# ---- Athena and Glue over the CloudTrail archive (3.3.5, 3.3.6) ----

locals {
  glue_db     = replace("${var.name_prefix}_audit", "-", "_")
  trail_table = "cloudtrail_org"
  ct_columns = {
    eventversion        = "string"
    useridentity        = "struct<type:string,principalid:string,arn:string,accountid:string,invokedby:string,accesskeyid:string,username:string,sessioncontext:struct<attributes:struct<mfaauthenticated:string,creationdate:string>,sessionissuer:struct<type:string,principalid:string,arn:string,accountid:string,username:string>,ec2roledelivery:string,webidfederationdata:map<string,string>>>"
    eventtime           = "string"
    eventsource         = "string"
    eventname           = "string"
    awsregion           = "string"
    sourceipaddress     = "string"
    useragent           = "string"
    errorcode           = "string"
    errormessage        = "string"
    requestparameters   = "string"
    responseelements    = "string"
    additionaleventdata = "string"
    requestid           = "string"
    eventid             = "string"
    resources           = "array<struct<arn:string,accountid:string,type:string>>"
    eventtype           = "string"
    apiversion          = "string"
    readonly            = "string"
    recipientaccountid  = "string"
    serviceeventdetails = "string"
    sharedeventid       = "string"
    vpcendpointid       = "string"
    eventcategory       = "string"
    tlsdetails          = "struct<tlsversion:string,ciphersuite:string,clientprovidedhostheader:string>"
  }
  week = "day >= date_format(date_add('day', -7, current_date), '%Y/%m/%d')"
  tbl  = "${local.glue_db}.${local.trail_table}"
}

resource "aws_glue_catalog_database" "audit" {
  provider    = aws.log_archive
  region      = var.home_region
  name        = local.glue_db
  description = "Audit log tables over the log archive bucket."
}

resource "aws_glue_data_catalog_encryption_settings" "this" {
  provider = aws.log_archive
  region   = var.home_region

  data_catalog_encryption_settings {
    connection_password_encryption {
      return_connection_password_encrypted = true
      aws_kms_key_id                       = var.kms_key_arns.log_archive
    }
    encryption_at_rest {
      catalog_encryption_mode = "SSE-KMS"
      sse_aws_kms_key_id      = var.kms_key_arns.log_archive
    }
  }
}

resource "aws_glue_catalog_table" "cloudtrail" {
  provider      = aws.log_archive
  region        = var.home_region
  database_name = aws_glue_catalog_database.audit.name
  name          = local.trail_table
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                       = "TRUE"
    classification                 = "cloudtrail"
    "projection.enabled"           = "true"
    "projection.day.type"          = "date"
    "projection.day.format"        = "yyyy/MM/dd"
    "projection.day.range"         = "NOW-3YEARS,NOW"
    "projection.day.interval"      = "1"
    "projection.day.interval.unit" = "DAYS"
    "projection.account.type"      = "enum"
    "projection.account.values"    = join(",", local.all_ids)
    "projection.region.type"       = "enum"
    "projection.region.values"     = join(",", var.allowed_regions)
    "storage.location.template"    = "s3://${aws_s3_bucket.archive.id}/AWSLogs/${var.organization_id}/$${account}/CloudTrail/$${region}/$${day}"
  }

  partition_keys {
    name = "account"
    type = "string"
  }
  partition_keys {
    name = "region"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.archive.id}/AWSLogs/${var.organization_id}/"
    input_format  = "com.amazon.emr.cloudtrail.CloudTrailInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hive.hcatalog.data.JsonSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    dynamic "columns" {
      for_each = local.ct_columns
      content {
        name = columns.key
        type = columns.value
      }
    }
  }
}

resource "aws_athena_workgroup" "audit" {
  provider      = aws.log_archive
  region        = var.home_region
  name          = "${var.name_prefix}-audit"
  description   = "Audit review over the CloudTrail archive."
  force_destroy = false

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 10737418240

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = var.kms_key_arns.log_archive
      }
    }
  }
}

