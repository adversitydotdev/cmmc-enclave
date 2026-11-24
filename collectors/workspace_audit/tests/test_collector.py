import contextlib
import gzip
import io
import json
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import collector  # noqa: E402
import handler  # noqa: E402
import reports  # noqa: E402
from state import DynamoState  # noqa: E402

NOW = datetime(2026, 11, 23, 12, 0, tzinfo=timezone.utc)
SECRET_PEM = "-----BEGIN PRIVATE KEY-----\nTOPSECRET\n-----END PRIVATE KEY-----\n"


def ev(time, uq, app="login", actor="a@example.com"):
    return {
        "kind": "admin#reports#activity",
        "id": {"time": time, "uniqueQualifier": uq, "applicationName": app, "customerId": "C0"},
        "actor": {"email": actor},
        "events": [{"type": "login", "name": "login_success"}],
    }


class Resp:
    def __init__(self, status, body=None):
        self.status_code = status
        self._body = body if body is not None else {}

    def json(self):
        return self._body


class FakeSession:
    """Serves canned responses per application; records every request."""

    def __init__(self, responses):
        self.responses = responses  # app -> list of Resp, consumed in order
        self.calls = []

    def get(self, url, params=None, timeout=None):
        app = url.split("/applications/")[1]
        self.calls.append((app, dict(params)))
        queue = self.responses[app]
        return queue.pop(0) if len(queue) > 1 else queue[0]


class FakeS3:
    def __init__(self):
        self.objects = {}

    def put_object(self, **kw):
        assert kw["Key"] not in self.objects, "Object Lock: key must be unique per run"
        self.objects[kw["Key"]] = kw


class FakeState:
    def __init__(self):
        self.items = {}

    def get(self, app):
        return self.items.get(app)

    def put(self, app, cursor, seen):
        self.items[app] = {"cursor": cursor, "seen": list(seen)}


def read_events(obj):
    return [json.loads(line) for line in gzip.decompress(obj["Body"]).decode().splitlines()]


def no_sleep(_):
    pass


class FetchTests(unittest.TestCase):
    def test_pagination_follows_tokens(self):
        s = FakeSession(
            {
                "login": [
                    Resp(200, {"items": [ev("2026-11-23T10:00:00.000Z", "1")], "nextPageToken": "p2"}),
                    Resp(200, {"items": [ev("2026-11-23T10:01:00.000Z", "2")], "nextPageToken": "p3"}),
                    Resp(200, {"items": [ev("2026-11-23T10:02:00.000Z", "3")]}),
                ]
            }
        )
        items = list(reports.fetch_activities(s, "login", NOW - timedelta(hours=3)))
        self.assertEqual([i["id"]["uniqueQualifier"] for i in items], ["1", "2", "3"])
        self.assertNotIn("pageToken", s.calls[0][1])
        self.assertEqual([c[1].get("pageToken") for c in s.calls[1:]], ["p2", "p3"])
        self.assertEqual(s.calls[0][1]["startTime"], "2026-11-23T09:00:00.000Z")

    def test_retries_transient_errors(self):
        s = FakeSession({"login": [Resp(503), Resp(429), Resp(200, {"items": [ev("2026-11-23T10:00:00.000Z", "1")]})]})
        self.assertEqual(len(list(reports.fetch_activities(s, "login", NOW, sleep=no_sleep))), 1)
        self.assertEqual(len(s.calls), 3)

    def test_gives_up_after_retries(self):
        s = FakeSession({"login": [Resp(500)]})
        with self.assertRaises(reports.ReportsError):
            list(reports.fetch_activities(s, "login", NOW, sleep=no_sleep))
        self.assertEqual(len(s.calls), reports.MAX_TRIES)

    def test_unavailable_app(self):
        body = {"error": {"errors": [{"reason": "invalid"}]}}
        s = FakeSession({"mobile": [Resp(400, body)]})
        with self.assertRaises(reports.AppUnavailable) as cm:
            list(reports.fetch_activities(s, "mobile", NOW))
        self.assertEqual(cm.exception.reason, "invalid")


