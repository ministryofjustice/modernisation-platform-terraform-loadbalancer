output "athena_db" {
  value = var.access_logs ? aws_athena_database.lb-access-logs[0] : null
}

output "security_group" {
  value = length(aws_security_group.lb) > 0 ? aws_security_group.lb[0] : null
}

output "load_balancer" {
  value = aws_lb.loadbalancer
}

output "load_balancer_arn" {
  value = aws_lb.loadbalancer.arn
}

output "lb_target_groups" {
  value = aws_lb_target_group.this
}

output "load_balancer_dns_name" {
  value = aws_lb.loadbalancer.dns_name
}

output "load_balancer_zone_id" {
  value = aws_lb.loadbalancer.zone_id

}