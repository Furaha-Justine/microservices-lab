output "repository_urls" {
  description = "Map of repository name → URL  (e.g. repository_urls[\"frontend\"])"
  value       = { for k, v in aws_ecr_repository.repos : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of repository name → ARN"
  value       = { for k, v in aws_ecr_repository.repos : k => v.arn }
}

output "registry_id" {
  description = "AWS account ID of the ECR registry"
  value       = length(aws_ecr_repository.repos) > 0 ? values(aws_ecr_repository.repos)[0].registry_id : ""
}
