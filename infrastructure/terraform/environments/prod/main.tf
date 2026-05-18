# ─────────────────────────────────────────────────────────────
# ShopNow — Production Environment
# Option A: All 4 services run as ECS Fargate tasks
#
# Modules used:
#   vpc  → VPC, public/private subnets, NAT, IGW
#   ecr  → ECR repos for frontend and backend
#   ecs  → 1 cluster, 4 task defs, 4 services, ALB, Cloud Map
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
# 2 AZs · public subnets (ALB, NAT) · private subnets (ECS tasks)
module "vpc" {
  source = "../../modules/vpc"

  project            = var.project
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  tags               = local.common_tags
}

# ── ECR ───────────────────────────────────────────────────────
# Repos for frontend and backend only.
# Postgres (postgres:16-alpine) and Redis (redis:7-alpine) pull from Docker Hub.
module "ecr" {
  source = "../../modules/ecr"

  project          = var.project
  repository_names = ["frontend", "backend"]
  tags             = local.common_tags
}

# ── ECS Fargate ───────────────────────────────────────────────
# 1 cluster · 4 task definitions · 4 services
# Request flow:
#   ALB → frontend (3000) → backend (5000) → postgres (5432)
#                                           → redis    (6379)
module "ecs" {
  source = "../../modules/ecs"

  project            = var.project
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # Images are pushed here by Jenkins; :latest is overridden per deploy
  frontend_image = "${module.ecr.repository_urls["frontend"]}:latest"
  backend_image  = "${module.ecr.repository_urls["backend"]}:latest"

  postgres_password = var.postgres_password

  tags = local.common_tags
}

# ── IAM: Jenkins CI/CD ────────────────────────────────────────
# Creates an IAM user your local Jenkins uses to:
#   - push images to ECR
#   - register task definitions
#   - trigger rolling ECS deploys
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