class CollectTests(unittest.TestCase):
    def test_first_run_uses_lookback_and_cursor_is_max_time(self):
        s = FakeSession({"login": [Resp(200, {"items": [ev("2026-11-23T11:00:00.000Z", "2"), ev("2026-11-23T10:00:00.000Z", "1")]})]})
        st = FakeState()
        events, cursor, seen = collector.collect_app(s, st, "login", NOW, timedelta(hours=6), timedelta(hours=24))
        self.assertEqual(s.calls[0][1]["startTime"], "2026-11-22T12:00:00.000Z")
        self.assertEqual(cursor, "2026-11-23T11:00:00.000Z")
        self.assertEqual([e["id"]["uniqueQualifier"] for e in events], ["1", "2"])
        self.assertEqual(len(seen), 2)

    def test_overlap_rereads_and_dedupes_and_catches_late_events(self):
        overlap = timedelta(hours=6)
        e1, e2 = ev("2026-11-23T10:00:00.000Z", "1"), ev("2026-11-23T11:00:00.000Z", "2")
        st = FakeState()
        s1 = FakeSession({"login": [Resp(200, {"items": [e1, e2]})]})
        new, cur, seen = collector.collect_app(s1, st, "login", NOW, overlap, timedelta(hours=24))
        st.put("login", cur, seen)
        self.assertEqual(len(new), 2)

        # Next run: Google now also reports a delayed event stamped before e2.
        late = ev("2026-11-23T10:30:00.000Z", "9")
        e3 = ev("2026-11-23T11:30:00.000Z", "3")
        s2 = FakeSession({"login": [Resp(200, {"items": [e3, e2, late, e1]})]})
        new, cur, seen = collector.collect_app(s2, st, "login", NOW, overlap, timedelta(hours=24))
        self.assertEqual(s2.calls[0][1]["startTime"], "2026-11-23T05:00:00.000Z")  # cursor 11:00 - 6h
        self.assertEqual(sorted(e["id"]["uniqueQualifier"] for e in new), ["3", "9"])
        self.assertEqual(cur, "2026-11-23T11:30:00.000Z")
        self.assertEqual(len(seen), 4)

    def test_same_time_different_qualifier_is_distinct_and_dupes_within_run_dropped(self):
        a, b = ev("2026-11-23T10:00:00.000Z", "1"), ev("2026-11-23T10:00:00.000Z", "2")
        s = FakeSession({"login": [Resp(200, {"items": [a, b, a]})]})
        new, _, _ = collector.collect_app(s, FakeState(), "login", NOW, timedelta(hours=1), timedelta(hours=24))
        self.assertEqual(len(new), 2)

    def test_seen_pruned_below_next_start(self):
        old = ev("2026-11-23T01:00:00.000Z", "old")
        st = FakeState()
        st.put("login", "2026-11-23T05:00:00.000Z", [collector.event_key(old)])
        new_ev = ev("2026-11-23T11:00:00.000Z", "n")
        s = FakeSession({"login": [Resp(200, {"items": [new_ev]})]})
        _, cur, seen = collector.collect_app(s, st, "login", NOW, timedelta(hours=6), timedelta(hours=24))
        self.assertEqual(cur, "2026-11-23T11:00:00.000Z")
        self.assertEqual(seen, [collector.event_key(new_ev)])

    def test_no_events_keeps_cursor(self):
        st = FakeState()
        st.put("login", "2026-11-23T05:00:00.000Z", [])
        s = FakeSession({"login": [Resp(200, {})]})
        new, cur, _ = collector.collect_app(s, st, "login", NOW, timedelta(hours=6), timedelta(hours=24))
        self.assertEqual((new, cur), ([], "2026-11-23T05:00:00.000Z"))


class WriteTests(unittest.TestCase):
    def test_key_layout_encryption_and_content(self):
        s3 = FakeS3()
        events = [ev("2026-11-23T10:05:00.000Z", "1"), ev("2026-11-23T10:55:00.000Z", "2"), ev("2026-11-23T23:59:59.000Z", "3")]
        keys = collector.write_events(s3, "bkt", "arn:kms:key", "drive", events, "run123")
        self.assertEqual(
            keys,
            [
                "workspace-audit/application=drive/dt=2026-11-23/10-run123.jsonl.gz",
                "workspace-audit/application=drive/dt=2026-11-23/23-run123.jsonl.gz",
            ],
        )
        obj = s3.objects[keys[0]]
        self.assertEqual(obj["ServerSideEncryption"], "aws:kms")
        self.assertEqual(obj["SSEKMSKeyId"], "arn:kms:key")
        self.assertEqual(obj["Bucket"], "bkt")
        self.assertEqual([e["id"]["uniqueQualifier"] for e in read_events(obj)], ["1", "2"])

    def test_no_events_writes_nothing(self):
        s3 = FakeS3()
        self.assertEqual(collector.write_events(s3, "b", "k", "login", [], "r"), [])
        self.assertEqual(s3.objects, {})

    def test_unique_keys_across_runs(self):
        s3 = FakeS3()
        e = [ev("2026-11-23T10:05:00.000Z", "1")]
        collector.write_events(s3, "b", "k", "login", e, collector.new_run_id())
        collector.write_events(s3, "b", "k", "login", e, collector.new_run_id())
        self.assertEqual(len(s3.objects), 2)


class FakeDynamo:
    def __init__(self):
        self.items = {}

    def put_item(self, TableName, Item):
        self.items[Item["application"]["S"]] = Item

    def get_item(self, TableName, Key, ConsistentRead):
        item = self.items.get(Key["application"]["S"])
        return {"Item": item} if item else {}


