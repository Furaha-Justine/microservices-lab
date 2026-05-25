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
    Statement = concat(
      [
        {
          Sid      = "ECRLogin"
          Effect   = "Allow"
          Action   = ["ecr:GetAuthorizationToken"]
          Resource = "*"
        },
        {
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
          Sid    = "EKSAccess"
          Effect = "Allow"
          Action = [
            "eks:DescribeCluster",
            "eks:ListClusters"
          ]
          Resource = "*"
        },
        {
          Sid    = "RDSDescribe"
          Effect = "Allow"
          Action = [
            "rds:DescribeDBInstances"
          ]
          Resource = "*"
        },
        {
          Sid    = "ElastiCacheDescribe"
          Effect = "Allow"
          Action = [
            "elasticache:DescribeReplicationGroups"
          ]
          Resource = "*"
        }
      ],
      length(var.ecs_task_role_arns) > 0 ? [
        {
          Sid      = "PassRoleToECS"
          Effect   = "Allow"
          Action   = ["iam:PassRole"]
          Resource = var.ecs_task_role_arns
        }
      ] : []
    )
  })
}
