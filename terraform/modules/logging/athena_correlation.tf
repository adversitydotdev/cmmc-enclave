# ---- Saved queries joining CloudTrail and the Workspace audit on user email (3.3.5, 3.3.6) ----
# Identity Center sessions carry the user's email as the role session name
# (arn:...:assumed-role/AWSReservedSSO_<set>_<id>/<email>) because SCIM syncs the
# Workspace primary email as the user name. Sign-in events carry it in userName or
# additionalEventData, so the AWS side coalesces the three. Workspace sides
# dedupe on the (email, time, event) triple because the collector can archive a
# late event twice.

locals {
  ws_tbl = "${local.glue_db}.workspace_audit"
  ws_day = "dt >= date_format(date_add('day', -7, current_date), '%Y-%m-%d')"

  # AWS-side user email, lowercased. Empty for non-SSO principals.
  ct_email = "lower(coalesce(nullif(useridentity.username, ''), regexp_extract(useridentity.arn, 'assumed-role/AWSReservedSSO_[^/]+/(.+)$', 1), json_extract_scalar(additionaleventdata, '$.UserName')))"

  ct_signin_events = "('ConsoleLogin','Federate','Authenticate','UserAuthentication','ExternalIdPDirectoryLogin')"

  # CTEs reused by the queries below.
  ct_signins_cte = <<-EOT
    ct_signins AS (
      SELECT ${local.ct_email} AS email, from_iso8601_timestamp(eventtime) AS ts, eventname, recipientaccountid, sourceipaddress,
             CASE WHEN errorcode IS NOT NULL OR responseelements LIKE '%Failure%' THEN 'failure' ELSE 'success' END AS outcome
      FROM ${local.tbl}
      WHERE ${local.week}
        AND eventsource IN ('signin.amazonaws.com','sso.amazonaws.com')
        AND eventname IN ${local.ct_signin_events}
    )
  EOT

  ws_logins_cte = <<-EOT
    ws_logins AS (
      SELECT lower(actor.email) AS email, from_iso8601_timestamp(id.time) AS ts, e.name AS event, ipaddress
      FROM ${local.ws_tbl} w CROSS JOIN UNNEST(w.events) AS t(e)
      WHERE application = 'login' AND ${local.ws_day}
        AND e.name IN ('login_success','login_failure','login_challenge')
      GROUP BY 1, 2, 3, 4
    )
  EOT

  correlation_queries = {
    correlate-signins-both-sides = {
      description = "Weekly: per person, Workspace sign-ins next to AWS sign-ins. Flags AWS sign-ins with no Workspace login the same week and Workspace login failures followed by AWS success (3.3.5, 3.3.6)."
      sql         = <<-EOT
        WITH ${local.ct_signins_cte},
        ${local.ws_logins_cte},
        ws AS (
          SELECT email, count_if(event = 'login_success') AS ws_success, count_if(event = 'login_failure') AS ws_failure, max(ts) AS ws_last
          FROM ws_logins GROUP BY 1
        ),
        aws AS (
          SELECT email, count_if(outcome = 'success') AS aws_success, count_if(outcome = 'failure') AS aws_failure, max(ts) AS aws_last
          FROM ct_signins WHERE email IS NOT NULL GROUP BY 1
        )
        SELECT coalesce(ws.email, aws.email) AS email,
               ws.ws_success, ws.ws_failure, ws.ws_last,
               aws.aws_success, aws.aws_failure, aws.aws_last,
               CASE
                 WHEN aws.aws_success > 0 AND coalesce(ws.ws_success, 0) = 0 THEN 'aws signin without workspace login'
                 WHEN coalesce(ws.ws_failure, 0) > 0 AND aws.aws_success > 0 THEN 'workspace failures then aws success'
                 WHEN coalesce(aws.aws_failure, 0) > 0 AND coalesce(ws.ws_failure, 0) > 0 THEN 'failures on both sides'
                 ELSE ''
               END AS flag
        FROM ws FULL OUTER JOIN aws ON ws.email = aws.email
        ORDER BY flag DESC, email
      EOT
    }
    correlate-admin-actions-same-person = {
      description = "Weekly: people who made Workspace admin changes and AWS privileged changes in the same week, with counts (3.3.5, 3.1.7)."
      sql         = <<-EOT
        WITH ws_admin AS (
          SELECT lower(actor.email) AS email, from_iso8601_timestamp(id.time) AS ts, e.name AS event
          FROM ${local.ws_tbl} w CROSS JOIN UNNEST(w.events) AS t(e)
          WHERE application = 'admin' AND ${local.ws_day}
          GROUP BY 1, 2, 3
        ),
        ct_priv AS (
          SELECT ${local.ct_email} AS email, from_iso8601_timestamp(eventtime) AS ts, eventsource, eventname, recipientaccountid
          FROM ${local.tbl}
          WHERE ${local.week}
            AND readonly = 'false'
            AND eventsource IN ('iam.amazonaws.com','organizations.amazonaws.com','kms.amazonaws.com','sso.amazonaws.com','identitystore.amazonaws.com')
        )
        SELECT w.email,
               count(DISTINCT w.ts) AS workspace_admin_actions, array_agg(DISTINCT w.event) AS workspace_events,
               count(DISTINCT c.ts) AS aws_privileged_calls, array_agg(DISTINCT c.eventname) AS aws_events,
               min(w.ts) AS first_workspace_admin, min(c.ts) AS first_aws_privileged
        FROM ws_admin w JOIN ct_priv c ON w.email = c.email
        GROUP BY 1
        ORDER BY aws_privileged_calls DESC
      EOT
    }
    correlate-workspace-login-then-aws-console = {
      description = "Weekly: each Workspace login with the AWS sign-ins and console-role activity by the same person in the following hour. A sign-in without a preceding Workspace login shows in correlate-signins-both-sides (3.3.5, 3.3.6)."
      sql         = <<-EOT
        WITH ${local.ws_logins_cte},
        ct_console AS (
          SELECT ${local.ct_email} AS email, from_iso8601_timestamp(eventtime) AS ts, eventsource, eventname, recipientaccountid, sourceipaddress
          FROM ${local.tbl}
          WHERE ${local.week}
            AND (eventname IN ${local.ct_signin_events} OR useridentity.arn LIKE '%assumed-role/AWSReservedSSO_%')
        )
        SELECT w.email, w.ts AS workspace_login, w.ipaddress AS workspace_ip,
               min(c.ts) AS first_aws_activity, count(c.ts) AS aws_events,
               array_agg(DISTINCT c.recipientaccountid) AS aws_accounts, array_agg(DISTINCT c.sourceipaddress) AS aws_ips
        FROM ws_logins w
        LEFT JOIN ct_console c ON c.email = w.email AND c.ts BETWEEN w.ts AND date_add('hour', 1, w.ts)
        WHERE w.event = 'login_success'
        GROUP BY 1, 2, 3
        ORDER BY w.ts DESC
      EOT
    }
  }
}

resource "aws_athena_named_query" "correlation" {
  for_each    = local.correlation_queries
  provider    = aws.log_archive
  region      = var.home_region
  name        = each.key
  description = each.value.description
  workgroup   = aws_athena_workgroup.audit.id
  database    = aws_glue_catalog_database.audit.name
  query       = each.value.sql

  depends_on = [aws_glue_catalog_table.cloudtrail, aws_glue_catalog_table.workspace_audit]
}
