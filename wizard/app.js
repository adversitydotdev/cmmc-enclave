// CMMC enclave wizard. Runs offline: no network access of any kind. The only
// thing that leaves the page is the zip the user downloads.
//
// Two halves in one file:
//   1. Core (no DOM): validation, tfvars, OGRL rendering, checklist, zip.
//      Exported as globalThis.WizardCore so `node --test` can use it.
//   2. UI (only when a document exists): form driven by questions.json.
//
// Output contract: enclave-config-v1.zip (see questions.json schema_version).
(function (root) {
  "use strict";

  const CONFIG_DIR = "enclave-config";
  const ZIP_NAME = "enclave-config-v1.zip";
  const ALLOWED_REGIONS = {
    standard: ["us-east-1", "us-east-2", "us-west-2"],
    itar: ["us-gov-west-1", "us-gov-east-1"],
  };

  // ---------------------------------------------------------------- helpers

  function data() {
    if (!root.WIZARD_DATA) throw new Error("bundle-data.js is not loaded");
    return root.WIZARD_DATA;
  }

  function sortKeys(value) {
    if (Array.isArray(value)) return value.map(sortKeys);
    if (value && typeof value === "object") {
      const out = {};
      for (const k of Object.keys(value).sort()) out[k] = sortKeys(value[k]);
      return out;
    }
    return value;
  }

  function stableJson(value) {
    return JSON.stringify(sortKeys(value), null, 2) + "\n";
  }

  function isEmpty(v) {
    return v === undefined || v === null || v === "" || (Array.isArray(v) && v.length === 0);
  }

  function questions() {
    return data().questions.questions;
  }

  function byId(id) {
    return questions().find((q) => q.id === id);
  }

  // ------------------------------------------------------- question helpers

  function optionsFor(q, answers) {
    if (q.options) return q.options;
    if (q.options_by) {
      const key = answers[q.options_by.question];
      return q.options_by.values[key] || q.options_by.values[Object.keys(q.options_by.values)[0]];
    }
    return [];
  }

  function defaultFor(q, answers) {
    if (q.default !== undefined) return q.default;
    if (q.type === "enum") {
      const opts = optionsFor(q, answers || {});
      return opts.length ? opts[0].value : "";
    }
    return q.type === "email_list" || q.type === "user_list" ? [] : "";
  }

  function isVisible(q, answers) {
    return !q.show_if || String(answers[q.show_if.id]) === String(q.show_if.equals);
  }

  function isRequired(q, answers) {
    if (!isVisible(q, answers)) return false;
    if (q.required) return true;
    return !!q.required_if && String(answers[q.required_if.id]) === String(q.required_if.equals);
  }

  // -------------------------------------------------------------- validation

  const EMAIL_RE = /^[^\s@,;"<>()\\]+@[^\s@,;"<>()\\]+\.[^\s@,;"<>()\\]+$/;
  const DOMAIN_RE = /^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;
  const NAME_RE = /^[^\s"\\][^"\\\n]*$/u;

  function splitList(raw) {
    if (Array.isArray(raw)) return raw.map((x) => String(x).trim()).filter(Boolean);
    return String(raw === undefined || raw === null ? "" : raw)
      .split(/[\n,;]+/)
      .map((s) => s.trim())
      .filter(Boolean);
  }

  function parseUsers(raw) {
    if (Array.isArray(raw)) {
      return raw.map((u) => ({ email: u.email, given_name: u.given_name, family_name: u.family_name, ou: u.ou }));
    }
    return String(raw || "")
      .split("\n")
      .map((l) => l.trim())
      .filter(Boolean)
      .map((line) => {
        const p = line.split(",").map((s) => s.trim());
        return { email: p[0], given_name: p[1], family_name: p[2], ou: p[3], _fields: p.length };
      });
  }

  // Returns {value, error}. Value is normalized (arrays for lists).
  function checkOne(q, raw, answers) {
    const v = q.validation || {};
    switch (q.type) {
      case "boolean": {
        const b = raw === true || raw === "true";
        return { value: b };
      }
      case "integer": {
        const s = String(raw === undefined || raw === null ? "" : raw).trim();
        if (s === "") return { value: "" };
        if (!/^\d+$/.test(s)) return { value: s, error: "Enter a whole number." };
        const n = Number(s);
        if (v.min !== undefined && n < v.min) return { value: n, error: `Must be at least ${v.min}.` };
        if (v.max !== undefined && n > v.max) return { value: n, error: `Must be at most ${v.max}.` };
        return { value: n };
      }
      case "enum": {
        const s = String(raw === undefined || raw === null ? "" : raw);
        if (s === "") return { value: "" };
        if (!optionsFor(q, answers).some((o) => o.value === s)) return { value: s, error: "Choose one of the listed options." };
        return { value: s };
      }
      case "email_list": {
        const seen = [];
        for (const item of splitList(raw)) {
          if (!EMAIL_RE.test(item)) return { value: seen, error: `"${item}" is not an email address.` };
          const e = item.toLowerCase();
          if (!seen.includes(e)) seen.push(e);
        }
        return { value: seen };
      }
      case "user_list": {
        const users = [];
        for (const u of parseUsers(raw)) {
          if (u._fields !== undefined && u._fields !== 4) return { value: users, error: `"${u.email}": need four fields: email, given name, family name, ou.` };
          if (!EMAIL_RE.test(u.email || "")) return { value: users, error: `"${u.email}" is not an email address.` };
          if (!u.given_name || !NAME_RE.test(u.given_name) || !u.family_name || !NAME_RE.test(u.family_name)) {
            return { value: users, error: `${u.email}: names must be present and contain no quotes or backslashes.` };
          }
          if (u.ou !== "cui" && u.ou !== "non_cui") return { value: users, error: `${u.email}: ou must be cui or non_cui.` };
          const email = u.email.toLowerCase();
          if (users.some((x) => x.email === email)) return { value: users, error: `${email} is listed twice.` };
          users.push({ email, given_name: u.given_name, family_name: u.family_name, ou: u.ou });
        }
        return { value: users };
      }
      default: {
        // string, email, domain
        let s = String(raw === undefined || raw === null ? "" : raw).trim();
        if (s === "") return { value: "" };
        if (q.type === "email") {
          if (!EMAIL_RE.test(s)) return { value: s, error: "Enter an email address." };
          s = s.toLowerCase();
        } else if (q.type === "domain") {
          s = s.toLowerCase();
          if (!DOMAIN_RE.test(s)) return { value: s, error: "Enter a domain such as example.com (no scheme and no path)." };
        }
        if (v.max_length && s.length > v.max_length) return { value: s, error: `At most ${v.max_length} characters.` };
        if (v.pattern && !new RegExp(v.pattern, "u").test(s)) return { value: s, error: v.pattern_message || "Invalid format." };
        return { value: s };
      }
    }
  }

  // raw: {id: string|array|boolean}. Returns {answers, errors}. answers has every
  // question id; hidden questions are cleared.
  function validate(raw) {
    const answers = {};
    const errors = {};
    // Pass 1 in order: tier before home_region (options_by), mdm before mdm_product.
    for (const q of questions()) {
      const input = raw[q.id] === undefined ? defaultFor(q, answers) : raw[q.id];
      if (!isVisible(q, answers)) {
        answers[q.id] = defaultFor(Object.assign({}, q, { default: undefined }), answers);
        if (q.type === "enum") answers[q.id] = "";
        continue;
      }
      const r = checkOne(q, input, answers);
      answers[q.id] = r.value;
      if (r.error) errors[q.id] = r.error;
    }
    for (const q of questions()) {
      if (!errors[q.id] && isRequired(q, answers) && isEmpty(answers[q.id]) && q.type !== "boolean") {
        errors[q.id] = "Required.";
      }
    }
    const mails = ["account_email_log_archive", "account_email_security", "account_email_workload", "account_email_grc"];
    const seen = {};
    for (const id of mails) {
      const e = answers[id];
      if (!e) continue;
      if (seen[e]) errors[id] = errors[id] || `Same address as ${byId(seen[e]).label}; each account needs its own.`;
      else seen[e] = id;
    }
    return { answers, errors };
  }

  // ------------------------------------------------------------------ tfvars

  function effective(q, answers) {
    let v = answers[q.id];
    if (isEmpty(v) && q.fallback_to) v = answers[q.fallback_to];
    return v;
  }

  function buildTfvars(answers) {
    const out = { org: {}, baseline: {}, workspace: {} };
    for (const q of questions()) {
      for (const m of q.maps_to) {
        if (m.kind !== "tfvar") continue;
        const v = effective(q, answers);
        if (q.type !== "boolean" && isEmpty(v)) continue;
        const val = m.invert ? !v : v;
        if (m.key !== undefined) {
          if (!out[m.stack][m.name]) out[m.stack][m.name] = {};
          out[m.stack][m.name][m.key] = val;
        } else if (q.type === "user_list") {
          const map = {};
          for (const u of v) map[u.email] = { given_name: u.given_name, family_name: u.family_name, ou: u.ou };
          out[m.stack][m.name] = map;
        } else {
          out[m.stack][m.name] = val;
        }
      }
    }
    // Single-region by design (#48): keys, EBS default encryption and backups exist only in
    // the home region, so the region allowlist is the home region alone.
    out.org.allowed_regions = [answers.home_region];
    out.baseline.allowed_regions = [answers.home_region];
    if (answers.fathom_domain) out.baseline.fathom_public_url = "https://" + answers.fathom_domain; // wizard-allow-url
    return out;
  }

  // -------------------------------------------------------------------- OGRL

  async function sha256Hex(text) {
    if (!root.crypto || !root.crypto.subtle) throw new Error("WebCrypto is unavailable; open this page from a local file or localhost");
    const buf = await root.crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
  }

  function ogrlSubstitutions(answers) {
    const subs = {};
    for (const q of questions()) {
      for (const m of q.maps_to) {
        if (m.kind === "ogrl_param") subs[m.param] = String(answers[q.id]);
      }
    }
    return subs;
  }

  function resolveUri(fromDir, uri) {
    const parts = (fromDir + "/" + uri).split("/");
    const out = [];
    for (const p of parts) {
      if (p === "." || p === "") continue;
      if (p === "..") out.pop();
      else out.push(p);
    }
    return out.join("/");
  }

  // The value may be quoted or bare (both appear in the committed bundle).
  const DIGEST_RE = /(digest:[ \t]*\n[ \t]*algorithm:[ \t]*sha-256[ \t]*\n[ \t]*value:[ \t]*"?)[0-9a-f]{64}("?)/;

  // Returns {path: text} for the rendered ogrl/ tree (paths relative to ogrl/).
  async function renderOgrl(answers) {
    const d = data();
    const subs = ogrlSubstitutions(answers);
    const files = Object.assign({}, d.files);

    // 1. Enum fields: write the chosen value at each slot (line-addressed).
    for (const [param, slots] of Object.entries(d.set_value_slots)) {
      const value = subs[param];
      for (const s of slots) {
        const lines = files[s.file].split("\n");
        const re = new RegExp("^(\\s*(?:- )?" + s.key + ":\\s+)\\S+(\\s*)$");
        if (!re.test(lines[s.line])) throw new Error(`${s.file}:${s.line + 1}: expected "${s.key}:" line; rebuild bundle-data.js`);
        lines[s.line] = lines[s.line].replace(re, (_, a, b) => a + value + b);
        files[s.file] = lines.join("\n");
      }
    }

    // 2. Tier post_render (before placeholders so line numbers still hold).
    for (const r of d.post_render[answers.tier] || []) {
      const lines = files[r.file].split("\n");
      lines.splice(r.start, r.end - r.start);
      files[r.file] = lines.join("\n");
    }

    // 3. {{ name }} placeholders in org/, policy/ and procedure/.
    for (const path of Object.keys(files)) {
      if (path === "parameters.yaml") continue;
      files[path] = files[path].replace(/\{\{\s*([A-Za-z0-9_]+)\s*\}\}/g, (m, name) => {
        if (!Object.prototype.hasOwnProperty.call(subs, name)) throw new Error(`${path}: unknown placeholder ${m}`);
        return subs[name];
      });
    }

    // 4. Re-pin resource.digest on every object that points at a document.
    for (const path of Object.keys(files).sort()) {
      if (!/^org\/.+\.yaml$/.test(path)) continue;
      const m = /^[ \t]+uri:[ \t]*(\S+)[ \t]*$/m.exec(files[path]);
      if (!m || !/^resource:/m.test(files[path])) continue;
      const target = resolveUri("org", m[1]);
      if (!Object.prototype.hasOwnProperty.call(files, target)) throw new Error(`${path}: ${m[1]} not in bundle`);
      if (!DIGEST_RE.test(files[path])) throw new Error(`${path}: no sha-256 digest block to re-pin`);
      const hex = await sha256Hex(files[target]);
      files[path] = files[path].replace(DIGEST_RE, (_, a, b) => a + hex + b);
    }

    for (const [path, text] of Object.entries(files)) {
      if (text.includes("{{")) throw new Error(`${path}: leftover "{{" after rendering`);
    }
    return files;
  }

  // --------------------------------------------------------------- checklist

  const RUNBOOK = "docs/runbook/workspace.md";

  function pricePerUser(edition) {
    return edition === "acp" ? 65 : edition === "ac" ? 55 : 0;
  }

  function buildChecklist(answers) {
    const a = answers;
    const itar = a.tier === "itar";
    const L = [];
    const fathomHost = a.fathom_domain || "<your Fathom domain>";
    const editionLabel = { acp: "Enterprise Plus with Assured Controls Plus", ac: "Enterprise Plus with Assured Controls", unsupported: "an unsupported edition" }[a.workspace_edition];

    L.push(`# Enclave checklist: ${a.company_name}`, "");
    L.push(`Tier: ${itar ? "ITAR (AWS GovCloud)" : "standard (commercial AWS)"}. Workspace domain: ${a.domain}. Users: ${a.user_count}. Edition: ${editionLabel}.`, "");
    L.push("Generated by the cmmc-enclave wizard. Contains no secrets; keys, passwords and the OAuth client secret are manual steps below.", "");

    // Purchases
    L.push("## Purchases", "", "Not on the one-hour clock. Prices are reseller list estimates, not quotes (SCOPE section 13).", "");
    const per = pricePerUser(a.workspace_edition);
    if (a.workspace_edition === "acp") {
      L.push(`- [ ] Google Workspace Enterprise Plus plus the Assured Controls Plus add-on, ${a.user_count} users (about $${per * a.user_count} a month at $${per} per user).`);
    } else if (a.workspace_edition === "ac") {
      L.push(`- [ ] Google Workspace Enterprise Plus plus the Assured Controls add-on (fallback), ${a.user_count} users (about $${per * a.user_count} a month at $${per} per user). Assured Controls Plus is the default; record the difference in the SSP.`);
    } else {
      L.push(`- [ ] Confirm your Workspace edition and add-ons by hand. The baseline does not support this edition (SCOPE decision D1); see POA&M items below.`);
    }
    if (a.workspace_tenant === "new") L.push(`- [ ] A new Workspace tenant for ${a.domain} (included with the licenses above).`);
    if (itar) {
      L.push("- [ ] AWS GovCloud (US) account signup, tied to your commercial AWS account (SCOPE section 4). Needs its own signup and verification.");
      L.push("- [ ] A client-side encryption key service for Workspace (ITAR needs customer-held keys): Flowcrypt, Thales, Virtru, Fortanix or others, or build one. Flowcrypt list price is about EUR 67, 117 and 217 a month at 10, 25 and 100 users; others are quote based.");
      L.push("- [ ] AWS (commercial remnant plus GovCloud): roughly $370 to $660 a month for 10 to 100 users (SCOPE section 13).");
    } else {
      L.push("- [ ] AWS: roughly $300 to $480 a month for 10 to 100 users (SCOPE section 13).");
    }
    if (a.mdm === "none") L.push("- [ ] An MDM product for enclave endpoints (none today). Not costed in SCOPE section 13.");
    if (a.edr === "none") L.push("- [ ] An EDR product for enclave endpoints (none today). Not costed in SCOPE section 13.");
    L.push("");

    // Steps
    L.push("## Manual steps, in order", "", `Workspace details: ${RUNBOOK} in the cmmc-enclave repo.`, "");
    const steps = [];
    if (a.workspace_tenant === "new") {
      steps.push(`Create the Google Workspace tenant for ${a.domain}, verify the domain in DNS, and create the super admin ${a.workspace_admin_email}. Then set \`customer_id\` (Admin console, Account settings) in terraform/workspace.auto.tfvars.json. See ${RUNBOOK}.`);
    }
    steps.push(a.workspace_edition === "unsupported"
      ? "Confirm your Workspace edition. Without Assured Controls the baseline's Workspace settings cannot all be applied; the POA&M items below record that."
      : `Buy or confirm ${editionLabel} and ask Google to enable Assured Controls for the tenant. Wait for confirmation before the workspace stage.`);
    if (!a.existing_organization) {
      steps.push(`Create the AWS management account${itar ? " in commercial AWS, then the linked GovCloud (US) account" : ""}. Terraform creates the organization and four member accounts from the emails you gave: ${[a.account_email_log_archive, a.account_email_security, a.account_email_workload, a.account_email_grc].join(", ")}. Make sure each mailbox receives mail.`);
    } else {
      steps.push("Make sure the existing AWS organization's management credentials are available to Terraform, and that the four member account emails are unused.");
    }
    steps.push(`Create the Terraform service account in Google Cloud, grant it domain-wide delegation for the scopes in ${RUNBOOK}, and export GOOGLEWORKSPACE_CREDENTIALS as the path to its key file. Do the same for the audit collector (impersonating ${a.workspace_audit_admin_email || a.workspace_admin_email}). Keep keys out of this config.`);
    steps.push("Run `scripts/bootstrap --config enclave-config-v1.zip`. Stages: preflight, org, baseline-1, manual-workspace (it pauses for the step above), workspace, seed-package, baseline-2, verify.");
    steps.push(`Fathom sign-in: in Google Cloud create an OAuth web client whose redirect path is /v1/auth/oidc/google/callback on ${fathomHost} (scheme https). Put the client ID in terraform/baseline.auto.tfvars.json as fathom_oidc_client_id${a.fathom_oidc_client_id ? " (already set)" : " (not set yet)"}.`);
    steps.push("Store the OAuth client secret by hand as an SSM SecureString in the grc account at /fathom/oidc/client-secret. Never write it into this config.");
    if (!a.fathom_certificate_arn || !a.fathom_domain) {
      steps.push(`Request an ACM certificate for ${fathomHost} in the grc account and home region, point DNS at the load balancer, and set fathom_domain_name and fathom_certificate_arn in terraform/baseline.auto.tfvars.json.`);
    }
    steps.push("After Fathom is up, create each aws_role connection in Fathom, copy its ExternalId into fathom_read_external_ids, and apply baseline again.");
    steps.push(`Enroll enclave endpoints${a.mdm === "existing" ? ` in ${a.mdm_product || "your MDM"}` : ""}${a.edr === "existing" ? ` and ${a.edr_product || "your EDR"}` : ""}. Endpoints, sites (${a.sites}) and policies stay your responsibility.`);
    steps.push(`Review the gaps in Fathom, adopt the policies in ogrl/policy, and have ${a.ssp_signer_name} (${a.ssp_signer_title}) sign the SSP.`);
    steps.forEach((s, i) => L.push(`${i + 1}. [ ] ${s}`));
    L.push("");

    // POA&M
    const poam = [];
    if (a.mdm === "none") {
      poam.push(["No MDM: connection of mobile devices (3.1.18)", "Mobile and managed-device connections to the enclave are not controlled by a management system."]);
      poam.push(["No MDM: encryption of CUI on mobile devices (3.1.19)", "Device encryption cannot be enforced or evidenced."]);
      poam.push(["No MDM: endpoint baseline configuration and settings (3.4.1, 3.4.2)", "Endpoint configuration is not managed or enforced."]);
      poam.push(["No MDM: portable storage and removable media (3.1.21, 3.8.7)", "Removable media use is not controlled by policy enforcement on devices."]);
    }
    if (a.edr === "none") {
      poam.push(["No EDR: malicious code protection (3.14.2)", "No endpoint malicious code protection is deployed."]);
      poam.push(["No EDR: scans and real-time protection (3.14.5)", "Periodic and real-time scanning is not evidenced."]);
    }
    if (a.workspace_edition === "unsupported") {
      poam.push(["Unsupported Workspace edition: Assured Controls (3.6.2, DFARS 252.204-7012(c))", "Google's 72 hour incident notice applies only to customers with Assured Controls (SCOPE section 4)."]);
      poam.push(["Unsupported Workspace edition: hardening settings (3.1.x, 3.3.x, 3.5.x, 3.13.11)", "The vendor guide's configuration steps rely on Enterprise Plus features; the baseline Policy API checks cannot all pass."]);
    }
    L.push("## POA&M items", "");
    if (poam.length === 0) {
      L.push("None generated from your answers.", "");
    } else {
      L.push("Enter these in Fathom as POA&M items. A POA&M is allowed only for requirements 32 CFR 170.21(a)(2) permits, and must close within 180 days; check each before relying on it.", "");
      for (const [title, why] of poam) L.push(`- [ ] ${title}. ${why}`);
      L.push("");
    }
    if (a.workspace_edition === "ac") {
      L.push("## Notes", "", "- Assured Controls without Plus: US-person support access is not covered. Document that in the SSP.", "");
    }
    return L.join("\n");
  }

  // --------------------------------------------------------------------- zip

  const CRC_TABLE = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();

  function crc32(bytes) {
    let c = 0xffffffff;
    for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  }

  // entries: [{name, data: Uint8Array}]. STORE method, fixed 1980-01-01 timestamp,
  // sorted by name, so the same entries always give the same bytes.
  function makeZip(entries) {
    const enc = new TextEncoder();
    const sorted = entries.slice().sort((x, y) => (x.name < y.name ? -1 : x.name > y.name ? 1 : 0));
    const chunks = [];
    const central = [];
    let offset = 0;
    const DOS_DATE = 0x0021; // 1980-01-01
    for (const e of sorted) {
      const name = enc.encode(e.name);
      const crc = crc32(e.data);
      const lh = new DataView(new ArrayBuffer(30));
      lh.setUint32(0, 0x04034b50, true);
      lh.setUint16(4, 20, true);
      lh.setUint16(6, 0x0800, true); // UTF-8 names
      lh.setUint16(8, 0, true); // STORE
      lh.setUint16(10, 0, true);
      lh.setUint16(12, DOS_DATE, true);
      lh.setUint32(14, crc, true);
      lh.setUint32(18, e.data.length, true);
      lh.setUint32(22, e.data.length, true);
      lh.setUint16(26, name.length, true);
      lh.setUint16(28, 0, true);
      chunks.push(new Uint8Array(lh.buffer), name, e.data);

      const ch = new DataView(new ArrayBuffer(46));
      ch.setUint32(0, 0x02014b50, true);
      ch.setUint16(4, (3 << 8) | 20, true); // made by: Unix
      ch.setUint16(6, 20, true);
      ch.setUint16(8, 0x0800, true);
      ch.setUint16(10, 0, true);
      ch.setUint16(12, 0, true);
      ch.setUint16(14, DOS_DATE, true);
      ch.setUint32(16, crc, true);
      ch.setUint32(20, e.data.length, true);
      ch.setUint32(24, e.data.length, true);
      ch.setUint16(28, name.length, true);
      ch.setUint32(38, (0o100644 << 16) >>> 0, true);
      ch.setUint32(42, offset, true);
      central.push(new Uint8Array(ch.buffer), name);
      offset += 30 + name.length + e.data.length;
    }
    let centralSize = 0;
    for (const c of central) centralSize += c.length;
    const end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true);
    end.setUint16(8, sorted.length, true);
    end.setUint16(10, sorted.length, true);
    end.setUint32(12, centralSize, true);
    end.setUint32(16, offset, true);
    const all = chunks.concat(central, [new Uint8Array(end.buffer)]);
    let total = 0;
    for (const c of all) total += c.length;
    const out = new Uint8Array(total);
    let p = 0;
    for (const c of all) {
      out.set(c, p);
      p += c.length;
    }
    return out;
  }

  // ----------------------------------------------------------------- driver

  // Returns {files: {name: string}} (names relative to enclave-config/) or
  // throws. `answers` must already be validated.
  async function buildFiles(answers) {
    const tf = buildTfvars(answers);
    const files = {};
    files["answers.json"] = stableJson({ schema_version: data().schema_version, generated_by: data().generated_by, answers });
    files["terraform/org.auto.tfvars.json"] = stableJson(tf.org);
    files["terraform/baseline.auto.tfvars.json"] = stableJson(tf.baseline);
    files["terraform/workspace.auto.tfvars.json"] = stableJson(tf.workspace);
    const ogrl = await renderOgrl(answers);
    for (const [p, t] of Object.entries(ogrl)) files["ogrl/" + p] = t;
    files["checklist.md"] = buildChecklist(answers) + "\n";
    return files;
  }

  async function buildZip(answers) {
    const files = await buildFiles(answers);
    const enc = new TextEncoder();
    const entries = Object.keys(files).map((n) => ({ name: CONFIG_DIR + "/" + n, data: enc.encode(files[n]) }));
    return makeZip(entries);
  }

  root.WizardCore = {
    ZIP_NAME, CONFIG_DIR, validate, buildTfvars, renderOgrl, buildChecklist, buildFiles, buildZip,
    makeZip, crc32, sha256Hex, stableJson, optionsFor, defaultFor, isVisible, isRequired, splitList,
  };

  // ---------------------------------------------------------------------- UI

  if (typeof document === "undefined") return;

  const core = root.WizardCore;
  const el = (tag, attrs, ...kids) => {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v === false || v === undefined || v === null) continue;
      if (k === "text") n.textContent = v;
      else n.setAttribute(k, v === true ? "" : v);
    }
    for (const k of kids) n.append(k);
    return n;
  };

  const state = { raw: {}, view: "form" };
  const fields = {}; // id -> {wrap, input, error, req}

  function displayValue(q, v) {
    if (q.type === "email_list") return (v || []).join("\n");
    if (q.type === "user_list") return (v || []).map((u) => [u.email, u.given_name, u.family_name, u.ou].join(", ")).join("\n");
    if (q.type === "boolean") return v ? "true" : "false";
    return v === undefined || v === null ? "" : String(v);
  }

  function readRaw() {
    for (const q of questions()) {
      const f = fields[q.id];
      state.raw[q.id] = f.input.value;
    }
  }

  function buildInput(q) {
    const id = "q-" + q.id;
    const describedBy = [q.help ? id + "-help" : "", id + "-error"].filter(Boolean).join(" ");
    const common = { id, name: q.id, "aria-describedby": describedBy };
    if (q.type === "enum" || q.type === "boolean") {
      return el("select", common);
    }
    if (q.type === "email_list" || q.type === "user_list") {
      return el("textarea", Object.assign({ rows: "4", spellcheck: "false", placeholder: q.example || false }, common));
    }
    return el("input", Object.assign({
      type: "text", autocomplete: "off", spellcheck: "false",
      inputmode: q.type === "integer" ? "numeric" : false, placeholder: q.example || false,
    }, common));
  }

  function fillOptions(q, answers) {
    const sel = fields[q.id].input;
    const current = sel.value;
    let opts;
    if (q.type === "boolean") opts = [{ value: "true", label: "Yes" }, { value: "false", label: "No" }];
    else opts = core.optionsFor(q, answers);
    const same = Array.from(sel.options).map((o) => o.value).join("|") === opts.map((o) => o.value).join("|");
    if (!same) {
      sel.textContent = "";
      for (const o of opts) sel.append(el("option", { value: o.value, text: o.label }));
      const keep = opts.some((o) => o.value === current);
      sel.value = keep ? current : opts.length ? opts[0].value : "";
    }
  }

  function currentAnswersLoose() {
    // Raw-ish answers for visibility and option decisions while editing.
    const a = {};
    for (const q of questions()) {
      const f = fields[q.id];
      a[q.id] = f ? f.input.value : "";
    }
    return a;
  }

  function refreshForm() {
    const a = currentAnswersLoose();
    for (const q of questions()) {
      if (q.type === "enum" || q.type === "boolean") fillOptions(q, a);
    }
    const a2 = currentAnswersLoose();
    for (const q of questions()) {
      const f = fields[q.id];
      f.wrap.hidden = !core.isVisible(q, a2);
      f.req.textContent = core.isRequired(q, a2) ? " (required)" : " (optional)";
    }
  }

  function showErrors(errors) {
    let first = null;
    for (const q of questions()) {
      const f = fields[q.id];
      const msg = errors[q.id];
      f.error.textContent = msg || "";
      if (msg) {
        f.input.setAttribute("aria-invalid", "true");
        if (!first) first = f.input;
      } else {
        f.input.removeAttribute("aria-invalid");
      }
    }
    return first;
  }

  function buildForm(form) {
    const d = data().questions;
    for (const s of d.sections) {
      const fs = el("fieldset", {}, el("legend", { text: s.title }), el("p", { class: "intro", text: s.intro }));
      for (const q of questions().filter((x) => x.section === s.id)) {
        const input = buildInput(q);
        const req = el("span", { class: "req" });
        const label = el("label", { for: "q-" + q.id }, q.label, req);
        const help = q.help ? el("p", { id: "q-" + q.id + "-help", class: "help", text: q.help }) : null;
        const error = el("p", { id: "q-" + q.id + "-error", class: "error", role: "alert" });
        const wrap = el("div", { class: "field" }, label, help || "", input, error);
        fields[q.id] = { wrap, input, error, req };
        input.addEventListener("input", refreshForm);
        input.addEventListener("change", refreshForm);
        fs.append(wrap);
      }
      form.append(fs);
    }
    for (const q of questions()) {
      const f = fields[q.id];
      if (q.type === "enum" || q.type === "boolean") fillOptions(q, { tier: "standard" });
      f.input.value = displayValue(q, core.defaultFor(q, { tier: "standard" }));
    }
    refreshForm();
  }

  function applyRaw(raw) {
    // Two passes so that tier (options) is set before home_region.
    for (const pass of [0, 1]) {
      for (const q of questions()) {
        if (raw[q.id] === undefined) continue;
        if ((q.id === "tier") !== (pass === 0)) continue;
        fields[q.id].input.value = displayValue(q, raw[q.id]);
        if (q.id === "tier") refreshForm();
      }
    }
    refreshForm();
  }

  function setView(view) {
    state.view = view;
    document.getElementById("form-view").hidden = view !== "form";
    document.getElementById("review-view").hidden = view !== "review";
    document.getElementById("step").textContent = view === "form" ? "Step 1 of 2: answer the questions" : "Step 2 of 2: review and download";
    const h = document.getElementById(view === "form" ? "form-title" : "review-title");
    h.focus();
  }

  function showReview(answers) {
    const box = document.getElementById("review-body");
    box.textContent = "";
    for (const s of data().questions.sections) {
      const dl = el("dl");
      for (const q of questions().filter((x) => x.section === s.id)) {
        const v = answers[q.id];
        if (!core.isVisible(q, answers)) continue;
        let text = displayValue(q, v);
        if (q.type === "enum") {
          const o = core.optionsFor(q, answers).find((x) => x.value === v);
          text = o ? o.label : text;
        } else if (q.type === "boolean") text = v ? "Yes" : "No";
        dl.append(el("dt", { text: q.label }), el("dd", { text: text === "" ? "(blank)" : text }));
      }
      box.append(el("h3", { text: s.title }), dl);
    }
    const warn = document.getElementById("review-warnings");
    warn.textContent = "";
    if (answers.mdm === "none") warn.append(el("li", { text: "No MDM: the checklist lists POA&M items and a purchase." }));
    if (answers.edr === "none") warn.append(el("li", { text: "No EDR: the checklist lists POA&M items and a purchase." }));
    if (answers.workspace_edition === "unsupported") warn.append(el("li", { text: "Unsupported Workspace edition: the checklist lists POA&M items." }));
    if (!answers.fathom_oidc_client_id) warn.append(el("li", { text: "No Fathom OAuth client ID yet: set fathom_oidc_client_id later." }));
    document.getElementById("review-warnings-wrap").hidden = warn.children.length === 0;
  }

  function download(bytes, name) {
    const blob = new Blob([bytes], { type: "application/zip" });
    const url = URL.createObjectURL(blob);
    const a = el("a", { href: url, download: name });
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  }

  function init() {
    const form = document.getElementById("wizard-form");
    buildForm(form);
    form.addEventListener("submit", (ev) => ev.preventDefault());
    const status = document.getElementById("status");

    document.getElementById("to-review").addEventListener("click", () => {
      readRaw();
      const { answers, errors } = core.validate(state.raw);
      const first = showErrors(errors);
      if (first) {
        status.textContent = `${Object.keys(errors).length} question(s) need attention.`;
        first.focus();
        return;
      }
      status.textContent = "";
      state.answers = answers;
      showReview(answers);
      setView("review");
    });
    document.getElementById("back").addEventListener("click", () => setView("form"));
    document.getElementById("download").addEventListener("click", async () => {
      status.textContent = "Building...";
      try {
        const bytes = await core.buildZip(state.answers);
        download(bytes, core.ZIP_NAME);
        status.textContent = `Downloaded ${core.ZIP_NAME} (${bytes.length} bytes). Nothing was sent anywhere.`;
      } catch (err) {
        status.textContent = "Error: " + err.message;
      }
    });
    document.getElementById("load-answers").addEventListener("change", (ev) => {
      const file = ev.target.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => {
        try {
          const doc = JSON.parse(String(reader.result));
          if (!doc || doc.schema_version !== data().schema_version || typeof doc.answers !== "object") throw new Error("not an answers.json from this wizard version");
          applyRaw(doc.answers);
          status.textContent = "Loaded answers from " + file.name + ".";
        } catch (err) {
          status.textContent = "Could not load: " + err.message;
        }
      };
      reader.readAsText(file);
    });
    setView("form");
  }

  init();
})(globalThis);
