output "athena_db_name" {
  value = module.lb_access_logs_enabled.athena_db.name
}

output "security_group_arn" {
  value = module.lb_access_logs_enabled.security_group.arn
}

output "load_balancer_arn" {
  value = module.lb_access_logs_enabled.load_balancer.arn
}
