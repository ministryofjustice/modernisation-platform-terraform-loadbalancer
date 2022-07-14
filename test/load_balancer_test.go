package main

import (
	"fmt"
	"testing"

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
	assert.Equal(t, "loadbalancer_access_logs", athena_db_name)
	security_group := terraform.Output(t, terraformOptions, "security_group")
	fmt.Println("***SECURITY GROUP***", security_group)
	output_security_group := terraform.Output(t, terraformOptions, "output_security_group")
	assert.Equal(t, output_security_group, security_group)
}
