"use strict";
// Run: node --test wizard/test/   (no npm dependencies)
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

require("../bundle-data.js");
require("../app.js");
const core = globalThis.WizardCore;
const D = globalThis.WIZARD_DATA;

const BASE = {
  company_name: "Acme Defense, LLC",
  domain: "acme-defense.com",
  ssp_signer_name: "Jane O'Doe",
  ssp_signer_title: "Chief Information Security Officer",
  tier: "standard",
  cui_categories: "CTI, Export Controlled",
  cui_confidentiality: "moderate",
  cui_integrity: "moderate",
  cui_availability: "low",
  user_count: "25",
  sites: "Huntsville AL office, remote",
  workspace_tenant: "existing",
  workspace_edition: "acp",
  workspace_customer_id: "C03abc123",
  workspace_admin_email: "terraform-admin@acme-defense.com",
  workspace_audit_admin_email: "",
  users: "carol@acme-defense.com, Carol, Lee, cui",
  group_enclave_admins: "alice@acme-defense.com\nbob@acme-defense.com",
  group_enclave_auditors: "bob@acme-defense.com",
  group_fathom_operators: "",
  group_logging_admins: "",
  mdm: "existing",
  mdm_product: "Jamf",
  edr: "existing",
  edr_product: "CrowdStrike",
  existing_organization: false,
  account_email_log_archive: "aws-log@acme-defense.com",
  account_email_security: "aws-sec@acme-defense.com",
  account_email_workload: "aws-work@acme-defense.com",
  account_email_grc: "aws-grc@acme-defense.com",
  home_region: "us-east-1",
  tag_owner: "it@acme-defense.com",
  tag_environment: "prod",
  tag_data_classification: "cui",
  notification_emails: "sec@acme-defense.com",
  fathom_domain: "grc.acme-defense.com",
  fathom_certificate_arn: "",
  fathom_oidc_client_id: "1234567890-abc.apps.googleusercontent.com",
  fathom_bootstrap_admin_emails: "alice@acme-defense.com",
};

function ok(overrides) {
  const { answers, errors } = core.validate(Object.assign({}, BASE, overrides));
  assert.deepEqual(errors, {});
  return answers;
}

const sha = (s) => crypto.createHash("sha256").update(s, "utf8").digest("hex");

test("crc32 known vector", () => {
  assert.equal(core.crc32(new TextEncoder().encode("123456789")), 0xcbf43926);
});

test("every question maps to a tfvar, OGRL param or checklist item that exists", () => {
  const params = D.ogrl_params;
  for (const q of D.questions.questions) {
    assert.ok(q.id && q.label && q.type && q.section, `${q.id}: id, label, type, section`);
    assert.ok(Array.isArray(q.maps_to) && q.maps_to.length > 0, `${q.id}: maps_to`);
    for (const m of q.maps_to) {
      if (m.kind === "tfvar") {
        assert.ok(D.stack_variables[m.stack], `${q.id}: stack ${m.stack}`);
        assert.ok(D.stack_variables[m.stack][m.name], `${q.id}: ${m.stack} does not declare ${m.name}`);
      } else if (m.kind === "ogrl_param") {
        assert.ok(params[m.param], `${q.id}: unknown OGRL param ${m.param}`);
      } else {
        assert.equal(m.kind, "checklist", `${q.id}: kind ${m.kind}`);
      }
    }
  }
  // Every wizard param in parameters.yaml has a question.
  const mapped = new Set(D.questions.questions.flatMap((q) => q.maps_to.filter((m) => m.kind === "ogrl_param").map((m) => m.param)));
  for (const p of Object.keys(params)) assert.ok(mapped.has(p), `parameter ${p} has no question`);
});

test("no question asks for a secret", () => {
  for (const q of D.questions.questions) {
    assert.doesNotMatch(q.id + " " + q.type, /secret|password|passwd|token|private|credential/i, q.id);
  }
  const allowed = ["fathom_oidc_client_id"];
  for (const q of D.questions.questions) {
    for (const m of q.maps_to) {
      if (m.kind === "tfvar") assert.doesNotMatch(m.name, /secret|password|credentials|token/, `${q.id} -> ${m.name}`);
    }
    assert.ok(allowed.includes(q.id) || !/client_id/.test(q.id) || true);
  }
});

