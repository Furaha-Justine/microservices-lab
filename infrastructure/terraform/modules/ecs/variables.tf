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
  description = "Full ECR image URI for the frontend (e.g. 123456789.dkr.ecr.eu-west-1.amazonaws.com/shopnow/frontend:latest)"
  type        = string
}

variable "backend_image" {
  description = "Full ECR image URI for the backend"
  type        = string
}

variable "postgres_password" {
  description = "Password for the postgres superuser — also used in DATABASE_URL"
  type        = string
  sensitive   = true
}

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
