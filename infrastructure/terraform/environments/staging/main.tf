# ─────────────────────────────────────────────────────────────
# ShopNow — Staging Environment
# Option A: All services in ECS Fargate (same as prod)
# Cheaper: 1 task per service, smaller CPU/memory
#
# ECR repos are shared with prod — no separate repos needed.
# Staging images are tagged :staging by the CI pipeline.
# ─────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  backend "s3" {
    bucket         = "shopnow-terraform-state-445567114084"
    key            = "staging/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "shopnow-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags { tags = local.common_tags }
}

data "aws_availability_zones" "available" { state = "available" }
data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project     = var.project
    Environment = "staging"
    ManagedBy   = "terraform"
  }
  # ECR URL is deterministic — no need to look up existing repos
  ecr_base = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

# ── VPC ───────────────────────────────────────────────────────
# Separate VPC from prod — different CIDR to avoid overlap
module "vpc" {
  source = "../../modules/vpc"

  project            = "${var.project}-staging"
  vpc_cidr           = "10.1.0.0/16"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  tags               = local.common_tags
}

# ── ECS Fargate ───────────────────────────────────────────────
# 1 cluster · 4 task definitions · 4 services
# Scaled down: 1 task each, half the CPU/memory of prod
# ECR repos are created by prod — staging reuses them with :staging tag
module "ecs" {
  source = "../../modules/ecs"

  project            = "${var.project}-staging"
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  frontend_image = "${local.ecr_base}/${var.project}/frontend:staging"
  backend_image  = "${local.ecr_base}/${var.project}/backend:staging"

  postgres_password = var.postgres_password

  frontend_cpu           = 256
  frontend_memory        = 512
  frontend_desired_count = 1

  backend_cpu           = 256
  backend_memory        = 512
  backend_desired_count = 1

  tags = local.common_tags
}

# ── Variables ─────────────────────────────────────────────────
variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "project" {
  type    = string
  default = "shopnow"
}

variable "postgres_password" {
  type      = string
  sensitive = true
}

# ── Outputs ───────────────────────────────────────────────────
output "app_url" { value = "http://${module.ecs.alb_dns_name}" }
output "ecs_cluster_name" { value = module.ecs.cluster_name }
output "service_discovery_ns" { value = module.ecs.service_discovery_ns }
