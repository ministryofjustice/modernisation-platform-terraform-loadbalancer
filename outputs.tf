output "athena_db" {
  value = aws_athena_database.lb-access-logs
}

output "security_group" {
  value = len(aws_security_group.lb) > 0 ? aws_security_group.lb[0] : null
}

output "load_balancer" {
  value = aws_lb.loadbalancer
}
