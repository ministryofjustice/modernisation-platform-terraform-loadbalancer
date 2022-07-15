package main

import (
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"regexp"
	"testing"
)

func TestLBCreation(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./unit-test",
	})

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	athenaDbName := terraform.Output(t, terraformOptions, "athena_db_name")
	assert.Equal(t, "loadbalancer_access_logs", athenaDbName)
	securityGroupArn := terraform.Output(t, terraformOptions, "security_group_arn")
	assert.Regexp(t, regexp.MustCompile(`^arn:aws:ec2:eu-west-2:[0-9]{12}:security-group\/sg-*`), securityGroupArn)
	loadbalancerArn := terraform.Output(t, terraformOptions, "load_balancer_arn")
	assert.Regexp(t, regexp.MustCompile(`^arn:aws:elasticloadbalancing:eu-west-2:[0-9]{12}:loadbalancer\/app\/testing-lb\/*`), loadbalancerArn)
}
