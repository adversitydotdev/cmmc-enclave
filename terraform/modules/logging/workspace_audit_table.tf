# ---- Athena table over the Workspace audit archive (3.3.5, 3.3.6) ----
# Written by collectors/workspace_audit: workspace-audit/application=<app>/dt=YYYY-MM-DD/<hour>-<runid>.jsonl.gz
# One JSON object per Reports API activity. A late event can be archived twice (crash between
# write and cursor update), so queries that count should dedupe on id.time + id.uniquequalifier.

resource "aws_glue_catalog_table" "workspace_audit" {
  provider      = aws.log_archive
  region        = var.home_region
  database_name = aws_glue_catalog_database.audit.name
  name          = "workspace_audit"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                        = "TRUE"
    classification                  = "json"
    "projection.enabled"            = "true"
    "projection.application.type"   = "enum"
    "projection.application.values" = "admin,login,drive,token,saml,user_accounts,groups,mobile,access_transparency"
    "projection.dt.type"            = "date"
    "projection.dt.format"          = "yyyy-MM-dd"
    "projection.dt.range"           = "NOW-3YEARS,NOW"
    "projection.dt.interval"        = "1"
    "projection.dt.interval.unit"   = "DAYS"
    "storage.location.template"     = "s3://${aws_s3_bucket.archive.id}/workspace-audit/application=$${application}/dt=$${dt}"
  }

  partition_keys {
    name = "application"
    type = "string"
  }
  partition_keys {
    name = "dt"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.archive.id}/workspace-audit/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    columns {
      name = "kind"
      type = "string"
    }
    columns {
      name = "id"
      type = "struct<time:string,uniquequalifier:string,applicationname:string,customerid:string>"
    }
    columns {
      name = "actor"
      type = "struct<email:string,profileid:string,callertype:string,key:string>"
    }
    columns {
      name = "ipaddress"
      type = "string"
    }
    columns {
      name = "ownerdomain"
      type = "string"
    }
    columns {
      name = "events"
      type = "array<struct<type:string,name:string,parameters:array<struct<name:string,value:string,intvalue:string,boolvalue:boolean,multivalue:array<string>>>>>"
    }
  }
}
