variable "aws_region" {
  description = "AWS region for the bootstrap resources"
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name used for tags"
  type        = string
  default     = "shopnow"
}

variable "state_bucket_name" {
  description = "S3 bucket used for Terraform remote state"
  type        = string
  default     = "shopnow-terraform-state-445567114084"
}

variable "lock_table_name" {
  description = "DynamoDB table used for Terraform state locking"
  type        = string
  default     = "shopnow-terraform-locks"
}
