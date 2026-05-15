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
    aws = { source = "hashicorp/aws"; version = "~> 5.40" }
  }

  backend "s3" {
    bucket         = "shopnow-terraform-state"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
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
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}

data "aws_availability_zones" "available" { state = "available" }

# ── VPC ───────────────────────────────────────────────────────
# Separate VPC from prod — different CIDR to avoid overlap
module "vpc" {
  source = "../../modules/vpc"

  project            = "${var.project}-staging"
  vpc_cidr           = "10.1.0.0/16"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  tags               = local.common_tags
}

# ── ECR ───────────────────────────────────────────────────────
# Reference the repos created by prod — staging uses the same
# repos with the :staging image tag.
data "aws_ecr_repository" "frontend" {
  name = "${var.project}/frontend"
}

data "aws_ecr_repository" "backend" {
  name = "${var.project}/backend"
}

# ── ECS Fargate ───────────────────────────────────────────────
# 1 cluster · 4 task definitions · 4 services
# Scaled down: 1 task each, half the CPU/memory of prod
module "ecs" {
  source = "../../modules/ecs"

  project            = "${var.project}-staging"
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  frontend_image = "${data.aws_ecr_repository.frontend.repository_url}:staging"
  backend_image  = "${data.aws_ecr_repository.backend.repository_url}:staging"

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
variable "aws_region"        { type = string; default = "us-east-1" }
variable "project"           { type = string; default = "shopnow" }
variable "postgres_password" { type = string; sensitive = true }

# ── Outputs ───────────────────────────────────────────────────
output "app_url"              { value = "http://${module.ecs.alb_dns_name}" }
output "ecs_cluster_name"     { value = module.ecs.cluster_name }
output "service_discovery_ns" { value = module.ecs.service_discovery_ns }