class StateTests(unittest.TestCase):
    def test_round_trip(self):
        st = DynamoState(FakeDynamo(), "tbl")
        self.assertIsNone(st.get("login"))
        st.put("login", "2026-11-23T10:00:00.000Z", {"b|2", "a|1"})
        self.assertEqual(st.get("login"), {"cursor": "2026-11-23T10:00:00.000Z", "seen": ["a|1", "b|2"]})


class HandlerTests(unittest.TestCase):
    ENV = {"BUCKET": "bkt", "KMS_KEY_ARN": "arn:kms:key", "APPLICATIONS": "login,mobile,admin"}

    def run_handler(self, session, env=None, state=None):
        out = io.StringIO()
        s3 = FakeS3()
        state = state or FakeState()
        with contextlib.redirect_stdout(out):
            try:
                result = handler.run(env or self.ENV, session, state, s3, NOW, "run1", sleep=no_sleep)
            except Exception as exc:
                return exc, out.getvalue(), s3, state
        return result, out.getvalue(), s3, state

    def test_success_skips_unavailable_and_emits_emf(self):
        session = FakeSession(
            {
                "login": [Resp(200, {"items": [ev("2026-11-23T10:00:00.000Z", "1")]})],
                "mobile": [Resp(403, {"error": {"errors": [{"reason": "forbidden"}]}})],
                "admin": [Resp(200, {"items": [ev("2026-11-23T10:00:00.000Z", "2", app="admin")]})],
            }
        )
        with self.assertLogs(level="WARNING") as logs:
            result, out, s3, state = self.run_handler(session)
        self.assertEqual(result, {"records": 2, "applications": 2, "objects": 2})
        self.assertTrue(any("skipping application mobile" in m for m in logs.output))
        self.assertNotIn("mobile", state.items)
        emf = json.loads(out.strip().splitlines()[-1])
        self.assertEqual((emf["Success"], emf["Records"], emf["Applications"]), (1, 2, 2))
        self.assertEqual(emf["_aws"]["CloudWatchMetrics"][0]["Namespace"], "WorkspaceAudit")

    def test_failure_raises_no_success_metric_and_other_apps_progress(self):
        session = FakeSession(
            {
                "login": [Resp(500)],
                "mobile": [Resp(200, {})],
                "admin": [Resp(200, {"items": [ev("2026-11-23T10:00:00.000Z", "2", app="admin")]})],
            }
        )
        result, out, s3, state = self.run_handler(session)
        self.assertIsInstance(result, RuntimeError)
        self.assertIn("login", str(result))
        self.assertNotIn("Success", out)
        self.assertNotIn("login", state.items)  # cursor not advanced on failure
        self.assertIn("admin", state.items)

    def test_all_unavailable_raises(self):
        r403 = Resp(403, {"error": {"errors": [{"reason": "forbidden"}]}})
        session = FakeSession({"login": [r403], "mobile": [r403], "admin": [r403]})
        with self.assertLogs(level="WARNING"):
            result, out, _, _ = self.run_handler(session)
        self.assertIsInstance(result, RuntimeError)
        self.assertNotIn("Success", out)

    def test_emits_zero_record_run(self):
        session = FakeSession({"login": [Resp(200, {})]})
        result, out, _, _ = self.run_handler(session, env={**self.ENV, "APPLICATIONS": "login"})
        self.assertEqual(result["records"], 0)
        self.assertEqual(json.loads(out)["Success"], 1)

    def test_per_app_overlap_override(self):
        session = FakeSession({"login": [Resp(200, {})]})
        state = FakeState()
        state.put("login", "2026-11-23T10:00:00.000Z", [])
        env = {**self.ENV, "APPLICATIONS": "login", "OVERLAP_HOURS_BY_APP": '{"login": 2}'}
        self.run_handler(session, env=env, state=state)
        self.assertEqual(session.calls[0][1]["startTime"], "2026-11-23T08:00:00.000Z")

    def test_secret_never_logged(self):
        class Secrets:
            def get_secret_value(self, SecretId):
                return {"SecretString": "{not json " + SECRET_PEM}

        with self.assertRaises(RuntimeError) as cm:
            handler.load_key(Secrets(), "arn:secret")
        self.assertNotIn("TOPSECRET", str(cm.exception))
        self.assertIsNone(cm.exception.__cause__)

        class GoodSecrets:
            def get_secret_value(self, SecretId):
                return {"SecretString": json.dumps({"client_email": "sa@x", "private_key": SECRET_PEM})}

        self.assertEqual(handler.load_key(GoodSecrets(), "arn")["client_email"], "sa@x")

    def test_scope_is_the_single_readonly_scope(self):
        self.assertEqual(reports.SCOPE, "https://www.googleapis.com/auth/admin.reports.audit.readonly")


if __name__ == "__main__":
    unittest.main()