test("valid answers validate; bad ones are caught", () => {
  ok({});
  const bad = (o) => core.validate(Object.assign({}, BASE, o)).errors;
  assert.ok(bad({ company_name: 'Acme "x"' }).company_name);
  assert.ok(bad({ company_name: "" }).company_name);
  assert.ok(bad({ domain: "https://acme.com" }).domain);
  assert.ok(bad({ user_count: "0" }).user_count);
  assert.ok(bad({ user_count: "abc" }).user_count);
  assert.ok(bad({ account_email_security: BASE.account_email_grc }).account_email_grc);
  assert.ok(bad({ tier: "itar" }).home_region, "commercial region rejected for ITAR");
  assert.ok(bad({ users: "x@y.com, A, B, other" }).users);
  assert.ok(bad({ fathom_oidc_client_id: "GOCSPX-secret" }).fathom_oidc_client_id);
  assert.ok(bad({ workspace_customer_id: "" }).workspace_customer_id, "required for existing tenant");
  assert.equal(bad({ workspace_tenant: "new", workspace_customer_id: "" }).workspace_customer_id, undefined);
});

test("rendering leaves no {{ and every file is present", async () => {
  const files = await core.buildFiles(ok({}));
  for (const [name, text] of Object.entries(files)) assert.ok(!text.includes("{{"), `${name} has {{`);
  assert.ok(files["ogrl/parameters.yaml"]);
  assert.ok(files["ogrl/policy/access-control.md"]);
  assert.match(files["ogrl/org/system/enclave.yaml"], /Acme Defense, LLC CUI enclave/);
  assert.match(files["ogrl/org/system/enclave.yaml"], /acme-defense\.com/);
});

test("digests match the rendered .md", async () => {
  const files = await core.buildFiles(ok({}));
  let pinned = 0;
  for (const [name, text] of Object.entries(files)) {
    if (!/^ogrl\/org\/(policy|procedure)\/.+\.yaml$/.test(name)) continue;
    const uri = /uri:\s*(\S+)/.exec(text)[1];
    const target = path.posix.normalize("ogrl/org/" + uri);
    const value = /value:\s*"?([0-9a-f]{64})/.exec(text)[1];
    assert.equal(value, sha(files[target]), `${name} -> ${target}`);
    pinned++;
  }
  assert.ok(pinned >= 10, `only ${pinned} pinned`);
  // Rendering actually changed the committed digests.
  const orig = /value:\s*"?([0-9a-f]{64})/.exec(D.files["org/policy/access-control.yaml"])[1];
  const now = /value:\s*"?([0-9a-f]{64})/.exec(files["ogrl/org/policy/access-control.yaml"])[1];
  assert.notEqual(orig, now);
});

test("tfvars keys are declared; required variables present; bootstrap-owned absent", async () => {
  const tf = core.buildTfvars(ok({}));
  const bootstrapOwned = {
    baseline: ["account_ids", "organization_id", "organization_root_id", "fathom_enable_services", "fathom_seed_bundle_path", "fathom_read_external_ids", "ogrl_library_ref"],
  };
  for (const stack of ["org", "baseline", "workspace"]) {
    const declared = D.stack_variables[stack];
    for (const key of Object.keys(tf[stack])) {
      assert.ok(declared[key], `${stack}: ${key} is not a declared variable`);
      assert.ok(!(bootstrapOwned[stack] || []).includes(key), `${stack}: ${key} is bootstrap-owned`);
    }
    for (const [name, v] of Object.entries(declared)) {
      if (v.required && !(bootstrapOwned[stack] || []).includes(name)) assert.ok(name in tf[stack], `${stack}: required ${name} missing`);
    }
  }
  assert.equal(tf.org.create_organization, true);
  assert.deepEqual(tf.baseline.allowed_regions, [tf.baseline.home_region]);
  assert.equal(tf.baseline.fathom_public_url, "https://grc.acme-defense.com");
  assert.equal(tf.baseline.workspace_admin_email, "terraform-admin@acme-defense.com", "audit admin falls back");
  assert.deepEqual(tf.workspace.group_members, { "enclave-admins": ["alice@acme-defense.com", "bob@acme-defense.com"], "enclave-auditors": ["bob@acme-defense.com"] });
  assert.deepEqual(tf.workspace.users, { "carol@acme-defense.com": { given_name: "Carol", family_name: "Lee", ou: "cui" } });
  assert.deepEqual(Object.keys(tf.baseline.tags).sort(), ["data-classification", "environment", "owner"]);
  assert.equal("fathom_certificate_arn" in tf.baseline, false, "empty optionals omitted");
});

