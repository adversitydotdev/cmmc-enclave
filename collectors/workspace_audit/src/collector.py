"""Cursor, overlap and dedupe logic, S3 layout. No AWS or Google imports here."""
import gzip
import json
import uuid
from datetime import timedelta

from reports import fetch_activities, format_time, parse_time

PREFIX = "workspace-audit"


def event_key(event):
    """Dedupe key: event time plus uniqueQualifier (app and customer are implied by the state item)."""
    eid = event["id"]
    return f"{eid['time']}|{eid.get('uniqueQualifier', '')}"


def _key_time(key):
    return parse_time(key.split("|", 1)[0])


def collect_app(session, state, app, now, overlap, lookback, sleep=None):
    """Return (new_events, new_cursor_str, new_seen_list) for one application. Does not write.

    Every run re-reads [cursor - overlap, now]. Google's reporting delay means events can
    appear with a time before the newest one already seen; the overlap catches them and
    `seen` (keys of events already archived inside the overlap window) drops repeats.
    """
    st = state.get(app)
    if st is None:
        cursor = now - lookback
        start = cursor
        seen = set()
    else:
        cursor = parse_time(st["cursor"])
        start = cursor - overlap
        seen = set(st["seen"])

    kwargs = {} if sleep is None else {"sleep": sleep}
    new, new_keys, high = [], set(), cursor
    for ev in fetch_activities(session, app, start, **kwargs):
        key = event_key(ev)
        if key in seen or key in new_keys:
            continue
        new_keys.add(key)
        new.append(ev)
        high = max(high, parse_time(ev["id"]["time"]))

    floor = high - overlap  # next run starts here; older keys can never be returned again
    kept = [k for k in seen | new_keys if _key_time(k) >= floor]
    new.sort(key=lambda e: parse_time(e["id"]["time"]))
    return new, format_time(high), kept


def partition_events(events):
    """Group events by (dt, hour) of event time, UTC."""
    groups = {}
    for ev in events:
        t = parse_time(ev["id"]["time"])
        groups.setdefault((t.strftime("%Y-%m-%d"), t.strftime("%H")), []).append(ev)
    return groups


def s3_key(app, dt, hour, run_id):
    return f"{PREFIX}/application={app}/dt={dt}/{hour}-{run_id}.jsonl.gz"


def write_events(s3, bucket, kms_key_arn, app, events, run_id):
    """One new object per (dt, hour) per run. Object Lock forbids overwrite, so keys carry run_id."""
    keys = []
    for (dt, hour), evs in sorted(partition_events(events).items()):
        body = "".join(json.dumps(e, separators=(",", ":"), sort_keys=True) + "\n" for e in evs)
        key = s3_key(app, dt, hour, run_id)
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=gzip.compress(body.encode(), mtime=0),
            ContentType="application/x-ndjson",
            ServerSideEncryption="aws:kms",
            SSEKMSKeyId=kms_key_arn,
        )
        keys.append(key)
    return keys


def new_run_id():
    return uuid.uuid4().hex


def overlap_for(app, default_hours, overrides):
    return timedelta(hours=float(overrides.get(app, default_hours)))
