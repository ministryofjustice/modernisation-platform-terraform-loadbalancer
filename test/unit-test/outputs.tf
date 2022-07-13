# output "VPC" {
#   value = module.lb_access_logs_enabled.vpc_all
# description = "VPC being used"
# }
output "athena_db_name" {
  value = module.lb_access_logs_enabled.athena_db_name
}