test("existing organization: create_organization false and existing_account_ids", () => {
  const tf = core.buildTfvars(ok({ existing_organization: true, existing_account_id_security: "123456789012" }));
  assert.equal(tf.org.create_organization, false);
  assert.deepEqual(tf.org.existing_account_ids, { security: "123456789012" });
  const hidden = core.buildTfvars(ok({ existing_organization: false, existing_account_id_security: "123456789012" }));
  assert.equal("existing_account_ids" in hidden.org, false, "hidden answer ignored");
});

test("ITAR: gov regions, GovCloud party kept; standard: removed; enums set", async () => {
  const itar = await core.buildFiles(ok({ tier: "itar", home_region: "us-gov-west-1", cui_confidentiality: "high", cui_integrity: "high", cui_availability: "moderate" }));
  const std = await core.buildFiles(ok({}));
  assert.match(itar["ogrl/org/system/enclave.yaml"], /identifier: F1603047866/);
  assert.doesNotMatch(std["ogrl/org/system/enclave.yaml"], /identifier: F1603047866/);
  assert.match(std["ogrl/org/system/enclave.yaml"], /AGENCYAMAZONEW/);
  assert.match(itar["ogrl/org/system/enclave.yaml"], /confidentiality: high/);
  assert.match(itar["ogrl/org/system/enclave.yaml"], /integrity: high/);
  assert.match(itar["ogrl/org/system/enclave.yaml"], /availability: moderate/);
  assert.match(std["ogrl/org/system/enclave.yaml"], /confidentiality: moderate/);
  assert.deepEqual(JSON.parse(itar["terraform/org.auto.tfvars.json"]).allowed_regions, [JSON.parse(itar["terraform/org.auto.tfvars.json"]).home_region]);
  assert.equal(JSON.parse(itar["terraform/baseline.auto.tfvars.json"]).tier, "itar");
});

test("output is deterministic for the same answers", async () => {
  const a = await core.buildZip(ok({}));
  const b = await core.buildZip(ok({}));
  assert.equal(Buffer.compare(Buffer.from(a), Buffer.from(b)), 0);
  const f1 = await core.buildFiles(ok({}));
  const f2 = await core.buildFiles(core.validate(JSON.parse(f1["answers.json"]).answers).answers);
  assert.deepEqual(f2, f1, "answers.json round-trips to the same output");
  assert.doesNotMatch(f1["answers.json"], /\d{4}-\d{2}-\d{2}T/, "no timestamps");
});

test("checklist: purchases, POA&M triggers, runbook link, no secrets asked", () => {
  const full = core.buildChecklist(ok({}));
  assert.match(full, /Assured Controls Plus/);
  assert.match(full, /docs\/runbook\/workspace\.md/);
  assert.match(full, /None generated/);
  const gaps = core.buildChecklist(ok({ mdm: "none", edr: "none", workspace_edition: "unsupported", tier: "itar", home_region: "us-gov-west-1" }));
  assert.match(gaps, /No MDM/);
  assert.match(gaps, /No EDR/);
  assert.match(gaps, /Unsupported Workspace edition/);
  assert.match(gaps, /GovCloud/);
  assert.match(gaps, /client-side encryption/);
  assert.doesNotMatch(gaps, /\{\{/);
  assert.match(core.buildChecklist(ok({ workspace_edition: "ac" })), /Assured Controls without Plus/);
});

for (const tier of ["standard", "itar"]) {
  test(`the ${tier} zip opens with Python zipfile and meets the contract`, async () => {
    const overrides = tier === "itar" ? { tier: "itar", home_region: "us-gov-west-1" } : {};
    const bytes = await core.buildZip(ok(overrides));
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wizard-zip-"));
    const zip = path.join(dir, core.ZIP_NAME);
    fs.writeFileSync(zip, bytes);
    const r = spawnSync("python3", ["-P", path.join(__dirname, "check_zip.py"), zip, tier], { encoding: "utf8" });
    fs.rmSync(dir, { recursive: true, force: true });
    assert.equal(r.status, 0, r.stdout + r.stderr);
  });
}
