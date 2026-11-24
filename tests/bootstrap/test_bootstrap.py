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


class TestWorkspacePolicy(Harness):
    def policy_calls(self):
        return [c for c, _ in self.popen_calls if any("workspace-policy" in str(x) for x in c)]

    def test_applies_after_workspace_apply_before_seed_package(self):
        self.assertEqual(self.make().run_all(), 0, self.out.getvalue())
        cmds = [c for c, _ in self.popen_calls]
        (pol,) = self.policy_calls()
        self.assertIn("--apply", pol)
        self.assertNotIn("--dry-run", pol)
        self.assertEqual(pol[pol.index("--customer-id") + 1], "C0123")
        self.assertEqual(pol[pol.index("--cui-ou") + 1], "/CUI")
        self.assertEqual(pol[pol.index("--non-cui-ou") + 1], "/Non-CUI")
        self.assertEqual(pol[pol.index("--subject") + 1], "a@example.com")
        apply_i = next(i for i, (c, cwd) in enumerate(self.popen_calls)
                       if cwd and Path(cwd).name == "workspace" and "apply" in c)
        pol_i = cmds.index(pol)
        pkg_i = next(i for i, c in enumerate(cmds) if is_pkg(c))
        self.assertLess(apply_i, pol_i)
        self.assertLess(pol_i, pkg_i)

    def test_plan_only_runs_dry_run(self):
        self.assertEqual(self.make(plan_only=True).run_all(), 0, self.out.getvalue())
        (pol,) = self.policy_calls()
        self.assertIn("--dry-run", pol)
        self.assertNotIn("--apply", pol)

    def test_custom_ou_names_from_tfvars(self):
        f = self.cfg / "terraform/workspace.auto.tfvars.json"
        d = json.loads(f.read_text())
        d.update(cui_ou_name="Controlled", non_cui_ou_name="Other")
        f.write_text(json.dumps(d))
        self.make().run_all(only="workspace")
        (pol,) = self.policy_calls()
        self.assertEqual(pol[pol.index("--cui-ou") + 1], "/Controlled")
        self.assertEqual(pol[pol.index("--non-cui-ou") + 1], "/Other")

    def test_not_run_when_terraform_apply_declined(self):
        b = self.make(yes=False)
        with mock.patch("builtins.input", return_value="n"):
            self.assertEqual(b.run_all(only="workspace"), 2)
        self.assertEqual(self.policy_calls(), [])

    def test_policy_failure_fails_workspace_stage(self):
        self.fail_if = lambda cmd, cwd: any("workspace-policy" in str(x) for x in cmd)
        self.assertEqual(self.make().run_all(only="workspace"), 1)
        self.assertEqual(self.state()["stages"]["workspace"]["status"], "failed")

    def test_credentials_by_environment_not_argv(self):
        f = self.cfg / "terraform/workspace.auto.tfvars.json"
        d = json.loads(f.read_text())
        d["credentials"] = '{"private_key": "SECRET"}'
        f.write_text(json.dumps(d))
        with mock.patch.dict("os.environ", {}, clear=True):
            b = self.make()
            b.run_all(only="workspace")
        (pol,) = self.policy_calls()
        self.assertNotIn("SECRET", " ".join(pol))
        self.assertEqual(b.env["GOOGLEWORKSPACE_CREDENTIALS"], '{"private_key": "SECRET"}')

    def test_preflight_checks_policy_script_deps(self):
        rc = self.make().run_all(only="preflight")
        self.assertEqual(rc, 0)
        self.assertIn("workspace-policy deps", self.out.getvalue())


GOOD_ARN = "arn:aws:acm:us-gov-west-1:555555555555:certificate/12345678-abcd-ef01-2345-6789abcdef01"
GOOD_CLIENT = "1234567890-abc123def456.apps.googleusercontent.com"


