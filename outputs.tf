output "athena_db_name" {
  value = aws_athena_database.lb-access-logs.id
}