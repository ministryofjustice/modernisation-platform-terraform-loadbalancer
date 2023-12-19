data "aws_vpc" "shared" {
  tags = {
    "Name" = var.vpc_all
  }
}

# Terraform module which creates S3 Bucket resources for Load Balancer Access Logs on AWS.

module "s3-bucket" {
  count  = var.existing_bucket_name == "" && var.access_logs ? 1 : 0
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=v7.1.0"

  providers = {
    aws.bucket-replication = aws.bucket-replication
  }
  bucket_prefix       = "${var.application_name}-lb-access-logs"
  bucket_policy       = [data.aws_iam_policy_document.bucket_policy[0].json]
  replication_enabled = false
  versioning_enabled  = var.s3_versioning
  force_destroy       = var.force_destroy_bucket
  lifecycle_rule = [
    {
      id      = "main"
      enabled = "Enabled"
      prefix  = ""

      tags = {
        rule      = "log"
        autoclean = "true"
      }

      transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
          }, {
          days          = 365
          storage_class = "GLACIER"
        }
      ]

      expiration = {
        days = 730
      }

      noncurrent_version_transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
          }, {
          days          = 365
          storage_class = "GLACIER"
        }
      ]

      noncurrent_version_expiration = {
        days = 730
      }
    }
  ]

  tags = var.tags
}

data "aws_iam_policy_document" "bucket_policy" {
  count = var.access_logs ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject"
    ]
    resources = [var.existing_bucket_name != "" ? "arn:aws:s3:::${var.existing_bucket_name}/${var.application_name}/AWSLogs/${var.account_number}/*" : "${module.s3-bucket[0].bucket.arn}/${var.application_name}/AWSLogs/${var.account_number}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.default.arn]
    }
  }
  statement {
    sid = "AWSLogDeliveryWrite"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [var.existing_bucket_name != "" ? "arn:aws:s3:::${var.existing_bucket_name}/${var.application_name}/AWSLogs/${var.account_number}/*" : "${module.s3-bucket[0].bucket.arn}/${var.application_name}/AWSLogs/${var.account_number}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"

      values = [
        "bucket-owner-full-control"
      ]
    }
  }

  statement {
    sid = "AWSLogDeliveryAclCheck"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = [
      "s3:GetBucketAcl"
    ]

    resources = [
      var.existing_bucket_name != "" ? "arn:aws:s3:::${var.existing_bucket_name}" : module.s3-bucket[0].bucket.arn
    ]
  }
}

data "aws_elb_service_account" "default" {}

#tfsec:ignore:aws-elb-alb-not-public
resource "aws_lb" "loadbalancer" {
  #checkov:skip=CKV_AWS_150:preventing destroy can be controlled outside of the module
  #checkov:skip=CKV2_AWS_28:WAF is configured outside of the module for more flexibility
  name                             = "${var.application_name}-lb"
  internal                         = var.internal_lb
  load_balancer_type               = var.load_balancer_type
  security_groups                  = length(aws_security_group.lb) > 0 ? [aws_security_group.lb[0].id] : var.security_groups
  subnets                          = concat(var.subnets, var.public_subnets)
  enable_deletion_protection       = var.enable_deletion_protection
  idle_timeout                     = var.idle_timeout
  drop_invalid_header_fields       = true
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  dns_record_client_routing_policy = var.dns_record_client_routing_policy

  dynamic "access_logs" {
    for_each = var.access_logs ? [1] : []
    content {
      bucket  = var.existing_bucket_name != "" ? var.existing_bucket_name : module.s3-bucket[0].bucket.id
      prefix  = var.application_name
      enabled = var.access_logs
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.application_name}-lb"
    },
  )
}

resource "aws_security_group" "lb" {
  count       = var.security_groups == null ? 1 : 0
  name        = "${var.application_name}-lb-security-group"
  description = "Controls access to the loadbalancer"
  vpc_id      = data.aws_vpc.shared.id

  dynamic "ingress" {
    for_each = var.loadbalancer_ingress_rules
    content {
      description     = lookup(ingress.value, "description", null)
      from_port       = lookup(ingress.value, "from_port", null)
      to_port         = lookup(ingress.value, "to_port", null)
      protocol        = lookup(ingress.value, "protocol", null)
      cidr_blocks     = lookup(ingress.value, "cidr_blocks", null)
      security_groups = lookup(ingress.value, "security_groups", null)
    }
  }

  dynamic "egress" {
    for_each = var.loadbalancer_egress_rules
    content {
      description     = lookup(egress.value, "description", null)
      from_port       = lookup(egress.value, "from_port", null)
      to_port         = lookup(egress.value, "to_port", null)
      protocol        = lookup(egress.value, "protocol", null)
      cidr_blocks     = lookup(egress.value, "cidr_blocks", null)
      security_groups = lookup(egress.value, "security_groups", null)
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.application_name}-lb-security-group"
    },
  )
}

