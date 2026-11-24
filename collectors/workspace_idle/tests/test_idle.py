import contextlib
import io
import json
import os
import sys
import types
import unittest
from datetime import datetime, timezone
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import directory  # noqa: E402
import handler  # noqa: E402
import idle  # noqa: E402

NOW = datetime(2026, 11, 23, 12, 0, tzinfo=timezone.utc)
SECRET_PEM = "-----BEGIN PRIVATE KEY-----\nTOPSECRET\n-----END PRIVATE KEY-----\n"
OLD = "2026-01-01T00:00:00.000Z"  # 326 days before NOW
RECENT = "2026-11-01T00:00:00.000Z"  # 22 days before NOW


def user(uid, email, login=OLD, created=OLD, ou="/", **kw):
    return {
        "id": uid,
        "primaryEmail": email,
        "lastLoginTime": login,
        "creationTime": created,
        "orgUnitPath": ou,
        **kw,
    }


class Resp:
    def __init__(self, status, body=None):
        self.status_code = status
        self._body = body if body is not None else {}

    def json(self):
        return self._body


class FakeSession:
    """Serves user pages for GET and records PATCHes; patch_status maps user id to a status."""

    def __init__(self, pages, patch_status=None):
        self.pages = pages  # list of response bodies, served in order
        self.patch_status = patch_status or {}
        self.gets = []
        self.patches = []

    def get(self, url, params=None, timeout=None):
        self.gets.append((url, dict(params)))
        page = self.pages[len(self.gets) - 1] if len(self.gets) <= len(self.pages) else self.pages[-1]
        return page if isinstance(page, Resp) else Resp(200, page)

    def patch(self, url, json=None, timeout=None):
        uid = url.rsplit("/", 1)[1]
        self.patches.append((uid, json))
        return Resp(self.patch_status.get(uid, 200))


class FakeS3:
    def __init__(self):
        self.objects = {}

    def put_object(self, **kw):
        assert kw["Key"] not in self.objects, "Object Lock: key must be unique per run"
        self.objects[kw["Key"]] = kw


def no_sleep(_):
    pass


class DirectoryTests(unittest.TestCase):
    def test_pagination_follows_tokens_with_listing_params(self):
        s = FakeSession(
            [
                {"users": [user("1", "a@x")], "nextPageToken": "t1"},
                {"users": [user("2", "b@x")], "nextPageToken": "t2"},
                {"users": [user("3", "c@x")]},
            ]
        )
        got = [u["id"] for u in directory.list_users(s, sleep=no_sleep)]
        self.assertEqual(got, ["1", "2", "3"])
        self.assertEqual(s.gets[0][0], directory.BASE)
        self.assertEqual(s.gets[0][1]["customer"], "my_customer")
        self.assertEqual(s.gets[0][1]["projection"], "basic")
        self.assertNotIn("pageToken", s.gets[0][1])
        self.assertEqual(s.gets[2][1]["pageToken"], "t2")

    def test_retries_transient_then_gives_up(self):
        s = FakeSession([Resp(503), {"users": [user("1", "a@x")]}])
        self.assertEqual(len(list(directory.list_users(s, sleep=no_sleep))), 1)
        s = FakeSession([Resp(500)])
        with self.assertRaises(directory.DirectoryError):
            list(directory.list_users(s, sleep=no_sleep))
        self.assertEqual(len(s.gets), directory.MAX_TRIES)

    def test_forbidden_is_not_retried(self):
        s = FakeSession([Resp(403, {"error": {"errors": [{"reason": "forbidden"}]}})])
        with self.assertRaisesRegex(directory.DirectoryError, "403 forbidden"):
            list(directory.list_users(s, sleep=no_sleep))
        self.assertEqual(len(s.gets), 1)


