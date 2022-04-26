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

To run queries in Athen do the following:
Go to the Athena console and click on Saved Queries https://console.aws.amazon.com/athena/saved-queries/home
Click the new saved query that is named <custom_name>-create-table and Run it. You only have to do it once.

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

<!--- END_TF_DOCS --->

## Looking for issues?
If you're looking to raise an issue with this module, please create a new issue in the [Modernisation Platform repository](https://github.com/ministryofjustice/modernisation-platform/issues).
