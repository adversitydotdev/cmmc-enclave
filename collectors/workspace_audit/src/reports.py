"""Admin SDK Reports API client: plain HTTPS over a google-auth AuthorizedSession."""
import time
from datetime import datetime, timezone

SCOPE = "https://www.googleapis.com/auth/admin.reports.audit.readonly"
URL = "https://admin.googleapis.com/admin/reports/v1/activity/users/all/applications/{app}"
RETRY_STATUS = {429, 500, 502, 503, 504}
UNAVAILABLE_STATUS = {400, 403, 404}  # unknown application, or not enabled for this edition
MAX_TRIES = 5


class AppUnavailable(Exception):
    """The application cannot be read in this tenant; the caller skips it."""

    def __init__(self, app, status, reason):
        super().__init__(f"{app}: HTTP {status} {reason}")
        self.app = app
        self.status = status
        self.reason = reason


class ReportsError(Exception):
    pass


def parse_time(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def format_time(dt):
    dt = dt.astimezone(timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"


def build_session(key_info, subject):
    """Domain-wide delegation: the service account impersonates an admin user."""
    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account

    creds = service_account.Credentials.from_service_account_info(
        key_info, scopes=[SCOPE], subject=subject
    )
    return AuthorizedSession(creds)


def _error_reason(resp):
    try:
        err = resp.json()["error"]
        errors = err.get("errors") or [{}]
        return errors[0].get("reason") or err.get("status") or "unknown"
    except Exception:  # non-JSON body
        return "unknown"


def _get(session, url, params, sleep):
    """Return parsed JSON on 200, else the failed response (after retrying transient statuses)."""
    for attempt in range(MAX_TRIES):
        resp = session.get(url, params=params, timeout=60)
        if resp.status_code == 200:
            return resp.json()
        if resp.status_code in RETRY_STATUS and attempt < MAX_TRIES - 1:
            sleep(2**attempt)
            continue
        return resp


def fetch_activities(session, app, start, end=None, page_size=1000, sleep=time.sleep):
    """Yield every activity for app with time >= start (datetime), following pagination."""
    url = URL.format(app=app)
    params = {"startTime": format_time(start), "maxResults": page_size}
    if end is not None:
        params["endTime"] = format_time(end)
    while True:
        result = _get(session, url, params, sleep)
        if not isinstance(result, dict):  # failed response
            if result.status_code in UNAVAILABLE_STATUS:
                raise AppUnavailable(app, result.status_code, _error_reason(result))
            raise ReportsError(f"{app}: HTTP {result.status_code} {_error_reason(result)}")
        yield from result.get("items", [])
        token = result.get("nextPageToken")
        if not token:
            return
        params["pageToken"] = token
