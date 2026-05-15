# ─────────────────────────────────────────────────────────────
# Module: IAM — Jenkins CI/CD user
# Grants your local Jenkins the minimum permissions it needs to:
#   1. Push Docker images to ECR
#   2. Register new ECS task definitions
#   3. Update ECS services (rolling deploy)
# ─────────────────────────────────────────────────────────────

resource "aws_iam_user" "jenkins" {
  name = "${var.project}-jenkins"
  path = "/ci/"
  tags = var.tags
}

resource "aws_iam_access_key" "jenkins" {
  user = aws_iam_user.jenkins.name
}

resource "aws_iam_user_policy" "jenkins" {
  name = "${var.project}-jenkins-policy"
  user = aws_iam_user.jenkins.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Needed for: aws ecr get-login-password
        Sid      = "ECRLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        # Needed for: docker push / docker pull from ECR
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages"
        ]
        Resource = var.ecr_repository_arns
      },
      {
        # Needed for: aws ecs register-task-definition + aws ecs update-service
        Sid    = "ECSDeployment"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTaskDefinitions",
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:ListServices",
          "ecs:DescribeClusters"
        ]
        Resource = "*"
      },
      {
        # ECS needs Jenkins to pass the task roles when registering task defs
        Sid      = "PassRoleToECS"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = var.ecs_task_role_arns
      }
    ]
  })
}
