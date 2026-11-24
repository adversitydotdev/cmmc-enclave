"""Lambda entry point: suspend (or only report) Workspace users idle beyond N days."""
import json
import logging
import os
import sys
from datetime import datetime, timezone

import directory
import idle

log = logging.getLogger()
log.setLevel(os.environ.get("LOG_LEVEL", "INFO"))


def load_key(secrets, secret_arn):
    """Fetch the service account key. Never log the value or exception text derived from it."""
    try:
        info = json.loads(secrets.get_secret_value(SecretId=secret_arn)["SecretString"])
        if not info.get("client_email") or not info.get("private_key"):
            raise ValueError("incomplete")
    except Exception as exc:
        raise RuntimeError(f"service account key unreadable ({type(exc).__name__})") from None
    return info


def emit_metrics(idle_users, suspended):
    """CloudWatch Embedded Metric Format line; also the success marker for the alarms."""
    print(
        json.dumps(
            {
                "_aws": {
                    "Timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
                    "CloudWatchMetrics": [
                        {
                            "Namespace": "WorkspaceIdle",
                            "Dimensions": [[]],
                            "Metrics": [
                                {"Name": "Success", "Unit": "Count"},
                                {"Name": "IdleUsers", "Unit": "Count"},
                                {"Name": "Suspended", "Unit": "Count"},
                            ],
                        }
                    ],
                },
                "Success": 1,
                "IdleUsers": idle_users,
                "Suspended": suspended,
            }
        )
    )
    sys.stdout.flush()


def run(env, session, s3, now, run_id, sleep=None):
    mode = env.get("MODE", "report")
    directory.scope_for(mode)  # reject a bad mode before touching anything
    days = int(env.get("IDLE_DAYS", "90"))
    emails = idle.parse_list(env.get("EXCLUDE_EMAILS"))
    ous = idle.parse_list(env.get("EXCLUDE_OUS"))
    kwargs = {} if sleep is None else {"sleep": sleep}

    users, excluded, scanned = idle.find_idle(
        directory.list_users(session, **kwargs), now, days, emails, ous
    )

    suspended = failed = 0
    for user in users:
        if mode != "suspend":
            user["action"] = "reported"
            continue
        try:
            directory.suspend_user(session, user["id"], **kwargs)
            user["action"] = "suspended"
            suspended += 1
        except Exception as exc:
            user["action"] = "failed"
            failed += 1
            log.error("suspend failed for user id %s: %s", user["id"], type(exc).__name__)

    report = {
        "runId": run_id,
        "time": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "mode": mode,
        "idleDays": days,
        "scanned": scanned,
        "excluded": excluded,
        "idleUsers": len(users),
        "suspended": suspended,
        "failed": failed,
        "users": users,
    }
    key = idle.write_report(s3, env["BUCKET"], env["KMS_KEY_ARN"], now, run_id, report)
    log.info(
        "mode=%s scanned=%d idle=%d suspended=%d failed=%d report=%s",
        mode, scanned, len(users), suspended, failed, key,
    )

    if failed:  # the report above is written first so partial work is on record
        raise RuntimeError(f"suspend failed for {failed} of {len(users)} idle users; see {key}")
    emit_metrics(len(users), suspended)
    return {"scanned": scanned, "idle": len(users), "suspended": suspended, "report": key}


def lambda_handler(event, context):
    import boto3

    env = os.environ
    mode = env.get("MODE", "report")
    key = load_key(boto3.client("secretsmanager"), env["SECRET_ARN"])
    session = directory.build_session(key, env["ADMIN_USER"], mode)
    return run(
        env,
        session,
        boto3.client("s3"),
        datetime.now(timezone.utc),
        context.aws_request_id.replace("-", "") if context else idle.new_run_id(),
    )
