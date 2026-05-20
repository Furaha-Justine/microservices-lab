variable "project" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "frontend_image" {
  description = "Full ECR image URI for the frontend"
  type        = string
}

variable "backend_image" {
  description = "Full ECR image URI for the backend"
  type        = string
}

variable "postgres_password" {
  description = "Password for the RDS PostgreSQL master user"
  type        = string
  sensitive   = true
}

# ── RDS PostgreSQL ─────────────────────────────────────────────
variable "db_instance_class" {
  description = "RDS instance type (e.g. db.t3.micro, db.t3.small)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.6"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 20
}

variable "db_backup_retention_days" {
  description = "Number of days to retain automated RDS backups (0 disables backups)"
  type        = number
  default     = 7
}

variable "multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = false
}

# ── ElastiCache Redis ──────────────────────────────────────────
variable "elasticache_node_type" {
  description = "ElastiCache node type (e.g. cache.t3.micro, cache.t3.small)"
  type        = string
  default     = "cache.t3.micro"
}

variable "elasticache_num_replicas" {
  description = "Number of read replicas per Redis shard (0 = primary only, no failover)"
  type        = number
  default     = 0
}

# ── ECS Task sizing ────────────────────────────────────────────
variable "frontend_cpu" {
  type    = number
  default = 256
}

variable "frontend_memory" {
  type    = number
  default = 512
}

variable "frontend_desired_count" {
  type    = number
  default = 2
}

variable "backend_cpu" {
  type    = number
  default = 512
}

variable "backend_memory" {
  type    = number
  default = 1024
}

variable "backend_desired_count" {
  type    = number
  default = 2
}

variable "tags" {
  type    = map(string)
  default = {}
}
