variable "project" {
  type = string
}

variable "ecr_repository_arns" {
  description = "ARNs of ECR repos Jenkins is allowed to push images to"
  type        = list(string)
}

variable "ecs_task_role_arns" {
  description = "ARNs of ECS task roles Jenkins can pass when registering task definitions"
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
