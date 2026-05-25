
terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "shopnow-terraform-state-445567114084"
    key            = "eks-prod/terraform.tfstate"
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

module "vpc" {
  source = "../../modules/vpc"

  project            = "${var.project}-eks"
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  tags               = local.common_tags
}

# ── ECR ───────────────────────────────────────────────────
module "ecr" {
  source = "../../modules/ecr"

  project          = var.project
  repository_names = ["frontend", "backend"]
  tags             = local.common_tags
}

# ── IAM: Jenkins CI/CD ────────────────────────────────────────
module "iam" {
  source = "../../modules/iam"

  project             = var.project
  ecr_repository_arns = values(module.ecr.repository_arns)
  ecs_task_role_arns  = []
  tags                = local.common_tags
}

# ── EKS Cluster + RDS + ElastiCache ───────────────────────────
module "eks" {
  source = "../../modules/eks"

  project            = var.project
  environment        = var.environment
  aws_region         = var.aws_region
  vpc_id             = [module.vpc.vpc_id]
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  kubernetes_version = var.kubernetes_version
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size

  postgres_password        = var.postgres_password
  db_instance_class        = var.db_instance_class
  db_engine_version        = var.db_engine_version
  db_allocated_storage     = var.db_allocated_storage
  db_backup_retention_days = var.db_backup_retention_days
  multi_az                 = var.multi_az

  elasticache_node_type    = var.elasticache_node_type
  elasticache_num_replicas = var.elasticache_num_replicas

  jenkins_user_arn = module.iam.jenkins_user_arn

  tags = local.common_tags
}
