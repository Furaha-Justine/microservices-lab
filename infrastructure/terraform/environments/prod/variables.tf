variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "project" {
  type    = string
  default = "shopnow"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "postgres_password" {
  description = "Master password for the RDS PostgreSQL instance"
  type        = string
  sensitive   = true
}

# ── RDS PostgreSQL ─────────────────────────────────────────────
variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.small"
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
  description = "Days to retain automated RDS backups"
  type        = number
  default     = 7
}

variable "multi_az" {
  description = "Enable Multi-AZ standby for RDS"
  type        = bool
  default     = true
}

# ── ElastiCache Redis ──────────────────────────────────────────
variable "elasticache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.small"
}

variable "elasticache_num_replicas" {
  description = "Number of Redis read replicas (0 = no failover)"
  type        = number
  default     = 1
}

# ── Bastion ────────────────────────────────────────────────────
variable "bastion_key_name" {
  description = "EC2 key pair name for SSH access to bastion (create in AWS Console → EC2 → Key Pairs)"
  type        = string
}

variable "bastion_allowed_cidr" {
  description = "Your laptop IP in CIDR notation (e.g. 102.176.1.1/32). Restricts SSH access to bastion."
  type        = string
  default     = "0.0.0.0/0"
}
