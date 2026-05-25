variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "vpc_id" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 10
}

variable "postgres_password" {
  type      = string
  sensitive = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_engine_version" {
  type    = string
  default = "16.6"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "elasticache_node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "elasticache_num_replicas" {
  type    = number
  default = 0
}

variable "jenkins_user_arn" {
  description = "ARN of the Jenkins IAM user (from the iam module output)"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
