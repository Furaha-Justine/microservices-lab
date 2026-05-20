# ── App access ────────────────────────────────────────────────
output "app_url" {
  description = "Public URL of the ShopNow storefront"
  value       = "http://${module.ecs.alb_dns_name}"
}

output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}

# ── Infrastructure ─────────────────────────────────────────────
output "vpc_id" { value = module.vpc.vpc_id }
output "ecs_cluster_name" { value = module.ecs.cluster_name }

# ── ECR image URLs ─────────────────────────────────────────────
output "ecr_frontend_url" { value = module.ecr.repository_urls["frontend"] }
output "ecr_backend_url" { value = module.ecr.repository_urls["backend"] }

# ── Service Connect namespace ──────────────────────────────────
output "service_discovery_namespace" {
  description = "Private DNS namespace — backend reachable at backend.<namespace>:5000"
  value       = module.ecs.service_discovery_ns
}

# ── Managed data services ──────────────────────────────────────
output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port) — for reference only, not exposed publicly"
  value       = module.ecs.rds_endpoint
}

output "elasticache_address" {
  description = "ElastiCache Redis primary hostname — for reference only, not exposed publicly"
  value       = module.ecs.elasticache_address
}

# ── Bastion ───────────────────────────────────────────────────
output "bastion_ip" {
  description = "SSH: ssh -L 5432:<rds_endpoint>:5432 ec2-user@<bastion_ip> -i ~/.ssh/<key>.pem"
  value       = module.bastion.public_ip
}

# ── Jenkins credentials ────────────────────────────────────────
output "jenkins_access_key_id" {
  description = "Add to Jenkins as AWS_ACCESS_KEY_ID credential"
  value       = module.iam.jenkins_access_key_id
}

output "jenkins_secret_access_key" {
  description = "Add to Jenkins as AWS_SECRET_ACCESS_KEY credential"
  value       = module.iam.jenkins_secret_access_key
  sensitive   = true
}
