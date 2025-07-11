# Modernisation Platform Terraform Loadbalancer Module with Access Logs enabled

[![Standards Icon]][Standards Link] [![Format Code Icon]][Format Code Link] [![Scorecards Icon]][Scorecards Link] [![SCA Icon]][SCA Link] [![Terraform SCA Icon]][Terraform SCA Link]

A Terraform module that creates an application loadbalancer (with loadbalancer security groups) or network loadbalancer in AWS with logging enabled, s3 to store logs and Athena DB to query logs.

An s3 bucket name can be provided in the module by adding the `existing_bucket_name` variable and adding the bucket name. Otherwise, if no bucket exists one will be created and no variable needs to be set in the module. Application loadbalancers and network loadbalancers do not log to the same S3 bucket location. If you're using existing buckets they also need to have specific permissions applied to them. See the [External buckets](#external-buckets) section for more information.

Either pass in existing security group(s) to attach to the load balancer using the `security_groups` variable, or define `loadbalancer_ingress_rules` and `loadbalancer_egress_rules` variables to create a new security group within the module.

If using the module to create the security group, you can use locals to define the rules for the `loadbalancer_ingress_rules` and `loadbalancer_egress_rules` variables as in the below example.

```
locals {
  loadbalancer_ingress_rules = {
    "cluster_ec2_lb_ingress" = {
      description     = "Cluster EC2 loadbalancer ingress rule"
      from_port       = 8080
      to_port         = 8080
      protocol        = "tcp"
      cidr_blocks     = []
      security_groups = []
    },
    "cluster_ec2_bastion_ingress" = {
      description     = "Cluster EC2 bastion ingress rule"
      from_port       = 3389
      to_port         = 3389
      protocol        = "tcp"
      cidr_blocks     = []
      security_groups = []
    }
  }
  loadbalancer_egress_rules = {
    "cluster_ec2_lb_egress" = {
      description     = "Cluster EC2 loadbalancer egress rule"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = []
    }
  }
}
```

Loadbalancer target groups and listeners need to be created separately.

The use of "aws_glue_catalog_table" resources for application and network loadbalancers means that logs appearing in the S3 bucket will be available to query via Athena without having to carry out any manual Athena config steps.

## Module created S3 access_logs bucket

By default the loadbalancer will set up an access_logs bucket for you, unless you set access_logs = false initially for testing or some other reason. Setting this back to true after the lb has been deployed will then create the bucket for you. The reason for the 'depends_on' here is that without the module.s3-bucket resource being created first, the module.lb resource will fail with a validation error.

```hcl
  depends_on = [
    module.s3-bucket
  ]
```

## External buckets

If you decide to use externally created buckets they need to have been created and have appropriate permissions applied to them BEFORE `access_logs = true` and `existing_bucket_name` values are added to the lb code. If you add these values before the bucket is created you will get an error because the lb module will run a check to see if the s3 bucket is writeable and if it is not it will fail.

So to use `external_bucket_name` the deployment steps are:

1. Set `access_logs = false` in the lb create code & create the lb
2. Create the bucket - making sure the appropriate permissions are applied
3. Set `existing_bucket_name` in the lb create code as your-bucket-name-GUID

### External bucket permissions

For simplicity the bucket can be created with the following policy attached to it. This applies whether the loadbalancer is an "application" or "network" loadbalancer. This uses the bucket_policy_v2 implementation using the s3_bucket module:

```hcl
  public-lb-logs-bucket = {
    sse_algorithm = "AES256" # required for Network Loadbalancers
    bucket_policy_v2 = [
      {
        effect = "Allow"
        actions = [
          "s3:PutObject",
        ]
        principals = {
          identifiers = ["arn:aws:iam::652711504416:root"]
          type        = "AWS"
        }
      },
      {
        effect = "Allow"
        actions = [
          "s3:PutObject"
        ]
        principals = {
          identifiers = ["delivery.logs.amazonaws.com"]
          type        = "Service"
        }

        conditions = [
          {
            test     = "StringEquals"
            variable = "s3:x-amz-acl"
            values   = ["bucket-owner-full-control"]
          }
        ]
      },
      {
        effect = "Allow"
        actions = [
          "s3:GetBucketAcl"
        ]
        principals = {
          identifiers = ["delivery.logs.amazonaws.com"]
          type        = "Service"
        }
      }
    ]
    iam_policies = module.baseline_presets.s3_iam_policies
  }
```

