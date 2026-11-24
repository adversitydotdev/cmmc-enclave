"""Tests for scripts/workspace-dlp with a fake HTTP layer (no network).

Run: python3 -I scripts/tests/test_workspace_dlp.py  (from the repo root)
"""
import contextlib
import copy
import importlib.machinery
import importlib.util
import io
import json
import re
import unittest
from pathlib import Path

PATH = str(Path(__file__).resolve().parent.parent / "workspace-dlp")
loader = importlib.machinery.SourceFileLoader("workspace_dlp", PATH)
spec = importlib.util.spec_from_loader("workspace_dlp", loader)
dlp = importlib.util.module_from_spec(spec)
loader.exec_module(dlp)

OU = "id:03ph8a2z1abc"
CUST = "C01234567"


class FakeHttp:
    def __init__(self, policies=None):
        self.policies = list(policies or [])
        self.calls = []
        self.n = 0

    def request(self, method, url, params=None, body=None):
        self.calls.append((method, url, params, copy.deepcopy(body)))
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
        return [c for c in self.calls if c[0] != "GET"]


def go(http, apply, **kw):
    args = dict(customer_id=CUST, org_unit=OU, categories=["CTI"], dissemination=True, apply=apply)
    args.update(kw)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        log = dlp.run(http, **args)
    return log, buf.getvalue()


class DryRun(unittest.TestCase):
    def test_dry_run_sends_nothing_and_prints_json(self):
        http = FakeHttp()
        log, out = go(http, apply=False)
        self.assertEqual(http.writes(), [])
        self.assertTrue(all(a == "create" for a, _ in log))
        docs = [json.loads(s) for s in re.split(r"(?<=\})\n(?=\{)", out.strip())]
        self.assertEqual(len(docs), len(log))
        self.assertTrue(all(d["method"] == "POST" for d in docs))

    def test_dry_run_without_http_layer(self):
        log, out = go(None, apply=False)
        self.assertEqual(len(log), 8)  # 5 detectors + 3 rules
        self.assertIn("would", out)


class Apply(unittest.TestCase):
    def test_first_apply_creates_then_second_is_noop(self):
        http = FakeHttp()
        log, _ = go(http, apply=True)
        creates = [n for a, n in log if a == "create"]
        self.assertEqual(len(creates), len(log))
        n_writes = len(http.writes())
        log2, _ = go(http, apply=True)
        self.assertTrue(all(a == "unchanged" for a, _ in log2), log2)
        self.assertEqual(len(http.writes()), n_writes)

    def test_changed_policy_is_patched_by_display_name(self):
        http = FakeHttp()
        go(http, apply=True)
        rule = next(p for p in http.policies if p["setting"]["value"]["display_name"].startswith("CUI: block external Drive"))
        rule["setting"]["value"]["state"] = "INACTIVE"
        log, _ = go(http, apply=True)
        self.assertEqual([x for x in log if x[0] != "unchanged"],
                         [("update", "CUI: block external Drive sharing")])
        patch = [c for c in http.writes() if c[0] == "PATCH"][-1]
        self.assertTrue(patch[1].endswith(rule["name"]))
        self.assertEqual(http.policies.count(rule), 1)

    def test_server_added_fields_do_not_cause_updates(self):
        http = FakeHttp()
        go(http, apply=True)
        for p in http.policies:
            p["setting"]["value"]["create_time"] = "2026-11-23T00:00:00Z"
        log, _ = go(http, apply=True)
        self.assertTrue(all(a == "unchanged" for a, _ in log))

    def test_rules_reference_detector_policy_names(self):
        http = FakeHttp()
        go(http, apply=True)
        rule = next(p for p in http.policies if p["setting"]["type"] == dlp.T_RULE)
        cond = rule["setting"]["value"]["condition"]["contentCondition"]
        self.assertIn("matches_regex_detector('policies/fake1')", cond)


class Shape(unittest.TestCase):
    def setUp(self):
        self.http = FakeHttp()
        go(self.http, apply=True)

    def test_envelope(self):
        for p in self.http.policies:
            self.assertEqual(p["customer"], "customers/" + CUST)
            self.assertEqual(p["policyQuery"]["orgUnit"], "orgUnits/03ph8a2z1abc")
            self.assertIn(p["setting"]["type"], (dlp.T_RULE, dlp.T_REGEX))

    def test_detectors_compile_and_match(self):
        dets = {p["setting"]["value"]["display_name"]: re.compile(p["setting"]["value"]["regular_expression"]["expression"])
                for p in self.http.policies if p["setting"]["type"] == dlp.T_REGEX}
        self.assertTrue(dets["CUI marking: banner"].search("CUI"))
        self.assertTrue(dets["CUI marking: banner"].search("CONTROLLED UNCLASSIFIED INFORMATION"))
        self.assertFalse(dets["CUI marking: banner"].search("cuisine"))
        self.assertTrue(dets["CUI marking: portion"].search("(CUI//SP-CTI) text"))
        self.assertTrue(dets["CUI marking: specified category"].search("CUI//SP-EXPT"))
        self.assertTrue(dets["CUI marking: selected categories"].search("CUI//SP-CTI"))
        self.assertFalse(dets["CUI marking: selected categories"].search("CUI//SP-PRVCY"))
        ldc = dets["CUI marking: dissemination control"]
        self.assertTrue(ldc.search("CUI//SP-CTI//NOFORN"))
        self.assertFalse(ldc.search("SECRET//NOFORN"))

    def test_rules(self):
        rules = {p["setting"]["value"]["display_name"]: p["setting"]["value"]
                 for p in self.http.policies if p["setting"]["type"] == dlp.T_RULE}
        self.assertEqual(len(rules), 3)
        d = rules["CUI: block external Drive sharing"]
        self.assertEqual(d["triggers"], ["google.workspace.drive.file.v1.share"])
        self.assertEqual(d["action"], {"driveAction": {"blockAccess": {}}})
        self.assertEqual(d["condition"]["trustCondition"],
                         "!organization_trust_target.matches_customer('customers/C01234567')")
        w = rules["CUI: warn on internal Drive sharing"]
        self.assertIn("warnUser", w["action"]["driveAction"])
        self.assertFalse(w["condition"]["trustCondition"].startswith("!"))
        g = rules["CUI: block outbound Gmail to external recipients"]
        self.assertEqual(g["triggers"], ["google.workspace.gmail.email.v1.send"])
        self.assertIn("blockContent", g["action"]["gmailAction"])
        for r in rules.values():
            self.assertEqual(r["state"], "ACTIVE")

    def test_options(self):
        specs = dlp.detector_specs([], dissemination=False)
        self.assertEqual(len(specs), 3)
        self.assertEqual(len(dlp.detector_specs(["cti", "prvcy"], True)), 5)
        self.assertEqual(len(dlp.rule_specs(["x"], CUST, drive_internal_warn=False)), 2)

    def test_list_filter_and_paging(self):
        class Paged(FakeHttp):
            def request(self, method, url, params=None, body=None):
                if method == "GET":
                    self.calls.append((method, url, params, None))
                    if not (params or {}).get("pageToken"):
                        return {"policies": [{"name": "policies/a"}], "nextPageToken": "t"}
                    return {"policies": [{"name": "policies/b"}]}
        h = Paged()
        got = dlp.list_policies(h, "customers/C1")
        self.assertEqual([p["name"] for p in got], ["policies/a", "policies/b"])
        self.assertIn('customer == "customers/C1"', h.calls[0][2]["filter"])
        self.assertEqual(h.calls[0][2]["pageSize"], 100)


if __name__ == "__main__":
    unittest.main()
