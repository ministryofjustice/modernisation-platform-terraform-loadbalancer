# Modernisation Platform Terraform Loadbalancer Module with Access Logs enabled
[![repo standards badge](https://img.shields.io/badge/dynamic/json?color=blue&style=for-the-badge&logo=github&label=MoJ%20Compliant&query=%24.data%5B%3F%28%40.name%20%3D%3D%20%22modernisation-platform-terraform-s3-bucket%22%29%5D.status&url=https%3A%2F%2Foperations-engineering-reports.cloud-platform.service.justice.gov.uk%2Fgithub_repositories)](https://operations-engineering-reports.cloud-platform.service.justice.gov.uk/github_repositories#modernisation-platform-terraform-s3-bucket "Link to report")

A Terraform module that creates application loadbalancer (with loadbalancer security groups) in AWS with logging enabled, s3 to store logs and Athena DB to query logs.

A locals for the loadbalancer security group is necessary to satisfy the `loadbalancer_ingress_rules` variable and also creates specific security group rules for the loadbalancer security group. Below is an example:

```
locals {
  loadbalancer_ingress_rules = {
    "cluster_ec2_lb_ingress" = {
      description     = "Cluster EC2 loadbalancer ingress rule"
      from_port       = 8080
      to_port         = 8080
      protocol        = "tcp"
      cidr_blocks     = [0.0.0.0/0]
      security_groups = []
    },
    "cluster_ec2_bastion_ingress" = {
      description     = "Cluster EC2 bastion ingress rule"
      from_port       = 3389
      to_port         = 3389
      protocol        = "tcp"
      cidr_blocks     = []
      security_groups = [module.bastion_linux.bastion_security_group]
    }
  }
}
```

Loadbalancer target groups and listeners need to be created separately.

To run queries in Athena do the following:
Go to the Athena console and click on Saved Queries https://console.aws.amazon.com/athena/saved-queries/home

Click the new saved query that is named `<custom_name>`-create-table and Run it. You only have to do it once.

Try a query like `select * from lb_logs limit 100;`


## Usage

```hcl

module "lb-access-logs-enabled" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-loadbalancer"

  vpc_all                             = "${local.vpc_name}-${local.environment}"
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
| <a name="module_s3-bucket"></a> [s3-bucket](#module\_s3-bucket) | github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket | v6.0.3 |

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
| <a name="input_idle_timeout"></a> [idle\_timeout](#input\_idle\_timeout) | The time in seconds that the connection is allowed to be idle. | `string` | n/a | yes |
| <a name="input_loadbalancer_ingress_rules"></a> [loadbalancer\_ingress\_rules](#input\_loadbalancer\_ingress\_rules) | Security group ingress rules for the loadbalancer | <pre>map(object({<br>    description     = string<br>    from_port       = number<br>    to_port         = number<br>    protocol        = string<br>    security_groups = list(string)<br>    cidr_blocks     = list(string)<br>  }))</pre> | n/a | yes |
| <a name="input_public_subnets"></a> [public\_subnets](#input\_public\_subnets) | Public subnets | `list(string)` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS Region where resources are to be created | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags to be used by all resources | `map(string)` | n/a | yes |
| <a name="input_vpc_all"></a> [vpc\_all](#input\_vpc\_all) | The full name of the VPC (including environment) used to create resources | `string` | n/a | yes |

## Outputs

No outputs.

<!--- END_TF_DOCS --->

## Looking for issues?
If you're looking to raise an issue with this module, please create a new issue in the [Modernisation Platform repository](https://github.com/ministryofjustice/modernisation-platform/issues).