locals {
  weekly_queries = {
    privileged-api-calls = {
      description = "Weekly: IAM, Organizations, KMS, STS and SSO changes by principal (3.3.5, 3.1.7)."
      sql         = <<-EOT
        SELECT eventtime, recipientaccountid, useridentity.arn AS principal, eventsource, eventname, sourceipaddress, errorcode
        FROM ${local.tbl}
        WHERE ${local.week}
          AND readonly = 'false'
          AND eventsource IN ('iam.amazonaws.com','organizations.amazonaws.com','kms.amazonaws.com','sso.amazonaws.com','sts.amazonaws.com')
        ORDER BY eventtime DESC
      EOT
    }
    root-and-break-glass = {
      description = "Weekly: root and break-glass IAM user activity (3.1.7, 3.3.5)."
      sql         = <<-EOT
        SELECT eventtime, recipientaccountid, useridentity.type AS identity_type, useridentity.username AS username, eventsource, eventname, sourceipaddress
        FROM ${local.tbl}
        WHERE ${local.week}
          AND (useridentity.type = 'Root' OR useridentity.username = '${var.break_glass_user_name}')
        ORDER BY eventtime DESC
      EOT
    }
    security-service-disablement = {
      description = "Weekly: calls that disable or alter logging and detection services, or the archive itself (3.3.8, 3.14.7)."
      sql         = <<-EOT
        SELECT eventtime, recipientaccountid, useridentity.arn AS principal, eventsource, eventname, requestparameters
        FROM ${local.tbl}
        WHERE ${local.week}
          AND eventname IN ('StopLogging','DeleteTrail','UpdateTrail','PutEventSelectors',
            'StopConfigurationRecorder','DeleteConfigurationRecorder','DeleteDeliveryChannel','DeleteOrganizationConformancePack',
            'DeleteDetector','DisableOrganizationAdminAccount','UpdateDetector','DisableSecurityHub','BatchDisableStandards','DisassociateMembers',
            'PutBucketPolicy','DeleteBucketPolicy','PutObjectLockConfiguration','PutBucketVersioning','PutBucketLifecycleConfiguration',
            'ScheduleKeyDeletion','DisableKey','PutBackupVaultAccessPolicy','DeleteBackupVault','DeleteBackupVaultLockConfiguration')
        ORDER BY eventtime DESC
      EOT
    }
    failed-auth-and-denied = {
      description = "Weekly: failed console logins and access denied by principal (3.1.8, 3.3.5)."
      sql         = <<-EOT
        SELECT useridentity.arn AS principal, eventname, errorcode, count(*) AS events, min(eventtime) AS first_seen, max(eventtime) AS last_seen
        FROM ${local.tbl}
        WHERE ${local.week}
          AND (errorcode IN ('AccessDenied','Client.UnauthorizedOperation','UnauthorizedOperation') OR (eventname = 'ConsoleLogin' AND responseelements LIKE '%Failure%'))
        GROUP BY 1, 2, 3
        ORDER BY events DESC
      EOT
    }
    archive-and-enclave-object-access = {
      description = "Weekly: S3 data events by principal and bucket on the archive and enclave buckets (3.3.1, 3.3.9)."
      sql         = <<-EOT
        SELECT useridentity.arn AS principal, eventname, json_extract_scalar(requestparameters, '$.bucketName') AS bucket, count(*) AS events
        FROM ${local.tbl}
        WHERE ${local.week}
          AND eventcategory = 'Data'
        GROUP BY 1, 2, 3
        ORDER BY events DESC
      EOT
    }
  }
}

resource "aws_athena_named_query" "weekly" {
  for_each    = local.weekly_queries
  provider    = aws.log_archive
  region      = var.home_region
  name        = "weekly-${each.key}"
  description = each.value.description
  workgroup   = aws_athena_workgroup.audit.id
  database    = aws_glue_catalog_database.audit.name
  query       = each.value.sql

  depends_on = [aws_glue_catalog_table.cloudtrail]
}
