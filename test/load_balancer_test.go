package main

import (
	"testing"
	"fmt"

	// "github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// "regexp" ^
func TestLBCreation(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./unit-test",
	})

	defer terraform.Destroy(t, terraformOptions)
	// awsRegion := "eu-west-2"
	terraform.InitAndApply(t, terraformOptions)

	// Run `terraform output` to get the value of an output variable
	// subnet := terraform.Output(t, terraformOptions, "subnet")
	athena_db_name := terraform.Output(t, terraformOptions, "athena_db_name")
	fmt.Println("athena_db_name", athena_db_name)
	assert.Equal(t,"loadbalancer_access_logs", athena_db_name,"PASS")
	// assert.Regexp(t, regexp.MustCompile(`^arn:aws:s3:::s3-bucket-*`), bucketArn)
	// aws.IsPublicSubnet(t, subnet, awsRegion)

	// assert.Equal(t, expectedStatus, actualStatus)

	// Verify that our Bucket has versioning enabled
	// actualStatus := aws.GetS3BucketVersioning(t, awsRegion, bucketID)
	// expectedStatus := "Enabled"
	// assert.Equal(t, expectedStatus, actualStatus)
}
