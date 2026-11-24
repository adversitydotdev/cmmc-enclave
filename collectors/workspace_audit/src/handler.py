"""Lambda entry point: Workspace audit logs -> log archive bucket."""
import json
import logging
import os
import sys
from datetime import datetime, timedelta, timezone

import collector
import reports

log = logging.getLogger()
log.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

DEFAULT_APPS = "admin,login,drive,token,saml,user_accounts,groups,mobile,access_transparency"


def load_key(secrets, secret_arn):
    """Fetch the service account key. Never log the value or exception text derived from it."""
    try:
        info = json.loads(secrets.get_secret_value(SecretId=secret_arn)["SecretString"])
        if not info.get("client_email") or not info.get("private_key"):
            raise ValueError("incomplete")
    except Exception as exc:
        raise RuntimeError(f"service account key unreadable ({type(exc).__name__})") from None
    return info


def emit_metrics(records, applications, objects):
    """CloudWatch Embedded Metric Format line; also the success marker for the alarms."""
    print(
        json.dumps(
            {
                "_aws": {
                    "Timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
                    "CloudWatchMetrics": [
                        {
                            "Namespace": "WorkspaceAudit",
                            "Dimensions": [[]],
                            "Metrics": [
                                {"Name": "Success", "Unit": "Count"},
                                {"Name": "Records", "Unit": "Count"},
                                {"Name": "Applications", "Unit": "Count"},
                                {"Name": "ObjectsWritten", "Unit": "Count"},
                            ],
                        }
                    ],
                },
                "Success": 1,
                "Records": records,
                "Applications": applications,
                "ObjectsWritten": objects,
            }
        )
    )
    sys.stdout.flush()


def run(env, session, state, s3, now, run_id, sleep=None):
    apps = [a.strip() for a in env.get("APPLICATIONS", DEFAULT_APPS).split(",") if a.strip()]
    default_overlap = env.get("OVERLAP_HOURS", "6")
    overrides = json.loads(env.get("OVERLAP_HOURS_BY_APP") or "{}")
    lookback = timedelta(hours=float(env.get("INITIAL_LOOKBACK_HOURS", "24")))

    records = objects = collected = 0
    failed = []
    for app in apps:
        try:
            overlap = collector.overlap_for(app, default_overlap, overrides)
            events, cursor, seen = collector.collect_app(session, state, app, now, overlap, lookback, sleep)
            keys = collector.write_events(s3, env["BUCKET"], env["KMS_KEY_ARN"], app, events, run_id)
            state.put(app, cursor, seen)  # after the writes: a crash re-archives instead of losing events
        except reports.AppUnavailable as exc:
            log.warning("skipping application %s: HTTP %s %s", exc.app, exc.status, exc.reason)
            continue
        except Exception as exc:
            log.error("application %s failed: %s", app, type(exc).__name__)
            failed.append(app)
            continue
        collected += 1
        records += len(events)
        objects += len(keys)
        log.info("application %s: %d records, %d objects", app, len(events), len(keys))

    if failed:
        raise RuntimeError(f"collection failed for: {', '.join(failed)}")
    if collected == 0:
        raise RuntimeError("no application was readable; check scope, delegation and admin user")
    emit_metrics(records, collected, objects)
    return {"records": records, "applications": collected, "objects": objects}


def lambda_handler(event, context):
    import boto3

    from state import DynamoState

    env = os.environ
    key = load_key(boto3.client("secretsmanager"), env["SECRET_ARN"])
    session = reports.build_session(key, env["ADMIN_USER"])
    return run(
        env,
        session,
        DynamoState(boto3.client("dynamodb"), env["STATE_TABLE"]),
        boto3.client("s3"),
        datetime.now(timezone.utc),
        context.aws_request_id.replace("-", "") if context else collector.new_run_id(),
    )
