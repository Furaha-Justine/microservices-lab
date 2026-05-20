output "cluster_id" { value = aws_ecs_cluster.main.id }
output "cluster_name" { value = aws_ecs_cluster.main.name }

output "alb_dns_name" { value = aws_lb.main.dns_name }
output "alb_arn" { value = aws_lb.main.arn }

output "frontend_service_name" { value = aws_ecs_service.frontend.name }
output "backend_service_name" { value = aws_ecs_service.backend.name }

output "service_discovery_ns" { value = aws_service_discovery_private_dns_namespace.main.name }

# Passed to the IAM module so Jenkins can iam:PassRole when registering task defs
output "task_execution_role_arn" { value = aws_iam_role.task_execution.arn }
output "task_role_arn" { value = aws_iam_role.task.arn }

output "frontend_sg_id" { value = aws_security_group.frontend.id }
output "backend_sg_id" { value = aws_security_group.backend.id }

# ── Managed data services ─────────────────────────────────────
output "rds_address" {
  description = "RDS PostgreSQL hostname (without port)"
  value       = aws_db_instance.main.address
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "rds_sg_id" { value = aws_security_group.rds.id }

output "elasticache_address" {
  description = "ElastiCache Redis primary hostname (without port)"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "elasticache_sg_id" { value = aws_security_group.elasticache.id }
