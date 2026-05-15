# variables.tf
variable "project"                { type = string }
variable "vpc_id"                 { type = string }
variable "vpc_cidr"               { type = string }
variable "private_subnet_ids"     { type = list(string) }
variable "node_type"              { type = string; default = "cache.t3.micro" }
variable "num_cache_clusters"     { type = number; default = 1 }
variable "snapshot_retention_days" { type = number; default = 1 }
variable "alarm_sns_arn"          { type = string; default = "" }
variable "tags"                   { type = map(string); default = {} }
