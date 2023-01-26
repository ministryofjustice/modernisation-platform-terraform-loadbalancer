variable "account_number" {
  type        = string
  description = "Account number of current environment"
}
variable "tags" {
  type        = map(string)
  description = "Common tags to be used by all resources"
}
variable "application_name" {
  type        = string
  description = "Name of application"
}
variable "public_subnets" {
  type        = list(string)
  description = "Public subnets"
}
variable "loadbalancer_ingress_rules" {
  description = "Create new security group with these ingress rules for the loadbalancer.  Or use the security_groups var to attach existing group(s)"
  type = map(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    security_groups = list(string)
    cidr_blocks     = list(string)
  }))
  default = {}
}

variable "loadbalancer_egress_rules" {
  description = "Create new security group with these egress rules for the loadbalancer.  Or use the security_groups var to attach existing group(s)"
  type = map(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    security_groups = list(string)
    cidr_blocks     = list(string)
  }))
  default = {}
}
variable "security_groups" {
  description = "List of existing security group ids to attach to the load balancer.  You can use this instead of loadbalancer_ingress_rules,loadbalancer_egress_rules vars"
  type        = list(string)
  default     = null
}
variable "vpc_all" {
  type        = string
  description = "The full name of the VPC (including environment) used to create resources"
}
variable "enable_deletion_protection" {
  type        = bool
  description = "If true, deletion of the load balancer will be disabled via the AWS API. This will prevent Terraform from deleting the load balancer."
}
variable "region" {
  type        = string
  description = "AWS Region where resources are to be created"
}
variable "idle_timeout" {
  type        = string
  description = "The time in seconds that the connection is allowed to be idle."
}
variable "existing_bucket_name" {
  type        = string
  default     = ""
  description = "The name of the existing bucket name. If no bucket is provided one will be created for them."
}
variable "force_destroy_bucket" {
  type        = bool
  description = "A boolean that indicates all objects (including any locked objects) should be deleted from the bucket so that the bucket can be destroyed without error. These objects are not recoverable."
  default     = false
}
variable "internal_lb" {
  type        = bool
  description = "A boolean that determines whether the load balancer is internal or internet-facing."
  default     = false
}
