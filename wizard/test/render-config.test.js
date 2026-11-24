"use strict";
// Run: node --test   (no npm dependencies)
// scripts/render-config must match the wizard's own render, byte for byte.
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

const REPO = path.join(__dirname, "..", "..");
const CLI = path.join(REPO, "scripts", "render-config");
const EXAMPLE = path.join(__dirname, "fixtures", "answers.example.json");

const made = [];
process.on("exit", () => made.forEach((d) => fs.rmSync(d, { recursive: true, force: true })));
function tmp() {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), "render-config-"));
  made.push(d);
  return d;
}

function cli(args) {
  return spawnSync(process.execPath, [CLI, ...args], { encoding: "utf8" });
}

function walk(dir, base = dir) {
  const out = {};
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) Object.assign(out, walk(p, base));
    else out[path.relative(base, p).split(path.sep).join("/")] = fs.readFileSync(p);
  }
  return out;
}

function answersOf(file) {
  return core.validate(JSON.parse(fs.readFileSync(file, "utf8")).answers);
}

const variants = {
  standard: EXAMPLE,
};
{
  // ITAR variant derived from the example, so it cannot rot separately.
  const doc = JSON.parse(fs.readFileSync(EXAMPLE, "utf8"));
  Object.assign(doc.answers, { tier: "itar", home_region: "us-gov-west-1" });
  const f = path.join(tmp(), "itar.json");
  fs.writeFileSync(f, JSON.stringify(doc));
  variants.itar = f;
}

const rendered = {};
for (const [name, file] of Object.entries(variants)) {
  const out = path.join(tmp(), "cfg");
  const zip = path.join(tmp(), "enclave-config-v1.zip");
  const r = cli(["--answers", file, "--out", out, "--zip", zip]);
  assert.equal(r.status, 0, r.stderr);
  rendered[name] = { out, zip, file };
}

for (const name of Object.keys(variants)) {
  test(`${name}: CLI output is byte-identical to the wizard's render`, async () => {
    const { out, zip, file } = rendered[name];
    const { answers, errors } = answersOf(file);
    assert.deepEqual(errors, {});
    const want = await core.buildFiles(answers);
    const got = walk(out);
    assert.deepEqual(Object.keys(got).sort(), Object.keys(want).sort());
    for (const [n, text] of Object.entries(want)) {
      assert.equal(Buffer.compare(got[n], Buffer.from(text, "utf8")), 0, `${n} differs`);
    }
    assert.equal(Buffer.compare(fs.readFileSync(zip), Buffer.from(await core.buildZip(answers))), 0, "zip differs");
    for (const n of ["answers.json", "checklist.md", "terraform/org.auto.tfvars.json", "terraform/baseline.auto.tfvars.json", "terraform/workspace.auto.tfvars.json"]) {
      assert.ok(got[n], n);
    }
  });

  test(`${name}: no {{ left`, () => {
    for (const [n, buf] of Object.entries(walk(rendered[name].out))) {
      assert.ok(!buf.toString("utf8").includes("{{"), `${n} holds {{`);
    }
  });

  test(`${name}: every org document digest matches its rendered body`, () => {
    const root = path.join(rendered[name].out, "ogrl");
    let checked = 0;
    for (const kind of ["policy", "procedure"]) {
      const dir = path.join(root, "org", kind);
      for (const f of fs.readdirSync(dir).filter((x) => x.endsWith(".yaml"))) {
        const text = fs.readFileSync(path.join(dir, f), "utf8");
        const uri = /^\s*uri:\s*(\S+)/m.exec(text)[1];
        const want = /value:\s*"?([0-9a-f]{64})"?/.exec(text)[1];
        const body = fs.readFileSync(path.join(root, "org", uri));
        assert.equal(crypto.createHash("sha256").update(body).digest("hex"), want, `${kind}/${f}`);
        checked++;
      }
    }
    assert.ok(checked > 0);
  });

  test(`${name}: package-fathom-seed accepts the output`, (t) => {
    const probe = spawnSync("python3", ["-c", "import yaml"]);
    if (probe.status !== 0) return t.skip("python3 with PyYAML not available");
    const tf = fs.readFileSync(path.join(REPO, "terraform/stacks/baseline/fathom_seed.tf"), "utf8");
    const ref = /variable "ogrl_library_ref"[\s\S]*?default\s*=\s*"([0-9a-f]{40})"/.exec(tf)[1];
    const tarball = path.join(tmp(), "seed.tar.gz");
    const r = spawnSync("python3", ["-P", path.join(REPO, "scripts/package-fathom-seed"), path.join(rendered[name].out, "ogrl"), tarball, "--library-ref", ref], { encoding: "utf8" });
    assert.equal(r.status, 0, r.stdout + r.stderr);
    assert.ok(fs.statSync(tarball).size > 0);
  });

  test(`${name}: bootstrap preflight config checks pass`, (t) => {
    if (spawnSync("python3", ["--version"]).status !== 0) return t.skip("python3 not available");
    const py = [
      "import importlib.machinery, importlib.util, io, json, sys",
      "from pathlib import Path",
      "repo = Path(sys.argv[1])",
      "loader = importlib.machinery.SourceFileLoader('bootstrap_script', str(repo / 'scripts/bootstrap'))",
      "spec = importlib.util.spec_from_loader('bootstrap_script', loader)",
      "bs = importlib.util.module_from_spec(spec)",
      "sys.modules['bootstrap_script'] = bs",
      "loader.exec_module(bs)",
      "b = bs.Bootstrap(Path(sys.argv[2]), out=io.StringIO(), config_arg=sys.argv[2])",
      "print(json.dumps(b.check_config()))",
    ].join("\n");
    const r = spawnSync("python3", ["-P", "-c", py, REPO, rendered[name].out], { encoding: "utf8" });
    assert.equal(r.status, 0, r.stderr);
    const checks = JSON.parse(r.stdout);
    assert.ok(checks.length >= 4);
    for (const [label, passed, detail] of checks) assert.ok(passed, `${label}: ${detail}`);
  });
}

