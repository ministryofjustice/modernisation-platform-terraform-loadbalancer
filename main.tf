data "aws_vpc" "shared" {
  tags = {
    "Name" = var.vpc_all
  }
}

# Terraform module which creates S3 Bucket resources for Load Balancer Access Logs on AWS.

module "s3-bucket" {
  count  = var.existing_bucket_name == "" ? 1 : 0
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=v6.4.0"

  providers = {
    aws.bucket-replication = aws.bucket-replication
  }
  bucket_prefix       = "${var.application_name}-lb-access-logs"
  bucket_policy       = [data.aws_iam_policy_document.bucket_policy.json]
  replication_enabled = false
  versioning_enabled  = true
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
  name                       = "${var.application_name}-lb"
  internal                   = var.internal_lb
  load_balancer_type         = var.load_balancer_type
  security_groups            = length(aws_security_group.lb) > 0 ? [aws_security_group.lb[0].id] : var.security_groups
  subnets                    = [var.public_subnets[0], var.public_subnets[1], var.public_subnets[2]]
  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout               = var.idle_timeout
  drop_invalid_header_fields = true

  access_logs {
    bucket  = var.existing_bucket_name != "" ? var.existing_bucket_name : module.s3-bucket[0].bucket.id
    prefix  = var.application_name
    enabled = true
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
  name   = replace("${var.application_name}-lb-access-logs", "-", "_") # dashes not allowed in name
  bucket = var.existing_bucket_name != "" ? var.existing_bucket_name : module.s3-bucket[0].bucket.id
  encryption_configuration {
    encryption_option = "SSE_S3"
  }
}

resource "aws_athena_named_query" "main" {
  name     = "${var.application_name}-create-table"
  database = aws_athena_database.lb-access-logs.name
  query = templatefile(
    "${path.module}/templates/create_table.sql",
    {
      bucket     = var.existing_bucket_name != "" ? var.existing_bucket_name : module.s3-bucket[0].bucket.id
      account_id = var.account_number
      region     = var.region
    }
  )
}

resource "aws_athena_workgroup" "lb-access-logs" {
  name = "${var.application_name}-lb-access-logs"

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

  name                 = "${var.application_name}-lb-${each.key}"
  port                 = each.value.port
  protocol             = each.value.protocol
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
      Name = "${var.application_name}-lb-${each.key}"
    },
  )
}