If you want to see exactly what policies are needed for each then refer to [NLB Requirements](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-access-logs.html#access-logging-bucket-requirements) and [ALB Requirements](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html#attach-bucket-policy)

## Network Loadbalancer caveats

* Access logs are created only if the load balancer has a TLS listener and they contain information only about TLS requests.
* Network loadbalancers only support SSE-S3 encryption for access logs, not aws:kms (AWS managed keys). 
* They can support customer managed keys but this is not currently supported by this module.
* No "verify bucket permissions" test file is created in the relevant bucket, only that the terraform apply step will fail with a validation error if the permissions and the bucket encryption parameters are not correct.

## Application Loadbalancer caveats

* It's worth noting that Application LB's will create a test file in the S3 bucket to verify that the bucket permissions are correct.

## Usage

```hcl

module "lb-access-logs-enabled" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-loadbalancer"

  providers = {
    # Here we use the default provider for the S3 bucket module, buck replication is disabled but we still
    # Need to pass the provider to the S3 bucket module
    aws.bucket-replication = aws
  }
  vpc_all                             = "${local.vpc_name}-${local.environment}"
  #existing_bucket_name               = "my-bucket-name"
  application_name                    = local.application_name
  public_subnets                      = [data.aws_subnet.public_az_a.id,data.aws_subnet.public_az_b.id,data.aws_subnet.public_az_c.id]
  loadbalancer_ingress_rules          = local.loadbalancer_ingress_rules
  tags                                = local.tags
  account_number                      = local.environment_management.account_ids[terraform.workspace]
  region                              = local.app_data.accounts[local.environment].region
  enable_deletion_protection          = false
  idle_timeout                        = 60
}

```
<!--- BEGIN_TF_DOCS --->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.1 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 4.0 |
| <a name="provider_template"></a> [template](#provider\_template) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_s3-bucket"></a> [s3-bucket](#module\_s3-bucket) | github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket | v6.1.1 |

## Resources

| Name | Type |
|------|------|
| [aws_athena_database.lb-access-logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/athena_database) | resource |
| [aws_athena_named_query.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/athena_named_query) | resource |
| [aws_athena_workgroup.lb-access-logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/athena_workgroup) | resource |
| [aws_lb.loadbalancer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_security_group.lb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_elb_service_account.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/elb_service_account) | data source |
| [aws_iam_policy_document.bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_vpc.shared](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |
| [template_file.lb-access-logs](https://registry.terraform.io/providers/hashicorp/template/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_number"></a> [account\_number](#input\_account\_number) | Account number of current environment | `string` | n/a | yes |
| <a name="input_application_name"></a> [application\_name](#input\_application\_name) | Name of application | `string` | n/a | yes |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | If true, deletion of the load balancer will be disabled via the AWS API. This will prevent Terraform from deleting the load balancer. | `bool` | n/a | yes |
| <a name="input_existing_bucket_name"></a> [existing\_bucket\_name](#input\_existing\_bucket\_name) | The name of the existing bucket name. If no bucket is provided one will be created for them. | `string` | `""` | no |
| <a name="input_force_destroy_bucket"></a> [force\_destroy\_bucket](#input\_force\_destroy\_bucket) | A boolean that indicates all objects (including any locked objects) should be deleted from the bucket so that the bucket can be destroyed without error. These objects are not recoverable. | `bool` | `false` | no |
| <a name="input_idle_timeout"></a> [idle\_timeout](#input\_idle\_timeout) | The time in seconds that the connection is allowed to be idle. | `string` | n/a | yes |
| <a name="input_loadbalancer_egress_rules"></a> [loadbalancer\_egress\_rules](#input\_loadbalancer\_egress\_rules) | Security group egress rules for the loadbalancer | <pre>map(object({<br>    description     = string<br>    from_port       = number<br>    to_port         = number<br>    protocol        = string<br>    security_groups = list(string)<br>    cidr_blocks     = list(string)<br>  }))</pre> | n/a | yes |
| <a name="input_loadbalancer_ingress_rules"></a> [loadbalancer\_ingress\_rules](#input\_loadbalancer\_ingress\_rules) | Security group ingress rules for the loadbalancer | <pre>map(object({<br>    description     = string<br>    from_port       = number<br>    to_port         = number<br>    protocol        = string<br>    security_groups = list(string)<br>    cidr_blocks     = list(string)<br>  }))</pre> | n/a | yes |
| <a name="input_public_subnets"></a> [public\_subnets](#input\_public\_subnets) | Public subnets | `list(string)` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS Region where resources are to be created | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags to be used by all resources | `map(string)` | n/a | yes |
| <a name="input_vpc_all"></a> [vpc\_all](#input\_vpc\_all) | The full name of the VPC (including environment) used to create resources | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_athena_db"></a> [athena\_db](#output\_athena\_db) | n/a |
| <a name="output_load_balancer"></a> [load\_balancer](#output\_load\_balancer) | n/a |
| <a name="output_security_group"></a> [security\_group](#output\_security\_group) | n/a |

<!--- END_TF_DOCS --->

## Looking for issues?
If you're looking to raise an issue with this module, please create a new issue in the [Modernisation Platform repository](https://github.com/ministryofjustice/modernisation-platform/issues).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.1 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_s3-bucket"></a> [s3-bucket](#module\_s3-bucket) | github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket | bf97d1f182936e9bfab0fb61baad2ba327ac36d3 |

## Resources

| Name | Type |
|------|------|
| [aws_athena_database.lb-access-logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/athena_database) | resource |
| [aws_athena_workgroup.lb-access-logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/athena_workgroup) | resource |
| [aws_glue_catalog_table.application_lb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_table) | resource |
| [aws_glue_catalog_table.network_lb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_table) | resource |
| [aws_iam_policy.glue_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.glue](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.glue_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.glue_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lb.loadbalancer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_security_group.lb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_elb_service_account.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/elb_service_account) | data source |
| [aws_iam_policy_document.bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.glue_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.glue_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_vpc.shared](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_logs"></a> [access\_logs](#input\_access\_logs) | A boolean that determines whether to have access logs | `bool` | `true` | no |
| <a name="input_access_logs_lifecycle_rule"></a> [access\_logs\_lifecycle\_rule](#input\_access\_logs\_lifecycle\_rule) | Custom lifecycle rule to override the default one | <pre>list(object({<br/>    id      = string<br/>    enabled = string<br/>    prefix  = string<br/>    tags    = map(string)<br/>    transition = list(object({<br/>      days          = number<br/>      storage_class = string<br/>    }))<br/>    expiration = object({<br/>      days = number<br/>    })<br/>    noncurrent_version_transition = list(object({<br/>      days          = number<br/>      storage_class = string<br/>    }))<br/>    noncurrent_version_expiration = object({<br/>      days = number<br/>    })<br/>  }))</pre> | <pre>[<br/>  {<br/>    "enabled": "Enabled",<br/>    "expiration": {<br/>      "days": 730<br/>    },<br/>    "id": "main",<br/>    "noncurrent_version_expiration": {<br/>      "days": 730<br/>    },<br/>    "noncurrent_version_transition": [<br/>      {<br/>        "days": 90,<br/>        "storage_class": "STANDARD_IA"<br/>      },<br/>      {<br/>        "days": 365,<br/>        "storage_class": "GLACIER"<br/>      }<br/>    ],<br/>    "prefix": "",<br/>    "tags": {<br/>      "autoclean": "true",<br/>      "rule": "log"<br/>    },<br/>    "transition": [<br/>      {<br/>        "days": 90,<br/>        "storage_class": "STANDARD_IA"<br/>      },<br/>      {<br/>        "days": 365,<br/>        "storage_class": "GLACIER"<br/>      }<br/>    ]<br/>  }<br/>]</pre> | no |
| <a name="input_account_number"></a> [account\_number](#input\_account\_number) | Account number of current environment | `string` | n/a | yes |
| <a name="input_application_name"></a> [application\_name](#input\_application\_name) | Name of application | `string` | n/a | yes |
| <a name="input_dns_record_client_routing_policy"></a> [dns\_record\_client\_routing\_policy](#input\_dns\_record\_client\_routing\_policy) | (optional) Indicates how traffic is distributed among network load balancer Availability Zones only. Possible values are any\_availability\_zone (client DNS queries are resolved among healthy LB IP addresses across all LB Availability Zones), partial\_availability\_zone\_affinity (85 percent of client DNS queries will favor load balancer IP addresses in their own Availability Zone, while the remaining queries resolve to any healthy zone) and availability\_zone\_affinity (Client DNS queries will favor load balancer IP address in their own Availability Zone). | `string` | `"any_availability_zone"` | no |
| <a name="input_drop_invalid_header_fields"></a> [drop\_invalid\_header\_fields](#input\_drop\_invalid\_header\_fields) | Whether HTTP headers with header fields that are not valid are removed by the load balancer (true) or routed to targets (false). | `bool` | `true` | no |
| <a name="input_enable_cross_zone_load_balancing"></a> [enable\_cross\_zone\_load\_balancing](#input\_enable\_cross\_zone\_load\_balancing) | A boolean that determines whether cross zone load balancing is enabled. In application load balancers this feature is always enabled and cannot be disabled. In network and gateway load balancers this feature is disabled by default but can be enabled. | `bool` | `false` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | If true, deletion of the load balancer will be disabled via the AWS API. This will prevent Terraform from deleting the load balancer. | `bool` | n/a | yes |
| <a name="input_existing_bucket_name"></a> [existing\_bucket\_name](#input\_existing\_bucket\_name) | The name of the existing bucket name. If no bucket is provided one will be created for them. | `string` | `""` | no |
| <a name="input_force_destroy_bucket"></a> [force\_destroy\_bucket](#input\_force\_destroy\_bucket) | A boolean that indicates all objects (including any locked objects) should be deleted from the bucket so that the bucket can be destroyed without error. These objects are not recoverable. | `bool` | `false` | no |
| <a name="input_idle_timeout"></a> [idle\_timeout](#input\_idle\_timeout) | The time in seconds that the connection is allowed to be idle. | `string` | `null` | no |
| <a name="input_internal_lb"></a> [internal\_lb](#input\_internal\_lb) | A boolean that determines whether the load balancer is internal or internet-facing. | `bool` | `false` | no |
| <a name="input_lb_target_groups"></a> [lb\_target\_groups](#input\_lb\_target\_groups) | Map of load balancer target groups, where key is the name | <pre>map(object({<br/>    port                 = optional(number)<br/>    attachment_port      = optional(number)<br/>    deregistration_delay = optional(number)<br/>    health_check = optional(object({<br/>      enabled             = optional(bool)<br/>      interval            = optional(number)<br/>      healthy_threshold   = optional(number)<br/>      matcher             = optional(string)<br/>      path                = optional(string)<br/>      port                = optional(number)<br/>      timeout             = optional(number)<br/>      unhealthy_threshold = optional(number)<br/>    }))<br/>    stickiness = optional(object({<br/>      enabled         = optional(bool)<br/>      type            = string<br/>      cookie_duration = optional(number)<br/>      cookie_name     = optional(string)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_load_balancer_type"></a> [load\_balancer\_type](#input\_load\_balancer\_type) | application or network | `string` | `"application"` | no |
| <a name="input_loadbalancer_egress_rules"></a> [loadbalancer\_egress\_rules](#input\_loadbalancer\_egress\_rules) | Create new security group with these egress rules for the loadbalancer.  Or use the security\_groups var to attach existing group(s) | <pre>map(object({<br/>    description     = string<br/>    from_port       = number<br/>    to_port         = number<br/>    protocol        = string<br/>    security_groups = list(string)<br/>    cidr_blocks     = list(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_loadbalancer_ingress_rules"></a> [loadbalancer\_ingress\_rules](#input\_loadbalancer\_ingress\_rules) | Create new security group with these ingress rules for the loadbalancer.  Or use the security\_groups var to attach existing group(s) | <pre>map(object({<br/>    description     = string<br/>    from_port       = number<br/>    to_port         = number<br/>    protocol        = string<br/>    security_groups = list(string)<br/>    cidr_blocks     = list(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_public_subnets"></a> [public\_subnets](#input\_public\_subnets) | Badly named variable, use subnets instead. Keeping for backward compatibility | `list(string)` | `[]` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS Region where resources are to be created | `string` | n/a | yes |
| <a name="input_s3_notification_queues"></a> [s3\_notification\_queues](#input\_s3\_notification\_queues) | a map of bucket notification queues where the map key is used as the configuration id | <pre>map(object({<br/>    events        = list(string)     # e.g. ["s3:ObjectCreated:*"]<br/>    filter_prefix = optional(string) # e.g. "images/"<br/>    filter_suffix = optional(string) # e.g. ".gz"<br/>    queue_arn     = string<br/>  }))</pre> | `{}` | no |
| <a name="input_s3_versioning"></a> [s3\_versioning](#input\_s3\_versioning) | A boolean that determines whether s3 will have versioning | `bool` | `true` | no |
| <a name="input_security_groups"></a> [security\_groups](#input\_security\_groups) | List of existing security group ids to attach to the load balancer.  You can use this instead of loadbalancer\_ingress\_rules,loadbalancer\_egress\_rules vars | `list(string)` | `null` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | List of subnet IDs. Typically use private subnet for internal LBs and public for public LBs | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags to be used by all resources | `map(string)` | n/a | yes |
| <a name="input_vpc_all"></a> [vpc\_all](#input\_vpc\_all) | The full name of the VPC (including environment) used to create resources | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_athena_db"></a> [athena\_db](#output\_athena\_db) | n/a |
| <a name="output_lb_target_groups"></a> [lb\_target\_groups](#output\_lb\_target\_groups) | n/a |
| <a name="output_load_balancer"></a> [load\_balancer](#output\_load\_balancer) | n/a |
| <a name="output_load_balancer_arn"></a> [load\_balancer\_arn](#output\_load\_balancer\_arn) | n/a |
| <a name="output_load_balancer_dns_name"></a> [load\_balancer\_dns\_name](#output\_load\_balancer\_dns\_name) | n/a |
| <a name="output_load_balancer_zone_id"></a> [load\_balancer\_zone\_id](#output\_load\_balancer\_zone\_id) | n/a |
| <a name="output_s3_bucket"></a> [s3\_bucket](#output\_s3\_bucket) | n/a |
| <a name="output_security_group"></a> [security\_group](#output\_security\_group) | n/a |
<!-- END_TF_DOCS -->

[Standards Link]: https://github-community.service.justice.gov.uk/repository-standards/modernisation-platform-terraform-loadbalancer "Repo standards badge."
[Standards Icon]: https://github-community.service.justice.gov.uk/repository-standards/api/modernisation-platform-terraform-loadbalancer/badge
[Format Code Icon]: https://img.shields.io/github/actions/workflow/status/ministryofjustice/modernisation-platform-terraform-loadbalancer/format-code.yml?labelColor=231f20&style=for-the-badge&label=Formate%20Code
[Format Code Link]: https://github.com/ministryofjustice/modernisation-platform-terraform-loadbalancer/actions/workflows/format-code.yml
[Scorecards Icon]: https://img.shields.io/github/actions/workflow/status/ministryofjustice/modernisation-platform-terraform-loadbalancer/scorecards.yml?branch=main&labelColor=231f20&style=for-the-badge&label=Scorecards
[Scorecards Link]: https://github.com/ministryofjustice/modernisation-platform-terraform-loadbalancer/actions/workflows/scorecards.yml
[SCA Icon]: https://img.shields.io/github/actions/workflow/status/ministryofjustice/modernisation-platform-terraform-loadbalancer/code-scanning.yml?branch=main&labelColor=231f20&style=for-the-badge&label=Secure%20Code%20Analysis
[SCA Link]: https://github.com/ministryofjustice/modernisation-platform-terraform-loadbalancer/actions/workflows/code-scanning.yml
[Terraform SCA Icon]: https://img.shields.io/github/actions/workflow/status/ministryofjustice/modernisation-platform-terraform-loadbalancer/code-scanning.yml?branch=main&labelColor=231f20&style=for-the-badge&label=Terraform%20Static%20Code%20Analysis
[Terraform SCA Link]: https://github.com/ministryofjustice/modernisation-platform-terraform-loadbalancer/actions/workflows/terraform-static-analysis.yml
