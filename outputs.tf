output "athena_db_name" {
  value = aws_athena_database.lb-access-logs.id
}
output "security_group" {
    value = aws_security_group.lb.id
}
output "output_security_group" {
  value = aws_security_group.lb.id
}