class ScopeTests(unittest.TestCase):
    def test_scope_per_mode(self):
        self.assertEqual(
            directory.scope_for("report"), "https://www.googleapis.com/auth/admin.directory.user.readonly"
        )
        self.assertEqual(directory.scope_for("suspend"), "https://www.googleapis.com/auth/admin.directory.user")
        with self.assertRaises(ValueError):
            directory.scope_for("enforce")

    def test_build_session_requests_only_the_active_scope(self):
        seen = []

        class Creds:
            @staticmethod
            def from_service_account_info(info, scopes, subject):
                seen.append((list(scopes), subject))
                return object()

        mods = {
            "google": types.ModuleType("google"),
            "google.auth": types.ModuleType("google.auth"),
            "google.auth.transport": types.ModuleType("google.auth.transport"),
            "google.auth.transport.requests": types.SimpleNamespace(AuthorizedSession=lambda c: c),
            "google.oauth2": types.ModuleType("google.oauth2"),
            "google.oauth2.service_account": types.SimpleNamespace(Credentials=Creds),
        }
        mods["google.oauth2"].service_account = mods["google.oauth2.service_account"]
        mods["google.auth.transport"].requests = mods["google.auth.transport.requests"]
        with mock.patch.dict(sys.modules, mods):
            directory.build_session({}, "admin@x", "report")
            directory.build_session({}, "admin@x", "suspend")
        self.assertEqual(
            seen,
            [
                (["https://www.googleapis.com/auth/admin.directory.user.readonly"], "admin@x"),
                (["https://www.googleapis.com/auth/admin.directory.user"], "admin@x"),
            ],
        )


class SelectionTests(unittest.TestCase):
    def find(self, users, days=90, emails=(), ous=()):
        return idle.find_idle(users, NOW, days, emails, ous)

    def test_threshold_and_never_logged_in_uses_creation_time(self):
        users = [
            user("1", "old@x"),
            user("2", "recent@x", login=RECENT),
            user("3", "never-old@x", login=idle.NEVER, created=OLD),
            user("4", "never-new@x", login=idle.NEVER, created=RECENT),
            user("5", "nologin-field@x", created=RECENT),
        ]
        users[4].pop("lastLoginTime")
        got, excluded, scanned = self.find(users)
        self.assertEqual([u["id"] for u in got], ["1", "3"])
        self.assertEqual(got[0]["basis"], "lastLoginTime")
        self.assertEqual(got[1]["basis"], "creationTime")
        self.assertEqual(got[1]["daysIdle"], 326)
        self.assertEqual((excluded, scanned), ({}, 5))

    def test_days_is_configurable(self):
        users = [user("1", "a@x", login=RECENT)]
        self.assertEqual(self.find(users, days=90)[0], [])
        self.assertEqual(len(self.find(users, days=10)[0]), 1)

    def test_already_suspended_skipped(self):
        self.assertEqual(self.find([user("1", "a@x", suspended=True)])[0], [])

    def test_exclusions(self):
        users = [
            user("1", "root@x", isAdmin=True),
            user("2", "bg@x"),
            user("3", "BG2@X"),
            user("4", "svc@x", ou="/Service Accounts"),
            user("5", "svc2@x", ou="/Service Accounts/CI"),
            user("6", "lookalike@x", ou="/Service Accounts Old"),
            user("7", "idle@x", ou="/Staff"),
        ]
        got, excluded, _ = self.find(users, emails=["bg@x", "bg2@x"], ous=["/Service Accounts/"])
        self.assertEqual([u["id"] for u in got], ["6", "7"])
        self.assertEqual(excluded, {"super_admin": 1, "email": 2, "ou": 2})

    def test_excluded_only_counted_when_idle(self):
        got, excluded, _ = self.find([user("1", "root@x", login=RECENT, isAdmin=True)])
        self.assertEqual((got, excluded), ([], {}))


