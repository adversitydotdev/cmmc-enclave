"""Tests for scripts/workspace-policy with a fake HTTP layer (no network).

Run: python3 -I scripts/tests/test_workspace_policy.py  (from the repo root)
"""
import contextlib
import copy
import importlib.machinery
import importlib.util
import io
import json
import unittest
from pathlib import Path

PATH = str(Path(__file__).resolve().parent.parent / "workspace-policy")
loader = importlib.machinery.SourceFileLoader("workspace_policy", PATH)
spec = importlib.util.spec_from_loader("workspace_policy", loader)
wp = importlib.util.module_from_spec(spec)
loader.exec_module(wp)

CUST = "C01234567"
OUS = {"CUI": "id:cui1", "Non-CUI": "id:non1"}


class FakeHttp:
    def __init__(self, policies=None, missing_ous=False):
        self.policies = list(policies or [])
        self.missing_ous = missing_ous
        self.calls = []
        self.n = 0

    def request(self, method, url, params=None, body=None):
        self.calls.append((method, url, params, copy.deepcopy(body)))
        if method == "GET" and "/orgunits/" in url:
            if self.missing_ous:
                raise RuntimeError("GET -> 404")
            name = url.rsplit("/orgunits/", 1)[1]
            return {"orgUnitId": OUS[name], "parentOrgUnitId": "id:root"}
        if method == "GET" and url.endswith("/policies"):
            return {"policies": copy.deepcopy(self.policies)}
        if method == "POST":
            self.n += 1
            p = copy.deepcopy(body)
            p["name"] = f"policies/fake{self.n}"
            self.policies.append(p)
            return {"name": f"operations/op{self.n}", "done": True}
        if method == "PATCH":
            name = url.split("/v1beta1/")[1]
            for p in self.policies:
                if p["name"] == name:
                    p["setting"] = copy.deepcopy(body["setting"])
            return {"name": "operations/patch", "done": True}
        raise AssertionError((method, url))

    def writes(self):
        return [c for c in self.calls if c[0] in ("POST", "PATCH")]


def go(http, apply, **kw):
    args = dict(customer_id=CUST, cui_ou="/CUI", non_cui_ou="/Non-CUI", root_ou=None, apply=apply)
    args.update(kw)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        log = wp.run(http, **args)
    return log, buf.getvalue()


def by_type(http, stype):
    return {p["policyQuery"]["orgUnit"]: p["setting"]["value"]
            for p in http.policies if p["setting"]["type"] == stype}


class TestPolicy(unittest.TestCase):
    def test_dry_run_sends_no_writes_and_prints_requests(self):
        http = FakeHttp()
        log, out = go(http, apply=False)
        self.assertEqual(http.writes(), [])
        self.assertEqual([a for a, _ in log], ["create"] * 4)
        self.assertEqual(out.count('"would": "create"'), 4)

    def test_dry_run_without_credentials_uses_placeholders(self):
        log, out = go(None, apply=False)
        self.assertEqual(len(log), 4)
        self.assertIn("orgUnits/<id of /CUI>", out)

    def test_dry_run_tolerates_ous_not_created_yet(self):
        http = FakeHttp(missing_ous=True)
        log, out = go(http, apply=False)
        self.assertEqual(len(log), 4)
        self.assertIn("<id of /CUI>", out)
        self.assertEqual(http.writes(), [])

    def test_apply_fails_when_ou_missing(self):
        with self.assertRaisesRegex(RuntimeError, "cannot resolve CUI OU"):
            go(FakeHttp(missing_ous=True), apply=True)

    def test_apply_creates_values_per_ou(self):
        http = FakeHttp()
        go(http, apply=True)
        self.assertEqual(by_type(http, wp.T_DRIVE), {"orgUnits/cui1": {"default_file_access": "PRIVATE_TO_OWNER"}})
        self.assertEqual(by_type(http, wp.T_MPA), {"orgUnits/root": {"multi_party_approval_state": "ENABLED"}})
        self.assertEqual(by_type(http, wp.T_PASSKEYS), {
            "orgUnits/cui1": {"allowed_passkeys_type": "HARDWARE_SECURITY_KEYS_ONLY"},
            "orgUnits/non1": {"allowed_passkeys_type": "HARDWARE_SECURITY_KEYS_ONLY"}})
        body = http.writes()[0][3]
        self.assertEqual(body["customer"], f"customers/{CUST}")

    def test_second_apply_is_noop(self):
        http = FakeHttp()
        go(http, apply=True)
        n = len(http.writes())
        log, _ = go(http, apply=True)
        self.assertEqual(len(http.writes()), n)
        self.assertEqual([a for a, _ in log], ["unchanged"] * 4)

    def test_server_added_fields_do_not_cause_updates(self):
        http = FakeHttp()
        go(http, apply=True)
        for p in http.policies:
            p["setting"]["value"]["updateTime"] = "2026-11-24T00:00:00Z"
        log, _ = go(http, apply=True)
        self.assertEqual([a for a, _ in log], ["unchanged"] * 4)

    def test_drifted_value_is_patched(self):
        http = FakeHttp()
        go(http, apply=True)
        for p in http.policies:
            if p["setting"]["type"] == wp.T_DRIVE:
                p["setting"]["value"] = {"default_file_access": "PRIMARY_AUDIENCE_WITH_LINK"}
        http.calls.clear()
        log, _ = go(http, apply=True)
        self.assertEqual([a for a, _ in log].count("update"), 1)
        self.assertEqual([c[0] for c in http.writes()], ["PATCH"])
        self.assertEqual(by_type(http, wp.T_DRIVE)["orgUnits/cui1"], wp.VALUE_DRIVE)

    def test_same_setting_other_ou_is_not_a_match(self):
        other = {"name": "policies/x", "policyQuery": {"orgUnit": "orgUnits/other"},
                 "setting": {"type": wp.T_DRIVE, "value": wp.VALUE_DRIVE}}
        http = FakeHttp([other])
        log, _ = go(http, apply=True)
        self.assertEqual([a for a, _ in log].count("create"), 4)

    def test_skip(self):
        http = FakeHttp()
        log, _ = go(http, apply=True, skip=["passkeys", "mpa"])
        self.assertEqual(len(log), 1)

    def test_explicit_ids_skip_directory_lookup(self):
        http = FakeHttp()
        go(http, apply=True, cui_ou="id:a", non_cui_ou="orgUnits/b", root_ou="id:r")
        self.assertFalse([c for c in http.calls if "/orgunits/" in c[1]])
        self.assertIn("orgUnits/r", by_type(http, wp.T_MPA))

    def test_list_filter_covers_only_our_types(self):
        http = FakeHttp()
        go(http, apply=False)
        flt = [c[2]["filter"] for c in http.calls if c[1].endswith("/policies")][0]
        self.assertIn(f'customer == "customers/{CUST}"', flt)
        for t in ("general_access_default", "require_approvals", "passkeys_restriction"):
            self.assertIn(t, flt)

    def test_payload_values_json_serializable(self):
        json.dumps(wp.plan("a", "b", "c"))


if __name__ == "__main__":
    unittest.main()