resource "aws_athena_database" "lb-access-logs" {
  count  = var.access_logs ? 1 : 0
  name   = replace("${var.application_name}-lb-access-logs", "-", "_") # dashes not allowed in name
  bucket = var.existing_bucket_name != "" ? var.existing_bucket_name : module.s3-bucket[0].bucket.id
  encryption_configuration {
    encryption_option = "SSE_S3"
  }
}

resource "aws_athena_workgroup" "lb-access-logs" {
  count = var.access_logs ? 1 : 0
  name  = "${var.application_name}-lb-access-logs"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = var.existing_bucket_name != "" ? "s3://${var.existing_bucket_name}/output/" : "s3://${module.s3-bucket[0].bucket.id}/output/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.application_name}-lb-access-logs"
    },
  )
}

resource "aws_lb_target_group" "this" {
  for_each = var.lb_target_groups

  name                 = each.key
  port                 = each.value.port
  protocol             = "TCP"
  target_type          = "alb"
  deregistration_delay = each.value.deregistration_delay
  vpc_id               = data.aws_vpc.shared.id

  dynamic "health_check" {
    for_each = each.value.health_check != null ? [each.value.health_check] : []
    content {
      enabled             = health_check.value.enabled
      interval            = health_check.value.interval
      healthy_threshold   = health_check.value.healthy_threshold
      matcher             = health_check.value.matcher
      path                = health_check.value.path
      port                = health_check.value.port
      timeout             = health_check.value.timeout
      unhealthy_threshold = health_check.value.unhealthy_threshold
    }
  }
  dynamic "stickiness" {
    for_each = each.value.stickiness != null ? [each.value.stickiness] : []
    content {
      enabled         = stickiness.value.enabled
      type            = stickiness.value.type
      cookie_duration = stickiness.value.cookie_duration
      cookie_name     = stickiness.value.cookie_name
    }
  }

  tags = merge(
    var.tags,
    {
      Name = each.key
    },
  )
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = var.lb_target_groups

  target_group_arn = aws_lb_target_group.this[each.key].arn
  target_id        = aws_lb.loadbalancer.arn
  port             = coalesce(each.value.attachment_port, each.value.port)
}

# Glue Permissions
resource "aws_iam_role" "glue" {
  count              = var.access_logs ? 1 : 0
  name               = "glue-${var.application_name}"
  assume_role_policy = data.aws_iam_policy_document.glue_assume[count.index].json
}

data "aws_iam_policy_document" "glue_assume" {
  count = var.access_logs ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "glue_s3" {
  count = var.access_logs ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = [var.existing_bucket_name != "" ? "arn:aws:s3:::${var.existing_bucket_name}/${var.application_name}/AWSLogs/${var.account_number}/*" : "${module.s3-bucket[0].bucket.arn}/${var.application_name}/AWSLogs/${var.account_number}/*"]
  }
}

resource "aws_iam_policy" "glue_s3" {
  count  = var.access_logs ? 1 : 0
  name   = "glue-s3-${var.application_name}"
  policy = data.aws_iam_policy_document.glue_s3[count.index].json
}

