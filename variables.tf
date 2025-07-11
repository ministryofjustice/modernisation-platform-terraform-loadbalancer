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
  description = "Badly named variable, use subnets instead. Keeping for backward compatibility"
  default     = []
}
variable "subnets" {
  type        = list(string)
  description = "List of subnet IDs. Typically use private subnet for internal LBs and public for public LBs"
  default     = []
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
  default     = null
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
variable "load_balancer_type" {
  type        = string
  description = "application or network"
  default     = "application"
}
variable "access_logs" {
  type        = bool
  description = "A boolean that determines whether to have access logs"
  default     = true
}
variable "s3_versioning" {
  type        = bool
  description = "A boolean that determines whether s3 will have versioning"
  default     = true
}
variable "s3_notification_queues" {
  type = map(object({
    events        = list(string)     # e.g. ["s3:ObjectCreated:*"]
    filter_prefix = optional(string) # e.g. "images/"
    filter_suffix = optional(string) # e.g. ".gz"
    queue_arn     = string
  }))
  description = "a map of bucket notification queues where the map key is used as the configuration id"
  default     = {}
}
variable "lb_target_groups" {
  description = "Map of load balancer target groups, where key is the name"
  type = map(object({
    port                 = optional(number)
    attachment_port      = optional(number)
    deregistration_delay = optional(number)
    health_check = optional(object({
      enabled             = optional(bool)
      interval            = optional(number)
      healthy_threshold   = optional(number)
      matcher             = optional(string)
      path                = optional(string)
      port                = optional(number)
      timeout             = optional(number)
      unhealthy_threshold = optional(number)
    }))
    stickiness = optional(object({
      enabled         = optional(bool)
      type            = string
      cookie_duration = optional(number)
      cookie_name     = optional(string)
    }))
  }))
  default = {}
}

variable "enable_cross_zone_load_balancing" {
  type        = bool
  description = "A boolean that determines whether cross zone load balancing is enabled. In application load balancers this feature is always enabled and cannot be disabled. In network and gateway load balancers this feature is disabled by default but can be enabled."
  default     = false
}

variable "dns_record_client_routing_policy" {
  type        = string
  description = "(optional) Indicates how traffic is distributed among network load balancer Availability Zones only. Possible values are any_availability_zone (client DNS queries are resolved among healthy LB IP addresses across all LB Availability Zones), partial_availability_zone_affinity (85 percent of client DNS queries will favor load balancer IP addresses in their own Availability Zone, while the remaining queries resolve to any healthy zone) and availability_zone_affinity (Client DNS queries will favor load balancer IP address in their own Availability Zone)."
  default     = "any_availability_zone"
}

variable "access_logs_lifecycle_rule" {
  description = "Custom lifecycle rule to override the default one"
  type = list(object({
    id      = string
    enabled = string
    prefix  = string
    tags    = map(string)
    transition = list(object({
      days          = number
      storage_class = string
    }))
    expiration = object({
      days = number
    })
    noncurrent_version_transition = list(object({
      days          = number
      storage_class = string
    }))
    noncurrent_version_expiration = object({
      days = number
    })
  }))
  default = [
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
        },
        {
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
        },
        {
          days          = 365
          storage_class = "GLACIER"
        }
      ]

      noncurrent_version_expiration = {
        days = 730
      }
    }
  ]
}

# set to false for SAP BIP, see https://me.sap.com/notes/0003348935
variable "drop_invalid_header_fields" {
  description = "Whether HTTP headers with header fields that are not valid are removed by the load balancer (true) or routed to targets (false)."
  default     = true
}
