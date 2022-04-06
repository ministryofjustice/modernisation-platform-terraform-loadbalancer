variable "bucket_prefix" {
  type        = string
  description = "Prefix for s3 bucket that will store access logs"
}
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
  type        = string
  description = "Public subnets"
}
variable "loadbalancer_ingress_rules" {
  description = "Security group ingress rules for the loadbalancer"
  type = map(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    security_groups = list(string)
    cidr_blocks     = list(string)
  }))
}
variable "vpc_all" {
  type        = string
  description = "The full name of the VPC (including environment) used to create resources"
}