class TestPrompts(Harness):
    def set_vars(self, stack, **kw):
        f = self.cfg / f"terraform/{stack}.auto.tfvars.json"
        d = json.loads(f.read_text())
        d.update(kw)
        for k in [k for k, v in d.items() if v is None]:
            del d[k]
        f.write_text(json.dumps(d))

    def tfv(self, stack):
        return json.loads((self.cfg / f"terraform/{stack}.auto.tfvars.json").read_text())

    def run_manual(self, answers, yes=False):
        b = self.make(yes=yes)
        with mock.patch("builtins.input", side_effect=answers) as inp:
            rc = b.run_all(only="manual-workspace")
        return rc, inp

    def test_prompts_for_missing_customer_id_and_writes_config(self):
        self.set_vars("workspace", customer_id=None)
        rc, inp = self.run_manual(["y", "C01a2b3c4"])
        self.assertEqual(rc, 0, self.out.getvalue())
        self.assertEqual(self.tfv("workspace")["customer_id"], "C01a2b3c4")
        self.assertIn("Account settings > Customer ID", inp.call_args_list[-1].args[0])
        self.assertEqual(self.tfv("workspace")["domain"], "example.com")  # other keys kept

    def test_no_prompt_when_present(self):
        rc, inp = self.run_manual(["y"])
        self.assertEqual(rc, 0)
        self.assertEqual(inp.call_count, 1)  # only "Manual steps done?"

    def test_invalid_customer_id_reprompts_then_accepts(self):
        self.set_vars("workspace", customer_id=None)
        rc, _ = self.run_manual(["y", "not-an-id", "c0123456", "C01a2b3c4"])
        self.assertEqual(rc, 0)
        self.assertEqual(self.tfv("workspace")["customer_id"], "C01a2b3c4")
        self.assertIn("not valid", self.out.getvalue())

    def test_three_invalid_answers_fail_stage(self):
        self.set_vars("workspace", customer_id=None)
        rc, _ = self.run_manual(["y", "x", "y", "z"])
        self.assertEqual(rc, 1)
        self.assertIn("customer_id", self.out.getvalue())
        self.assertNotIn("customer_id", self.tfv("workspace"))

    def test_yes_with_missing_customer_id_fails_without_prompt(self):
        self.set_vars("workspace", customer_id=None)
        rc, inp = self.run_manual([], yes=True)
        self.assertEqual(rc, 1)
        inp.assert_not_called()
        text = self.out.getvalue()
        self.assertIn("customer_id: missing", text)
        self.assertIn("Account settings > Customer ID", text)
        self.assertEqual(self.state()["stages"]["manual-workspace"]["status"], "failed")

    def test_fathom_values_prompted_when_domain_set(self):
        self.set_vars("baseline", fathom_domain_name="fathom.example.com", fathom_oidc_client_id=None)
        rc, _ = self.run_manual(["y", GOOD_CLIENT, GOOD_ARN])
        self.assertEqual(rc, 0, self.out.getvalue())
        d = self.tfv("baseline")
        self.assertEqual((d["fathom_oidc_client_id"], d["fathom_certificate_arn"]), (GOOD_CLIENT, GOOD_ARN))

    def test_fathom_values_not_prompted_without_domain(self):
        self.set_vars("baseline", fathom_oidc_client_id=None)
        rc, inp = self.run_manual(["y"])
        self.assertEqual(rc, 0)
        self.assertEqual(inp.call_count, 1)

    def test_empty_string_counts_as_missing(self):
        self.set_vars("baseline", fathom_domain_name="f.example.com", fathom_oidc_client_id="",
                      fathom_certificate_arn=GOOD_ARN)
        rc, _ = self.run_manual(["y", GOOD_CLIENT])
        self.assertEqual(rc, 0)
        self.assertEqual(self.tfv("baseline")["fathom_oidc_client_id"], GOOD_CLIENT)

    def test_baseline2_prompts_before_terraform(self):
        self.set_vars("baseline", fathom_domain_name="f.example.com", fathom_oidc_client_id=None)
        (self.cfg / "terraform/baseline.org-outputs.auto.tfvars.json").write_text("{}")
        (self.cfg / "fathom-seed.tar.gz").write_bytes(b"seed")
        b = self.make(yes=False)
        with mock.patch("builtins.input", side_effect=[GOOD_CLIENT, GOOD_ARN, "n"]):
            self.assertEqual(b.run_all(only="baseline-2"), 2)  # declined the apply, after prompting
        self.assertEqual(self.tfv("baseline")["fathom_oidc_client_id"], GOOD_CLIENT)
        self.assertEqual(self.tfv("baseline")["fathom_certificate_arn"], GOOD_ARN)

    def test_baseline2_yes_fails_before_terraform(self):
        self.set_vars("baseline", fathom_domain_name="f.example.com", fathom_oidc_client_id=None)
        (self.cfg / "fathom-seed.tar.gz").write_bytes(b"seed")
        self.assertEqual(self.make().run_all(only="baseline-2"), 1)
        self.assertEqual(self.popen_calls, [])
        self.assertIn("fathom_oidc_client_id: missing", self.out.getvalue())

    def test_workspace_stage_requires_customer_id_in_plan_only(self):
        self.set_vars("workspace", customer_id=None)
        self.assertEqual(self.make(plan_only=True).run_all(only="workspace"), 1)
        self.assertEqual(self.popen_calls, [])

    def test_formats(self):
        def ok(r, v):
            return bool(r.match(v))
        self.assertTrue(ok(bs.CUSTOMER_ID_RE, "C03abcd12"))
        for bad in ("", "03abcd12", "C1abcd123", "C0", "C0 12345678", "c03abcd12"):
            self.assertFalse(ok(bs.CUSTOMER_ID_RE, bad), bad)
        self.assertTrue(ok(bs.ACM_ARN_RE, GOOD_ARN))
        for bad in ("", GOOD_ARN.replace("acm", "iam"), GOOD_ARN[:-4], "certificate/1234"):
            self.assertFalse(ok(bs.ACM_ARN_RE, bad), bad)
        self.assertTrue(ok(bs.OAUTH_CLIENT_RE, GOOD_CLIENT))
        for bad in ("", "abc.apps.googleusercontent.com", GOOD_CLIENT + "x", "123-abc.example.com"):
            self.assertFalse(ok(bs.OAUTH_CLIENT_RE, bad), bad)


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
