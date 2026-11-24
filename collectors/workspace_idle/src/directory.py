"""Admin SDK Directory API client: plain HTTPS over a google-auth AuthorizedSession."""
import time

SCOPES = {
    "report": "https://www.googleapis.com/auth/admin.directory.user.readonly",
    "suspend": "https://www.googleapis.com/auth/admin.directory.user",
}
BASE = "https://admin.googleapis.com/admin/directory/v1/users"
RETRY_STATUS = {429, 500, 502, 503, 504}
MAX_TRIES = 5


class DirectoryError(Exception):
    pass


def scope_for(mode):
    """The one scope the active mode needs; the write scope is never requested in report mode."""
    try:
        return SCOPES[mode]
    except KeyError:
        raise ValueError(f"MODE must be report or suspend, got {mode!r}") from None


def build_session(key_info, subject, mode):
    """Domain-wide delegation: the service account impersonates an admin user."""
    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account

    creds = service_account.Credentials.from_service_account_info(
        key_info, scopes=[scope_for(mode)], subject=subject
    )
    return AuthorizedSession(creds)


def _error_reason(resp):
    try:
        err = resp.json()["error"]
        errors = err.get("errors") or [{}]
        return errors[0].get("reason") or err.get("status") or "unknown"
    except Exception:  # non-JSON body
        return "unknown"


def _request(session, method, url, sleep, **kw):
    """Return the 200 response, retrying transient statuses; raise DirectoryError otherwise."""
    for attempt in range(MAX_TRIES):
        resp = getattr(session, method)(url, timeout=60, **kw)
        if resp.status_code == 200:
            return resp
        if resp.status_code in RETRY_STATUS and attempt < MAX_TRIES - 1:
            sleep(2**attempt)
            continue
        raise DirectoryError(f"HTTP {resp.status_code} {_error_reason(resp)}")


def list_users(session, page_size=500, sleep=time.sleep):
    """Yield every user (basic projection) in the customer, following pagination."""
    params = {"customer": "my_customer", "projection": "basic", "maxResults": page_size}
    while True:
        body = _request(session, "get", BASE, sleep, params=params).json()
        yield from body.get("users", [])
        token = body.get("nextPageToken")
        if not token:
            return
        params["pageToken"] = token


def suspend_user(session, user_id, sleep=time.sleep):
    """Set suspended=true. PATCH, so no other field of the user is touched."""
    _request(session, "patch", f"{BASE}/{user_id}", sleep, json={"suspended": True})
