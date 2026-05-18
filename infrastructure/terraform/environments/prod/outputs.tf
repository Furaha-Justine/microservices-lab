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
# Use these in your Jenkins pipeline: docker build + docker push
output "ecr_frontend_url" { value = module.ecr.repository_urls["frontend"] }
output "ecr_backend_url" { value = module.ecr.repository_urls["backend"] }

# ── Service discovery ──────────────────────────────────────────
output "service_discovery_namespace" {
  description = "Private DNS namespace — services reach each other via <name>.<namespace>"
  value       = module.ecs.service_discovery_ns
}

# ── Jenkins credentials ────────────────────────────────────────
# Run: terraform output jenkins_access_key_id
# Run: terraform output -raw jenkins_secret_access_key
output "jenkins_access_key_id" {
  description = "Add to Jenkins as AWS_ACCESS_KEY_ID credential"
  value       = module.iam.jenkins_access_key_id
}

output "jenkins_secret_access_key" {
  description = "Add to Jenkins as AWS_SECRET_ACCESS_KEY credential"
  value       = module.iam.jenkins_secret_access_key
  sensitive   = true
}
