output "primary_endpoint"  { value = aws_elasticache_replication_group.main.primary_endpoint_address; sensitive = true }
output "port"              { value = aws_elasticache_replication_group.main.port }
output "security_group_id" { value = aws_security_group.redis.id }
output "redis_url"         { value = "rediss://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379/0"; sensitive = true }
