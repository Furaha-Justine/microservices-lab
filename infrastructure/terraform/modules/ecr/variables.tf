variable "project" {
  description = "Project name used as prefix for ECR repository names"
  type        = string
}

variable "repository_names" {
  description = "List of image names to create ECR repositories for"
  type        = list(string)
  default     = ["frontend", "backend"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
