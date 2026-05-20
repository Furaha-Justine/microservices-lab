# ─────────────────────────────────────────────────────────────
# ShopNow — Production Environment
# ECS Fargate (frontend + backend) + RDS PostgreSQL + ElastiCache Redis
#
# Modules used:
#   vpc  → VPC, public/private subnets, NAT, IGW
#   ecr  → ECR repos for frontend and backend
#   ecs  → 1 cluster, 2 task defs, 2 ECS services, ALB, RDS, ElastiCache
#   iam  → Jenkins CI/CD IAM user + access keys
# ─────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Create this S3 bucket and DynamoDB table before first terraform init
  backend "s3" {
    bucket         = "shopnow-terraform-state-445567114084"
    key            = "prod/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "shopnow-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags { tags = local.common_tags }
}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

data "aws_availability_zones" "available" { state = "available" }

# ── VPC ───────────────────────────────────────────────────────
# 2 AZs · public subnets (ALB, NAT) · private subnets (ECS, RDS, ElastiCache)
module "vpc" {
  source = "../../modules/vpc"

  project            = var.project
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  tags               = local.common_tags
}

# ── ECR ───────────────────────────────────────────────────────
# Repos for frontend and backend only. RDS and ElastiCache are managed services.
module "ecr" {
  source = "../../modules/ecr"

  project          = var.project
  repository_names = ["frontend", "backend"]
  tags             = local.common_tags
}

# ── ECS Fargate + RDS + ElastiCache ───────────────────────────
# 1 cluster · 2 ECS services (frontend, backend)
# RDS PostgreSQL for the primary datastore
# ElastiCache Redis for caching
# Request flow:
#   ALB → frontend (3000) --Service Connect--> backend (5000) → RDS (5432)
#                                                             → ElastiCache (6379)
module "ecs" {
  source = "../../modules/ecs"

  project            = var.project
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  frontend_image = "${module.ecr.repository_urls["frontend"]}:latest"
  backend_image  = "${module.ecr.repository_urls["backend"]}:latest"

  postgres_password = var.postgres_password

  # RDS PostgreSQL
  db_instance_class        = var.db_instance_class
  db_engine_version        = var.db_engine_version
  db_allocated_storage     = var.db_allocated_storage
  db_backup_retention_days = var.db_backup_retention_days
  multi_az                 = var.multi_az

  # ElastiCache Redis
  elasticache_node_type    = var.elasticache_node_type
  elasticache_num_replicas = var.elasticache_num_replicas

  tags = local.common_tags
}

# ── Bastion Host ──────────────────────────────────────────────
# SSH tunnel to RDS from your laptop:
#   ssh -L 5432:<rds-endpoint>:5432 ec2-user@<bastion-ip> -i ~/.ssh/<key>.pem
#   psql -h localhost -U shopnow -d shopnow
module "bastion" {
  source = "../../modules/bastion"

  project          = var.project
  vpc_id           = module.vpc.vpc_id
  public_subnet_id = module.vpc.public_subnet_ids[0]
  rds_sg_id        = module.ecs.rds_sg_id
  key_name         = var.bastion_key_name
  allowed_cidr     = var.bastion_allowed_cidr
  tags             = local.common_tags
}

# ── IAM: Jenkins CI/CD ────────────────────────────────────────
module "iam" {
  source = "../../modules/iam"

  project             = var.project
  ecr_repository_arns = values(module.ecr.repository_arns)
  ecs_task_role_arns = [
    module.ecs.task_execution_role_arn,
    module.ecs.task_role_arn
  ]
  tags = local.common_tags
}
