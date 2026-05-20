variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  description = "A public subnet to place the bastion in"
  type        = string
}

variable "rds_sg_id" {
  description = "RDS security group — bastion will be granted inbound access on 5432"
  type        = string
}

variable "key_name" {
  description = "EC2 key pair name to use for SSH access (create in AWS Console → EC2 → Key Pairs)"
  type        = string
}

variable "allowed_cidr" {
  description = "Your laptop's IP in CIDR notation (e.g. 102.176.1.1/32). Use 0.0.0.0/0 to allow all."
  type        = string
  default     = "0.0.0.0/0"
}

variable "tags" {
  type    = map(string)
  default = {}
}
