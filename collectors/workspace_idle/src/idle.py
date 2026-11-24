"""Idle-user selection and report layout. No AWS or Google imports here."""
import json
import uuid
from datetime import datetime, timedelta, timezone

PREFIX = "workspace-idle"
NEVER = "1970-01-01T00:00:00.000Z"  # Directory API value for "never logged in"


def parse_time(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def parse_list(value):
    return [v.strip() for v in (value or "").split(",") if v.strip()]


def ou_excluded(path, ous):
    """True when path is one of the excluded OUs or below one."""
    path = (path or "/").rstrip("/") or "/"
    for ou in ous:
        ou = ou.rstrip("/") or "/"
        if ou == "/" or path == ou or path.startswith(ou + "/"):
            return True
    return False


def last_activity(user):
    """(timestamp, basis): last login, else creation time for users who never logged in."""
    login = user.get("lastLoginTime")
    if login and login != NEVER:
        return parse_time(login), "lastLoginTime"
    return parse_time(user["creationTime"]), "creationTime"


def exclusion_reason(user, emails, ous):
    if user.get("isAdmin"):
        return "super_admin"
    if user.get("primaryEmail", "").lower() in emails:
        return "email"
    if ou_excluded(user.get("orgUnitPath"), ous):
        return "ou"
    return None


def find_idle(users, now, days, emails, ous):
    """Return (idle, excluded_counts, scanned). Already suspended users are not candidates."""
    cutoff = now - timedelta(days=days)
    emails = {e.lower() for e in emails}
    idle, excluded, scanned = [], {}, 0
    for user in users:
        scanned += 1
        if user.get("suspended"):
            continue
        when, basis = last_activity(user)
        if when >= cutoff:
            continue
        reason = exclusion_reason(user, emails, ous)
        if reason:
            excluded[reason] = excluded.get(reason, 0) + 1
            continue
        idle.append(
            {
                "id": user["id"],
                "email": user["primaryEmail"],
                "orgUnitPath": user.get("orgUnitPath", "/"),
                "lastActivity": when.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "basis": basis,
                "daysIdle": (now - when).days,
            }
        )
    return idle, excluded, scanned


def s3_key(now, run_id):
    return f"{PREFIX}/dt={now.strftime('%Y-%m-%d')}/{run_id}.json"


def write_report(s3, bucket, kms_key_arn, now, run_id, report):
    """One new object per run. Object Lock forbids overwrite, so the key carries run_id."""
    key = s3_key(now, run_id)
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(report, indent=2, sort_keys=True).encode(),
        ContentType="application/json",
        ServerSideEncryption="aws:kms",
        SSEKMSKeyId=kms_key_arn,
    )
    return key


def new_run_id():
    return uuid.uuid4().hex
