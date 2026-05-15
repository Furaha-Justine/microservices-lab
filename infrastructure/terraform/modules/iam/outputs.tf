output "jenkins_user_arn" {
  description = "ARN of the Jenkins IAM user"
  value       = aws_iam_user.jenkins.arn
}

output "jenkins_access_key_id" {
  description = "Set this as AWS_ACCESS_KEY_ID in Jenkins → Manage Credentials"
  value       = aws_iam_access_key.jenkins.id
}

output "jenkins_secret_access_key" {
  description = "Set this as AWS_SECRET_ACCESS_KEY in Jenkins → Manage Credentials"
  value       = aws_iam_access_key.jenkins.secret
  sensitive   = true
}
