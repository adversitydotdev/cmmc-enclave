#!/usr/bin/env python3
"""Open the wizard's zip with Python's zipfile and verify it against the contract.

Usage: python3 -P check_zip.py <zip> <tier: standard|itar>
Exit 0 and print OK, or exit 1 with the failures.
"""
import hashlib
import json
import re
import sys
import zipfile

import yaml

path, tier = sys.argv[1], sys.argv[2]
fail = []


def check(cond, msg):
    if not cond:
        fail.append(msg)


with zipfile.ZipFile(path) as z:
    check(z.testzip() is None, "testzip found a bad CRC")
    infos = z.infolist()
    names = [i.filename for i in infos]
    check(names == sorted(names), "entries not sorted")
    check(all(i.compress_type == zipfile.ZIP_STORED for i in infos), "not all STORE")
    check(all(n.startswith("enclave-config/") for n in names), "entry outside enclave-config/")
    files = {n[len("enclave-config/"):]: z.read(n) for n in names}

for need in ["answers.json", "checklist.md", "ogrl/parameters.yaml", "ogrl/org/bundle.yaml",
             "terraform/org.auto.tfvars.json", "terraform/baseline.auto.tfvars.json",
             "terraform/workspace.auto.tfvars.json"]:
    check(need in files, f"missing {need}")

ans = json.loads(files["answers.json"])
check(ans["schema_version"] == "1", "schema_version")
check(ans["answers"]["tier"] == tier, "tier in answers.json")
for n in ["org", "baseline", "workspace"]:
    json.loads(files[f"terraform/{n}.auto.tfvars.json"])

for n, b in files.items():
    check(b"{{" not in b, f"{n}: leftover double brace")
    if n.endswith(".yaml"):
        try:
            yaml.safe_load(b)
        except yaml.YAMLError as e:
            fail.append(f"{n}: YAML error {e}")

pins = 0
for n, b in files.items():
    if not re.fullmatch(r"ogrl/org/[^/]+/[^/]+\.yaml", n):
        continue
    obj = yaml.safe_load(b)
    res = obj.get("resource") or {}
    if not res.get("uri"):
        continue
    parts = []
    for p in ("ogrl/org/" + res["uri"]).split("/"):
        if p == "..":
            parts.pop()
        elif p:
            parts.append(p)
    target = "/".join(parts)
    check(target in files, f"{n}: {target} not in zip")
    if target in files:
        pins += 1
        check(res["digest"]["value"] == hashlib.sha256(files[target]).hexdigest(), f"{n}: digest does not match {target}")
check(pins >= 10, f"only {pins} pinned documents")

sysobj = yaml.safe_load(files["ogrl/org/system/enclave.yaml"])
ids = [p.get("authorization", {}).get("identifier") for p in sysobj["parties"]]
check(("F1603047866" in ids) == (tier == "itar"), f"GovCloud party presence wrong for {tier}: {ids}")

if fail:
    print("FAIL:\n  " + "\n  ".join(fail))
    sys.exit(1)
print(f"OK {len(files)} files, {pins} digests")
