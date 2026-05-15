# variables.tf
variable "project"             { type = string }
variable "vpc_id"              { type = string }
variable "vpc_cidr"            { type = string }
variable "private_subnet_ids"  { type = list(string) }
variable "db_name"             { type = string; default = "shopnow" }
variable "db_username"         { type = string; default = "shopnow" }
variable "db_password"         { type = string; sensitive = true }
variable "instance_class"      { type = string; default = "db.t3.medium" }
variable "allocated_storage"   { type = number; default = 20 }
variable "multi_az"            { type = bool;   default = false }
variable "deletion_protection" { type = bool;   default = false }
variable "backup_retention_days" { type = number; default = 7 }
variable "alarm_sns_arn"       { type = string; default = "" }
variable "tags"                { type = map(string); default = {} }
