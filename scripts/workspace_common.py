"""Shared helpers for scripts/workspace-dlp and scripts/workspace-policy (Cloud Identity Policy API).

Auth, HTTP, policy-resource shapes, operation polling and org-unit resolution live here so the
two scripts stay thin. Tests substitute a fake with the same
request(method, url, params=None, body=None) -> dict signature for Http.

References (retrieved 2026-11-23/24):
  [R2] Policy resource (customer, policyQuery.orgUnit, setting.type/value):
       https://docs.cloud.google.com/identity/docs/reference/rest/v1beta1/policies
  [R3] policies.list (filter is a CEL expression, pageSize max 100):
       https://docs.cloud.google.com/identity/docs/reference/rest/v1beta1/policies/list
  [R4] policies.create (POST /v1beta1/policies, returns an Operation; scope cloud-identity.policies):
       https://docs.cloud.google.com/identity/docs/reference/rest/v1beta1/policies/create
  [R5] Directory API orgunits.get (GET .../customer/{customerId}/orgunits/{orgUnitPath=**};
       scope admin.directory.orgunit, already on the Terraform service account's delegation):
       https://developers.google.com/workspace/admin/directory/reference/rest/v1/orgunits/get
"""
import json
import time
import urllib.parse

BASE = "https://cloudidentity.googleapis.com/v1beta1"
DIRECTORY = "https://admin.googleapis.com/admin/directory/v1"
SCOPE = "https://www.googleapis.com/auth/cloud-identity.policies"  # [R4]
SCOPE_ORGUNIT = "https://www.googleapis.com/auth/admin.directory.orgunit"  # [R5]


class Http:
    """Thin authorized HTTP layer (google-auth + requests)."""

    def __init__(self, credentials=None, subject=None, scopes=(SCOPE,)):
        """credentials: path to a service account key, or the key JSON itself; None uses ADC."""
        import google.auth
        from google.auth.transport.requests import AuthorizedSession
        from google.oauth2 import service_account
        scopes = list(scopes)
        if credentials:
            if credentials.lstrip().startswith("{"):
                creds = service_account.Credentials.from_service_account_info(
                    json.loads(credentials), scopes=scopes)
            else:
                creds = service_account.Credentials.from_service_account_file(credentials, scopes=scopes)
            if subject:
                creds = creds.with_subject(subject)  # UNVERIFIED: DWD impersonation accepted by Policy API
        else:
            creds, _ = google.auth.default(scopes=scopes)
        self.session = AuthorizedSession(creds)

    def request(self, method, url, params=None, body=None):
        r = self.session.request(method, url, params=params, json=body, timeout=60)
        if r.status_code >= 300:
            raise RuntimeError(f"{method} {url} -> {r.status_code}: {r.text[:500]}")
        return r.json() if r.text else {}


def customer_name(customer_id):
    return customer_id if customer_id.startswith("customers/") else f"customers/{customer_id}"


def org_unit_name(org_unit):
    """'id:03ph...' or bare id or 'orgUnits/...' -> 'orgUnits/<id>'."""
    if org_unit.startswith("id:"):
        return "orgUnits/" + org_unit[3:]
    return org_unit if org_unit.startswith("orgUnits/") else "orgUnits/" + org_unit


def resolve_org_unit(http, path):
    """[R5] Directory API orgunits.get by path ('/CUI'); returns the OrgUnit dict (orgUnitId 'id:...',
    parentOrgUnitId)."""
    url = f"{DIRECTORY}/customer/my_customer/orgunits/{urllib.parse.quote(path.lstrip('/'), safe='/')}"
    return http.request("GET", url)


def policy_body(customer, org_unit, stype, value):
    """[R2] Policy: customer, policyQuery.orgUnit (orgUnits/{id}, UNVERIFIED format), setting{type,value}."""
    return {
        "customer": customer,
        "policyQuery": {"orgUnit": org_unit, "group": ""},
        "setting": {"type": stype, "value": value},
    }


def list_policies(http, customer, type_regex):
    """[R3] filter is a CEL expression. type_regex is an RE2 body matched against setting.type,
    e.g. r'settings/(rule\\.dlp|detector\\..*)'; anchors are added here."""
    flt = (f'customer == "{customer}" && '
           "setting.type.matches('^" + type_regex.replace("\\", "\\\\") + "$')")
    out, token = [], None
    while True:
        params = {"filter": flt, "pageSize": 100}
        if token:
            params["pageToken"] = token
        page = http.request("GET", f"{BASE}/policies", params=params)
        out += page.get("policies", [])
        token = page.get("nextPageToken")
        if not token:
            return out


def subset(want, have):
    """True when every field we set already has that value (server adds timestamps etc.)."""
    if isinstance(want, dict):
        return isinstance(have, dict) and all(k in have and subset(v, have[k]) for k, v in want.items())
    return want == have


def wait_operation(http, op, tries=10):
    """[R4] create returns an Operation; poll GET /v1beta1/{operation.name} until done."""
    for _ in range(tries):
        if not op or op.get("done", True) or "name" not in op:
            break
        time.sleep(1)
        op = http.request("GET", f"{BASE}/{op['name']}")
    if op and op.get("error"):
        raise RuntimeError(f"operation failed: {op['error']}")
