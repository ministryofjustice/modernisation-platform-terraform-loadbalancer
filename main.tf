data "aws_vpc" "shared" {
  tags = {
    "Name" = var.vpc_all
  }
}

# data "aws_subnets" "shared-public" {
#   filter {
#     name   = "vpc-id"
#     values = [data.aws_vpc.shared.id]
#   }
#   tags = {
#     Name = "${var.public_subnets}-public*"
#   }
# }

# Terraform module which creates S3 Bucket resources for Load Balancer Access Logs on AWS.

module "s3-bucket" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=v6.0.3"

  providers = {
    aws.bucket-replication = aws.bucket-replication
  }
  bucket_prefix       = "${var.application_name}-lb-access-logs"
  bucket_policy       = [data.aws_iam_policy_document.bucket_policy.json]
  replication_enabled = false
  versioning_enabled  = true
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
    resources = ["${module.s3-bucket.bucket.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.default.arn]
    }
  }
}

data "aws_elb_service_account" "default" {}

# https://www.terraform.io/docs/providers/aws/d/region.html
# Get the region of the callee
data "aws_region" "current" {}

resource "aws_lb" "loadbalancer" {
  name               = "${var.application_name}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = [var.public_subnets[0], var.public_subnets[1], var.public_subnets[2]]
  enable_deletion_protection = true

  access_logs {
    bucket  = module.s3-bucket.bucket.id
    prefix  = "${var.application_name}"
    enabled = true
  }

  tags = merge(
    var.tags,
    {
      Name = "lb-${var.application_name}"
    },
  )
}

resource "aws_security_group" "lb" {
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
}

data "template_file" "lb-access-logs" {
  template = file("${path.module}/templates/create_table.sql")

  vars = {
    bucket     = module.s3-bucket.bucket.id
    account_id = var.account_number
    region     = var.region
  }
}

resource "aws_athena_database" "lb-access-logs" {
  name   = "loadbalancer_access_logs"
  bucket = module.s3-bucket.bucket.id
}

resource "aws_athena_named_query" "main" {
  name     = "${var.application_name}-create-table"
  database = "${aws_athena_database.lb-access-logs.name}"
  query    = "${data.template_file.lb-access-logs.rendered}"
}
