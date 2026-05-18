output "cluster_id" { value = aws_ecs_cluster.main.id }
output "cluster_name" { value = aws_ecs_cluster.main.name }

output "alb_dns_name" { value = aws_lb.main.dns_name }
output "alb_arn" { value = aws_lb.main.arn }

output "frontend_service_name" { value = aws_ecs_service.frontend.name }
output "backend_service_name" { value = aws_ecs_service.backend.name }
output "postgres_service_name" { value = aws_ecs_service.postgres.name }
output "redis_service_name" { value = aws_ecs_service.redis.name }

output "service_discovery_ns" { value = aws_service_discovery_private_dns_namespace.main.name }

# Passed to the IAM module so Jenkins can iam:PassRole when registering task defs
output "task_execution_role_arn" { value = aws_iam_role.task_execution.arn }
output "task_role_arn" { value = aws_iam_role.task.arn }

output "frontend_sg_id" { value = aws_security_group.frontend.id }
output "backend_sg_id" { value = aws_security_group.backend.id }
output "postgres_sg_id" { value = aws_security_group.postgres.id }
output "redis_sg_id" { value = aws_security_group.redis.id }
