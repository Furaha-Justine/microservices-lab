output "eks_cluster_name" {
  description = "EKS cluster name — set this as EKS_CLUSTER in Jenkins"
  value       = module.eks.eks_cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.eks_cluster_endpoint
}

output "rds_endpoint" {
  description = "RDS hostname — used to build DATABASE_URL"
  value       = module.eks.rds_endpoint
}

output "elasticache_address" {
  description = "ElastiCache primary endpoint — used to build REDIS_URL"
  value       = module.eks.elasticache_address
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller — used in Helm install"
  value       = module.eks.alb_controller_role_arn
}

output "ecr_frontend_url" {
  value = module.ecr.repository_urls["frontend"]
}

output "ecr_backend_url" {
  value = module.ecr.repository_urls["backend"]
}

output "jenkins_access_key_id" {
  value = module.iam.jenkins_access_key_id
}

output "jenkins_secret_access_key" {
  value     = module.iam.jenkins_secret_access_key
  sensitive = true
}