test("accepts a bare answers map and matches the wrapped form", () => {
  const doc = JSON.parse(fs.readFileSync(EXAMPLE, "utf8"));
  const f = path.join(tmp(), "bare.json");
  fs.writeFileSync(f, JSON.stringify(doc.answers));
  const out = path.join(tmp(), "cfg");
  const r = cli(["--answers", f, "--out", out]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(walk(out), walk(rendered.standard.out));
});

test("invalid answers: lists each error, writes nothing, exit 1", () => {
  const doc = JSON.parse(fs.readFileSync(EXAMPLE, "utf8"));
  doc.answers.domain = "not a domain";
  doc.answers.company_name = "";
  const f = path.join(tmp(), "bad.json");
  fs.writeFileSync(f, JSON.stringify(doc));
  const out = path.join(tmp(), "cfg");
  const r = cli(["--answers", f, "--out", out]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /company_name: Required/);
  assert.match(r.stderr, /domain: /);
  assert.equal(fs.existsSync(out), false);
});

test("rejects unknown ids, wrong schema_version, non-empty out dir", () => {
  const doc = JSON.parse(fs.readFileSync(EXAMPLE, "utf8"));
  const dir = tmp();
  const typo = path.join(dir, "typo.json");
  fs.writeFileSync(typo, JSON.stringify({ schema_version: "1", answers: Object.assign({}, doc.answers, { dommain: "x" }) }));
  assert.match(cli(["--answers", typo, "--out", path.join(dir, "a")]).stderr, /unknown answer id.*dommain/);
  const v = path.join(dir, "v.json");
  fs.writeFileSync(v, JSON.stringify({ schema_version: "9", answers: doc.answers }));
  assert.match(cli(["--answers", v, "--out", path.join(dir, "b")]).stderr, /schema_version/);
  const r = cli(["--answers", EXAMPLE, "--out", rendered.standard.out]);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /not empty/);
  assert.equal(cli(["--answers", EXAMPLE, "--out", rendered.standard.out, "--force"]).status, 0);
});

test("--help says how to get answers.json", () => {
  const r = cli(["--help"]);
  assert.equal(r.status, 0);
  assert.match(r.stdout, /Resume from a saved answers\.json/);
  assert.match(r.stdout, /by hand/i);
});

test("the example answers file is secret-free", () => {
  assert.doesNotMatch(fs.readFileSync(EXAMPLE, "utf8"), /secret|password|AKIA|BEGIN [A-Z ]*PRIVATE/i);
});