resource "aws_iam_role_policy_attachment" "glue_s3" {
  count      = var.access_logs ? 1 : 0
  role       = aws_iam_role.glue[count.index].name
  policy_arn = aws_iam_policy.glue_s3[count.index].arn
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  count      = var.access_logs ? 1 : 0
  role       = aws_iam_role.glue[count.index].id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Catalog Tables
resource "aws_glue_catalog_table" "application_lb_logs" {
  count         = var.access_logs && var.load_balancer_type == "application" ? 1 : 0
  name          = "${var.application_name}-application-lb-logs"
  database_name = aws_athena_database.lb-access-logs[0].name

  table_type = "EXTERNAL_TABLE"

  partition_keys {
    name = "day"
    type = "string"
  }

  parameters = {
    "projection.enabled"           = "true"
    "projection.day.format"        = "yyyy/MM/dd"
    "projection.day.interval"      = "1"
    "projection.day.interval.unit" = "DAYS"
    "projection.day.type"          = "date"
    "projection.day.range"         = "2023/01/01,NOW"
    "storage.location.template"    = var.existing_bucket_name != "" ? "s3://${var.existing_bucket_name}/${var.application_name}/AWSLogs/${var.account_number}/elasticloadbalancing/${var.region}/$${day}" : "s3://${module.s3-bucket[0].bucket.id}/${var.application_name}/AWSLogs/${var.account_number}/elasticloadbalancing/${var.region}/$${day}"
  }
  storage_descriptor {
    location      = var.existing_bucket_name != "" ? "s3://${var.existing_bucket_name}/${var.application_name}/AWSLogs/${var.account_number}/elasticloadbalancing/${var.region}" : "s3://${module.s3-bucket[0].bucket.id}/${var.application_name}/AWSLogs/${var.account_number}/elasticloadbalancing/${var.region}"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    ser_de_info {
      name = "application_lb_logs"
      parameters = {
        "serialization.format" = "1",
        "input.regex"          = "([^ ]*) ([^ ]*) ([^ ]*) ([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}):([0-9]+) ([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}):([0-9]+) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) \"([^\"]*)\" \"([^\"]*)\" ([^ ]*) ([^ ]*) ([^ ]*) \"([^\"]*)\" \"([^\"]*)\" \"([^\"]*)\" ([^ ]*) ([^ ]*) \"([^\"]*)\" \"([^\"]*)\" \"([^\"]*)\" \"([^\"]*)\" \"([^\"]*)\" \"([^\"]*)\" \"([^\"]*)\""
      }
      serialization_library = "org.apache.hadoop.hive.serde2.RegexSerDe"
    }
    columns {
      name = "type"
      type = "string"
    }
    columns {
      name = "time"
      type = "string"
    }
    columns {
      name = "elb"
      type = "string"
    }
    columns {
      name = "client_ip"
      type = "string"
    }
    columns {
      name = "client_port"
      type = "int"
    }
    columns {
      name = "target_ip"
      type = "string"
    }
    columns {
      name = "target_port"
      type = "int"
    }
    columns {
      name = "request_processing_time"
      type = "double"
    }
    columns {
      name = "target_processing_time"
      type = "double"
    }
    columns {
      name = "response_processing_time"
      type = "double"
    }
    columns {
      name = "elb_status_code"
      type = "int"
    }
    columns {
      name = "target_status_code"
      type = "int"
    }
    columns {
      name = "received_bytes"
      type = "int"
    }
    columns {
      name = "sent_bytes"
      type = "int"
    }
    columns {
      name = "request"
      type = "string"
    }
    columns {
      name = "user_agent"
      type = "string"
    }
    columns {
      name = "ssl_cipher"
      type = "string"
    }
    columns {
      name = "ssl_protocol"
      type = "string"
    }
    columns {
      name = "target_group_arn"
      type = "string"
    }
    columns {
      name = "trace_id"
      type = "string"
    }
    columns {
      name = "domain_name"
      type = "string"
    }
    columns {
      name = "chosen_cert_arn"
      type = "string"
    }
    columns {
      name = "matched_rule_priority"
      type = "int"
    }
    columns {
      name = "request_creation_time"
      type = "string"
    }
    columns {
      name = "actions_executed"
      type = "string"
    }
    columns {
      name = "redirect_url"
      type = "string"
    }
    columns {
      name = "lambda_error_reason"
      type = "string"
    }
    columns {
      name = "target_port_list"
      type = "string"
    }
    columns {
      name = "target_status_code_list"
      type = "string"
    }
    columns {
      name = "classification"
      type = "string"
    }
    columns {
      name = "classification_reason"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "network_lb_logs" {
  count         = var.access_logs && var.load_balancer_type == "network" ? 1 : 0
  name          = "${var.application_name}-network-lb-logs"
  database_name = aws_athena_database.lb-access-logs[0].name

  table_type = "EXTERNAL_TABLE"

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }

  storage_descriptor {
    location      = var.existing_bucket_name != "" ? "s3://${var.existing_bucket_name}/${var.application_name}/AWSLogs/${var.account_number}/elasticloadbalancing/${var.region}/" : "s3://${module.s3-bucket[0].bucket.id}/${var.application_name}/AWSLogs/${var.account_number}/elasticloadbalancing/${var.region}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    ser_de_info {
      name = "network_lb_logs"
      parameters = {
        "serialization.format" = "1",
        "input.regex"          = "([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*):([0-9]*) ([^ ]*):([0-9]*) ([-.0-9]*) ([-.0-9]*) ([-0-9]*) ([-0-9]*) ([-0-9]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*)$"
      }
      serialization_library = "org.apache.hadoop.hive.serde2.RegexSerDe"
    }
    columns {
      name = "type"
      type = "string"
    }
    columns {
      name = "version"
      type = "string"
    }
    columns {
      name = "time"
      type = "string"
    }
    columns {
      name = "elb"
      type = "string"
    }
    columns {
      name = "listener_id"
      type = "string"
    }
    columns {
      name = "client_ip"
      type = "string"
    }
    columns {
      name = "client_port"
      type = "int"
    }
    columns {
      name = "target_ip"
      type = "string"
    }
    columns {
      name = "target_port"
      type = "int"
    }
    columns {
      name = "tcp_connection_time"
      type = "double"
    }
    columns {
      name = "tls_handshake_time"
      type = "double"
    }
    columns {
      name = "received_bytes"
      type = "bigint"
    }
    columns {
      name = "sent_bytes"
      type = "bigint"
    }
    columns {
      name = "incoming_tls_alert"
      type = "int"
    }
    columns {
      name = "cert_arn"
      type = "string"
    }
    columns {
      name = "certificate_serial"
      type = "string"
    }
    columns {
      name = "tls_cipher_suite"
      type = "string"
    }
    columns {
      name = "tls_protocol_version"
      type = "string"
    }
    columns {
      name = "tls_named_group"
      type = "string"
    }
    columns {
      name = "domain_name"
      type = "string"
    }
    columns {
      name = "alpn_fe_protocol"
      type = "string"
    }
    columns {
      name = "alpn_be_protocol"
      type = "string"
    }
    columns {
      name = "alpn_client_preference_list"
      type = "string"
    }
    columns {
      name = "tls_connection_creation_time"
      type = "string"
    }
  }
}
