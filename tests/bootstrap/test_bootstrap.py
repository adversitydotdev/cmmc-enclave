"""Tests for scripts/bootstrap. No AWS, no terraform: subprocess is mocked."""

import importlib.machinery
import importlib.util
import io
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
_loader = importlib.machinery.SourceFileLoader("bootstrap_script", str(REPO / "scripts/bootstrap"))
_spec = importlib.util.spec_from_loader("bootstrap_script", _loader)
bs = importlib.util.module_from_spec(_spec)
sys.modules["bootstrap_script"] = bs
_loader.exec_module(bs)

ORG_OUT = {
    "account_ids": {"value": {"management": "111111111111", "log_archive": "222222222222",
                              "security": "333333333333", "workload": "444444444444",
                              "grc": "555555555555"}},
    "organization_id": {"value": "o-abc1234567"},
    "organization_root_id": {"value": "r-ab12"},
    "ou_ids": {"value": {}},
}


def write_fixture(cfg: Path):
    (cfg / "terraform").mkdir(parents=True)
    (cfg / "ogrl/org").mkdir(parents=True)
    (cfg / "answers.json").write_text(json.dumps({"schema_version": "1", "generated_by": "test", "answers": {}}))
    (cfg / "checklist.md").write_text("steps\n")
    (cfg / "ogrl/org/bundle.yaml").write_text("id: bundle\n")
    (cfg / "terraform/org.auto.tfvars.json").write_text(json.dumps(
        {"name_prefix": "acme", "tier": "standard", "create_organization": True}))
    (cfg / "terraform/baseline.auto.tfvars.json").write_text(json.dumps(
        {"name_prefix": "acme", "tier": "standard", "fathom_oidc_client_id": "x"}))
    (cfg / "terraform/workspace.auto.tfvars.json").write_text(json.dumps(
        {"customer_id": "C0123", "impersonated_user_email": "a@example.com", "domain": "example.com"}))


class FakeProc:
    def __init__(self, rc, lines=()):
        self.stdout = iter(lines)
        self._rc = rc

    def wait(self):
        return self._rc


def is_pkg(cmd):
    return any("package-fathom-seed" in str(c) for c in cmd)


