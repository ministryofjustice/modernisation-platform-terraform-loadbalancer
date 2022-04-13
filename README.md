## Usage

```hcl

module "lb-with-access-logs-enabled" {

  source = "github.com/ministryofjustice/modernisation-platform-terraform-loadbalancer"

  bucket_prefix    = local.application_data.accounts[local.environment].bucket_prefix
  tags             = local.tags
  application_name = local.application_name

}

Go to the Athena console and click on Saved Queries https://console.aws.amazon.com/athena/saved-queries/home
Click the new saved query that is named <custom_name>-create-table and Run it. You only have to do it once.
That's all, try a query select * from lb_logs limit 100;

```
<!--- BEGIN_TF_DOCS --->

<!--- END_TF_DOCS --->

## Looking for issues?
If you're looking to raise an issue with this module, please create a new issue in the [Modernisation Platform repository](https://github.com/ministryofjustice/modernisation-platform/issues).
