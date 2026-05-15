output "endpoint"       { value = aws_db_instance.main.address; sensitive = true }
output "port"           { value = aws_db_instance.main.port }
output "db_name"        { value = aws_db_instance.main.db_name }
output "security_group_id" { value = aws_security_group.rds.id }
output "instance_id"    { value = aws_db_instance.main.identifier }
output "connection_url" {
  value     = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.main.address}:5432/${var.db_name}"
  sensitive = true
}
