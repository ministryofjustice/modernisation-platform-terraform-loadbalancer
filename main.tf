data "aws_vpc" "shared" {
  tags = {
    "Name" = var.vpc_all
  }
}

# Terraform module which creates S3 Bucket resources for Load Balancer Access Logs on AWS.

module "s3-bucket" {
  count  = var.existing_bucket_name == "" && var.access_logs ? 1 : 0
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=8688bc15a08fbf5a4f4eef9b7433c5a417df8df1" # v7.0.0

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

resource "aws_athena_named_query" "main" {
  count     = var.access_logs ? 1 : 0
  name      = "${var.application_name}-create-table"
  database  = aws_athena_database.lb-access-logs[0].name
  workgroup = aws_athena_workgroup.lb-access-logs[0].id

  query = templatefile(
    "${path.module}/templates/create_table.sql",
    {
      bucket           = var.existing_bucket_name != "" ? var.existing_bucket_name : module.s3-bucket[0].bucket.id
      account_id       = var.account_number
      region           = var.region
      application_name = var.application_name
      database         = aws_athena_database.lb-access-logs[0].name
    }
  )
}

resource "aws_athena_workgroup" "lb-access-logs" {
  count = var.access_logs ? 1 : 0
  name  = "${var.application_name}-lb-access-logs"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

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

# Glue crawler to update Athena Table
# Role for crawler
resource "aws_iam_role" "lb_glue_crawler" {
  count              = var.access_logs ? 1 : 0
  name               = "ssm-glue-crawler"
  assume_role_policy = data.aws_iam_policy_document.lb_glue_crawler_assume.json
}

data "aws_iam_policy_document" "lb_glue_crawler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "lb_glue_crawler" {
  count  = var.access_logs ? 1 : 0
  name   = "LbGlueCrawler"
  policy = data.aws_iam_policy_document.lb_glue_crawler[count.index].json
}

data "aws_iam_policy_document" "lb_glue_crawler" {
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

# Glue Crawler Policy
resource "aws_iam_role_policy_attachment" "lb_glue_crawler" {
  count      = var.access_logs ? 1 : 0
  role       = aws_iam_role.lb_glue_crawler[count.index].name
  policy_arn = aws_iam_policy.lb_glue_crawler[count.index].arn
}

resource "aws_iam_role_policy_attachment" "lb_glue_service" {
  count      = var.access_logs ? 1 : 0
  role       = aws_iam_role.lb_glue_crawler[count.index].id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Glue Crawler
resource "aws_glue_crawler" "ssm_resource_sync" {
  #checkov:skip=CKV_AWS_195
  count         = var.access_logs ? 1 : 0
  database_name = aws_athena_database.lb-access-logs[0].name
  name          = "lb_resource_sync"
  role          = aws_iam_role.lb_glue_crawler[count.index].arn
  schedule      = var.log_schedule

  s3_target {
    path = var.existing_bucket_name != "" ? "s3://${var.existing_bucket_name}/${var.application_name}/AWSLogs/${var.account_number}/elasticloadbalancing/" : "s3://${module.s3-bucket[0].bucket.id}/${var.application_name}/AWSLogs/${var.account_number}/elasticloadbalancing/"
  }
}

resource "aws_glue_catalog_table" "lb_log_table" {
  name = "${var.application_name}-lb-log-table"
  database_name = "${var.application_name}-database"

  table_type = "EXTERNAL_TABLE"

  storage_descriptor {
    location = var.existing_bucket_name != "" ? "s3://${var.existing_bucket_name}/${var.application_name}/AWSLogs/${var.account_number}/" : "s3://${module.s3-bucket[0].bucket.id}/${var.application_name}/AWSLogs/${var.account_number}/"
    input_format = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    ser_de_info {
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
      type = "string"
    }

    columns {
      name = "target_status_code"
      type = "string"
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
      name = "request_verb"
      type = "string"
    }

    columns {
      name = "request_url"
      type = "string"
    }

    columns {
      name = "request_proto"
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
      type = "string"
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
      name = "new_field"
      type = "string"
    }
  }
}