class Harness(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.cfg = self.tmp / "enclave-config"
        write_fixture(self.cfg)
        self.popen_calls = []   # (cmd, cwd)
        self.fail_if = None     # callable(cmd, cwd) -> bool
        self.org_exists = False
        self.clock = 1_000_000.0
        for target, fake in (("subprocess.run", self.fake_run), ("subprocess.Popen", self.fake_popen),
                             ("bootstrap_script.now", self.fake_now)):
            p = mock.patch(target, fake)
            p.start()
            self.addCleanup(p.stop)
        p = mock.patch.dict("os.environ", {"GOOGLEWORKSPACE_CREDENTIALS": "/tmp/key.json"})
        p.start()
        self.addCleanup(p.stop)

    def fake_now(self):
        self.clock += 60
        return self.clock

    def fake_run(self, cmd, cwd=None, **kw):
        j = " ".join(str(c) for c in cmd)
        out, rc, err = "", 0, ""
        if "terraform version" in j:
            out = json.dumps({"terraform_version": "1.17.2"})
        elif "tflint --version" in j:
            out = "TFLint version 0.66.0\n"
        elif "sts get-caller-identity" in j:
            out = json.dumps({"Account": "111111111111", "Arn": "arn:aws:iam::111111111111:user/x"})
        elif "describe-organization" in j:
            if self.org_exists:
                out = json.dumps({"Organization": {"Id": "o-1", "ManagementAccountId": "111111111111",
                                                   "FeatureSet": "ALL"}})
            else:
                rc, err = 254, "An error occurred (AWSOrganizationsNotInUseException)"
        elif "terraform output -json" in j:
            out = json.dumps(ORG_OUT)
        elif "command -v ogrl" in j:
            rc = 1
        return subprocess.CompletedProcess(cmd, rc, out, err)

    def fake_popen(self, cmd, cwd=None, **kw):
        self.popen_calls.append((cmd, cwd))
        if is_pkg(cmd):
            Path(cmd[3]).write_bytes(b"seed")
        rc = 1 if self.fail_if and self.fail_if(cmd, cwd) else 0
        return FakeProc(rc, ["output line\n"])

    def make(self, **kw):
        kw.setdefault("yes", True)
        self.out = io.StringIO()
        return bs.Bootstrap(self.cfg, out=self.out, config_arg="./enclave-config", **kw)

    def tf_calls(self):
        """(stack, subcommand) for each terraform call, in order."""
        return [(Path(cwd).name, cmd[cmd.index("terraform") + 1])
                for cmd, cwd in self.popen_calls if "terraform" in cmd and cwd]

    def state(self):
        return json.loads((self.cfg / ".bootstrap-state.json").read_text())


class TestStages(Harness):
    def test_stage_ordering(self):
        rc = self.make().run_all()
        self.assertEqual(rc, 0, self.out.getvalue())
        self.assertEqual(list(self.state()["stages"]), bs.STAGES)
        self.assertTrue(all(s["status"] == "complete" for s in self.state()["stages"].values()))
        want = [("org", "init"), ("org", "plan"), ("org", "apply"),
                ("baseline", "init"), ("baseline", "plan"), ("baseline", "apply"),
                ("workspace", "init"), ("workspace", "plan"), ("workspace", "apply"),
                ("baseline", "init"), ("baseline", "plan"), ("baseline", "apply"),
                ("baseline", "output")]
        self.assertEqual(self.tf_calls(), want)
        seed = [i for i, (c, _) in enumerate(self.popen_calls) if is_pkg(c)]
        self.assertEqual(len(seed), 1)

        def idx(stack, sub, n):
            return [i for i, (c, cwd) in enumerate(self.popen_calls)
                    if cwd and Path(cwd).name == stack and sub in c][n]
        # seed-package sits between workspace apply and baseline-2 init
        self.assertLess(idx("workspace", "apply", 0), seed[0])
        self.assertLess(seed[0], idx("baseline", "init", 1))

    def test_var_files_and_stage_vars(self):
        self.make().run_all()
        org, b1, ws, b2 = [c for c, _ in self.popen_calls if "plan" in c]
        self.assertIn(f"-var-file={self.cfg}/terraform/org.auto.tfvars.json", org)
        self.assertIn(f"-var-file={self.cfg}/terraform/baseline.auto.tfvars.json", b1)
        self.assertIn(f"-var-file={self.cfg}/terraform/baseline.org-outputs.auto.tfvars.json", b1)
        self.assertIn("-var=fathom_enable_services=false", b1)
        self.assertIn("-var=fathom_enable_services=true", b2)
        self.assertIn(f"-var=fathom_seed_bundle_path={self.cfg}/fathom-seed.tar.gz", b2)
        self.assertEqual(b1[:3], ["mise", "exec", "--"])
        pkg = [c for c, _ in self.popen_calls if is_pkg(c)][0]
        self.assertEqual(pkg[-2], "--library-ref")
        self.assertRegex(pkg[-1], r"^[0-9a-f]{40}$")
        self.assertEqual(pkg[2], str(self.cfg / "ogrl"))

    def test_org_outputs_format(self):
        self.make().run_all(only="org")
        data = json.loads((self.cfg / "terraform/baseline.org-outputs.auto.tfvars.json").read_text())
        self.assertEqual(data, {
            "account_ids": ORG_OUT["account_ids"]["value"],
            "organization_id": "o-abc1234567",
            "organization_root_id": "r-ab12",
        })

    def test_resume_skips_completed(self):
        self.fail_if = lambda cmd, cwd: bool(cwd) and Path(cwd).name == "workspace" and "apply" in cmd
        self.assertEqual(self.make().run_all(), 1)
        self.popen_calls.clear()
        self.fail_if = None
        org_before = self.state()["stages"]["org"]
        self.assertEqual(self.make().run_all(resume=True), 0, self.out.getvalue())
        self.assertIn("[org] already complete", self.out.getvalue())
        self.assertNotIn(("org", "init"), self.tf_calls())
        self.assertEqual(self.tf_calls()[0], ("workspace", "init"))
        self.assertEqual(self.state()["stages"]["org"], org_before)
        self.assertEqual(self.state()["stages"]["workspace"]["status"], "complete")

    def test_failure_recorded_and_resume_command(self):
        self.fail_if = lambda cmd, cwd: bool(cwd) and Path(cwd).name == "baseline" and "plan" in cmd
        b = self.make(profile="prod", backend_config=["backend.hcl"])
        self.assertEqual(b.run_all(), 1)
        st = self.state()["stages"]
        self.assertEqual(st["baseline-1"]["status"], "failed")
        self.assertEqual(st["baseline-1"]["error"]["rc"], 1)
        self.assertIn("plan", st["baseline-1"]["error"]["command"])
        self.assertEqual(st["baseline-1"]["error"]["log"], str(self.cfg / "logs/baseline-1.log"))
        self.assertNotIn("workspace", st)
        text = self.out.getvalue()
        self.assertIn("FAILED stage: baseline-1", text)
        self.assertIn(str(self.cfg / "logs/baseline-1.log"), text)
        self.assertIn("scripts/bootstrap --config ./enclave-config --resume --profile prod "
                      "--backend-config backend.hcl --yes", text)
        self.assertIn("output line", (self.cfg / "logs/baseline-1.log").read_text())

    def test_plan_only_stops_before_apply(self):
        rc = self.make(plan_only=True).run_all()
        self.assertEqual(rc, 0, self.out.getvalue())
        self.assertNotIn("apply", [s for _, s in self.tf_calls()])
        # baseline needs the org outputs, so it is skipped; workspace has no such dependency
        self.assertEqual(self.tf_calls(), [("org", "init"), ("org", "plan"),
                                           ("workspace", "init"), ("workspace", "plan")])
        self.assertFalse((self.cfg / "terraform/baseline.org-outputs.auto.tfvars.json").exists())
        st = self.state()["stages"]
        self.assertEqual(st["org"]["status"], "planned")
        self.assertNotEqual(st["baseline-1"]["status"], "complete")
        self.assertNotEqual(st["verify"]["status"], "complete")
        self.assertNotIn("Manual steps (do these now", self.out.getvalue())

    def test_plan_only_does_not_count_as_complete_on_resume(self):
        self.make(plan_only=True).run_all()
        self.popen_calls.clear()
        self.make().run_all(resume=True)
        self.assertIn(("org", "apply"), self.tf_calls())

    def test_decline_apply_stops_with_resume(self):
        b = self.make(yes=False)
        with mock.patch("builtins.input", return_value="n"):
            self.assertEqual(b.run_all(), 2)
        self.assertNotIn("apply", [s for _, s in self.tf_calls()])
        self.assertIn("--resume", self.out.getvalue())
        self.assertEqual(self.state()["stages"]["org"]["status"], "pending")

    def test_timing_recorded(self):
        self.make().run_all()
        for name, st in self.state()["stages"].items():
            self.assertRegex(st["start"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$", name)
            self.assertRegex(st["end"], r"^\d{4}-", name)
            self.assertEqual(st["duration_s"], 60, name)  # fake clock ticks 60s per reading
        text = self.out.getvalue()
        self.assertIn("Stage timing", text)
        self.assertIn("within the one-hour objective", text)

    def test_over_objective_flagged(self):
        step = [0]

        def jump():
            step[0] += 1
            return 1_000_000.0 + step[0] * 3000
        b = self.make()
        with mock.patch("bootstrap_script.now", jump):
            b.run_all()
        self.assertIn("OVER the one-hour objective", self.out.getvalue())

    def test_local_state_warning_and_backend_config(self):
        self.make().run_all(only="org")
        self.assertIn("LOCAL state", self.out.getvalue())
        self.popen_calls.clear()
        self.make(backend_config=["b-{stack}.hcl"]).run_all(only="org")
        self.assertNotIn("LOCAL state", self.out.getvalue())
        init = [c for c, _ in self.popen_calls if "init" in c][0]
        self.assertIn("-backend-config=b-org.hcl", init)

    def fake_repo(self, runbook=None):
        repo = self.tmp / "repo"
        shutil.copytree(REPO / "terraform", repo / "terraform")
        if runbook:
            (repo / "docs/runbook").mkdir(parents=True)
            (repo / "docs/runbook/workspace.md").write_text(runbook)
        return repo

    def test_manual_step_pointer_when_runbook_missing(self):
        b = self.make()
        b.repo = self.fake_repo()
        b.run_all(only="manual-workspace")
        text = self.out.getvalue()
        self.assertIn("#29", text)
        self.assertIn("fathom_oidc_client_id", text)
        self.assertIn("ACM certificate", text)

    def test_manual_step_lists_runbook_headings(self):
        b = self.make()
        b.repo = self.fake_repo("# Workspace runbook\n\n## 1. Admin console\ntext\n")
        b.run_all(only="manual-workspace")
        self.assertIn("## 1. Admin console", self.out.getvalue())

    def test_manual_step_waits_without_yes(self):
        b = self.make(yes=False)
        with mock.patch("builtins.input", return_value="n"):
            self.assertEqual(b.run_all(only="manual-workspace"), 2)


class TestPreflight(Harness):
    def run_preflight(self):
        rc = self.make().run_all(only="preflight")
        return rc, self.out.getvalue()

    def test_passes_on_good_fixture(self):
        rc, text = self.run_preflight()
        self.assertEqual(rc, 0, text)
        self.assertIn("PASS", text)
        self.assertNotIn("FAIL", text)

    def test_fails_on_leftover_placeholder(self):
        (self.cfg / "ogrl/org/policy.yaml").write_text("title: {{ company_name }}\n")
        rc, text = self.run_preflight()
        self.assertEqual(rc, 1)
        self.assertRegex(text, r'FAIL\s+config: no leftover "\{\{"')
        self.assertIn("ogrl/org/policy.yaml", text)
        self.assertEqual(self.state()["stages"]["preflight"]["status"], "failed")

    def test_fails_on_missing_file(self):
        (self.cfg / "terraform/workspace.auto.tfvars.json").unlink()
        rc, text = self.run_preflight()
        self.assertEqual(rc, 1)
        self.assertRegex(text, r"FAIL\s+config: required files")
        self.assertIn("terraform/workspace.auto.tfvars.json", text)

    def test_fails_on_wrong_schema_version(self):
        (self.cfg / "answers.json").write_text(json.dumps({"schema_version": "2"}))
        rc, text = self.run_preflight()
        self.assertEqual(rc, 1)
        self.assertRegex(text, r"FAIL\s+config: schema_version")

    def test_fails_on_undeclared_variable(self):
        (self.cfg / "terraform/org.auto.tfvars.json").write_text(json.dumps({"not_a_var": 1}))
        rc, text = self.run_preflight()
        self.assertEqual(rc, 1)
        self.assertIn("undeclared not_a_var", text)

    def test_fails_when_org_exists_and_create_true(self):
        self.org_exists = True
        rc, text = self.run_preflight()
        self.assertEqual(rc, 1)
        self.assertRegex(text, r"FAIL\s+aws: organization state")

    def test_fails_without_workspace_credentials(self):
        with mock.patch.dict("os.environ", {}, clear=True):
            rc, text = self.run_preflight()
        self.assertEqual(rc, 1)
        self.assertRegex(text, r"FAIL\s+workspace: GOOGLEWORKSPACE_CREDENTIALS")

    def test_fixture_tfvars_match_stack_variables(self):
        for stack in ("org", "baseline", "workspace"):
            declared = bs.declared_variables(REPO / "terraform/stacks" / stack)
            self.assertTrue(declared, stack)
            for f in (self.cfg / "terraform").glob(f"{stack}.*json"):
                self.assertLessEqual(set(json.loads(f.read_text())), declared, f.name)
        # the variables bootstrap itself writes or sets are declared by baseline
        self.assertLessEqual({"account_ids", "organization_id", "organization_root_id",
                              "fathom_enable_services", "fathom_seed_bundle_path", "ogrl_library_ref"},
                             bs.declared_variables(REPO / "terraform/stacks/baseline"))

    def test_library_ref_default_matches_ci(self):
        ci = re.search(r"OGRL_LIBRARY_REF:\s*([0-9a-f]{40})", (REPO / ".github/workflows/ogrl.yml").read_text())
        self.assertEqual(bs.default_library_ref(REPO), ci.group(1))


if __name__ == "__main__":
    unittest.main()