class HandlerTests(unittest.TestCase):
    ENV = {"BUCKET": "bkt", "KMS_KEY_ARN": "arn:kms:key", "EXCLUDE_EMAILS": "bg@x", "EXCLUDE_OUS": "/Svc"}

    def pages(self):
        return [
            {"users": [user("1", "a@x"), user("2", "b@x", login=RECENT)], "nextPageToken": "p"},
            {"users": [user("3", "bg@x"), user("4", "c@x", login=idle.NEVER), user("5", "root@x", isAdmin=True)]},
        ]

    def run_handler(self, session, env=None):
        out = io.StringIO()
        s3 = FakeS3()
        with contextlib.redirect_stdout(out):
            try:
                result = handler.run({**self.ENV, **(env or {})}, session, s3, NOW, "run1", sleep=no_sleep)
            except Exception as exc:
                return exc, out.getvalue(), s3
        return result, out.getvalue(), s3

    def report(self, s3):
        (obj,) = s3.objects.values()
        return json.loads(obj["Body"])

    def test_default_mode_is_report_and_never_writes(self):
        session = FakeSession(self.pages())
        result, out, s3 = self.run_handler(session)
        self.assertEqual(session.patches, [])
        self.assertEqual(result, {"scanned": 5, "idle": 2, "suspended": 0, "report": "workspace-idle/dt=2026-11-23/run1.json"})
        rep = self.report(s3)
        self.assertEqual(rep["mode"], "report")
        self.assertEqual({u["action"] for u in rep["users"]}, {"reported"})
        self.assertEqual(rep["excluded"], {"email": 1, "super_admin": 1})
        emf = json.loads(out.strip().splitlines()[-1])
        self.assertEqual((emf["Success"], emf["IdleUsers"], emf["Suspended"]), (1, 2, 0))
        self.assertEqual(emf["_aws"]["CloudWatchMetrics"][0]["Namespace"], "WorkspaceIdle")

    def test_suspend_mode_patches_only_idle_non_excluded(self):
        session = FakeSession(self.pages())
        result, out, s3 = self.run_handler(session, {"MODE": "suspend"})
        self.assertEqual(session.patches, [("1", {"suspended": True}), ("4", {"suspended": True})])
        self.assertEqual(result["suspended"], 2)
        rep = self.report(s3)
        self.assertEqual({u["action"] for u in rep["users"]}, {"suspended"})
        emf = json.loads(out.strip().splitlines()[-1])
        self.assertEqual((emf["IdleUsers"], emf["Suspended"]), (2, 2))

    def test_report_object_encryption_and_key_layout(self):
        _, _, s3 = self.run_handler(FakeSession(self.pages()))
        (key, obj), = s3.objects.items()
        self.assertEqual(key, "workspace-idle/dt=2026-11-23/run1.json")
        self.assertEqual(obj["ServerSideEncryption"], "aws:kms")
        self.assertEqual(obj["SSEKMSKeyId"], "arn:kms:key")
        self.assertEqual(self.report(s3)["idleDays"], 90)

    def test_idle_days_env(self):
        _, _, s3 = self.run_handler(FakeSession(self.pages()), {"IDLE_DAYS": "10"})
        self.assertEqual(self.report(s3)["idleUsers"], 3)  # 22 day old login now counts too

    def test_suspend_failure_raises_after_writing_report_and_no_success(self):
        session = FakeSession(self.pages(), patch_status={"1": 403})
        with self.assertLogs(level="ERROR") as logs:
            result, out, s3 = self.run_handler(session, {"MODE": "suspend"})
        self.assertIsInstance(result, RuntimeError)
        self.assertNotIn("Success", out)
        self.assertEqual([p[0] for p in session.patches], ["1", "4"])  # carries on past the failure
        rep = self.report(s3)
        self.assertEqual((rep["suspended"], rep["failed"]), (1, 1))
        self.assertEqual([u["action"] for u in rep["users"]], ["failed", "suspended"])
        self.assertTrue(any("user id 1" in m for m in logs.output))
        self.assertFalse(any("a@x" in m for m in logs.output))

    def test_listing_failure_raises_no_report_no_success(self):
        result, out, s3 = self.run_handler(FakeSession([Resp(403)]))
        self.assertIsInstance(result, directory.DirectoryError)
        self.assertEqual((out, s3.objects), ("", {}))

    def test_bad_mode_raises_before_any_call(self):
        session = FakeSession(self.pages())
        result, _, _ = self.run_handler(session, {"MODE": "enforce"})
        self.assertIsInstance(result, ValueError)
        self.assertEqual(session.gets, [])

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

    def test_key_absent_from_output_logs_and_report(self):
        session = FakeSession(self.pages(), patch_status={"1": 500})
        with self.assertLogs(level="INFO") as logs:
            _, out, s3 = self.run_handler(session, {"MODE": "suspend"})
        everything = out + "\n".join(logs.output) + next(iter(s3.objects.values()))["Body"].decode()
        self.assertNotIn("TOPSECRET", everything)
        self.assertNotIn("PRIVATE KEY", everything)


if __name__ == "__main__":
    unittest.main()
