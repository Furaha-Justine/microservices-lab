# ─────────────────────────────────────────────────────────────
# Module: ECS Fargate — Option A (all services in ECS)
#
# 1 cluster · 4 task definitions · 4 services
#
# Service topology (all in private subnets):
#   Internet → ALB (public) → frontend → backend → postgres
#                                                 → redis
#
# Service discovery: AWS Cloud Map  (shopnow.local)
#   backend.shopnow.local:5000
#   postgres.shopnow.local:5432
#   redis.shopnow.local:6379
#
# NOTE: postgres data is ephemeral — attach EFS for persistence
#       in a production system.
# ─────────────────────────────────────────────────────────────

# ── ECS Cluster ───────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# ── CloudWatch Log Groups (one per service) ───────────────────
resource "aws_cloudwatch_log_group" "services" {
  for_each          = toset(["frontend", "backend", "postgres", "redis"])
  name              = "/ecs/${var.project}/${each.key}"
  retention_in_days = 7
  tags              = var.tags
}

# ── IAM: Task Execution Role ──────────────────────────────────
# ECS control plane uses this to pull images from ECR and write logs
resource "aws_iam_role" "task_execution" {
  name = "${var.project}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── IAM: Task Role ────────────────────────────────────────────
# The application container uses this at runtime
resource "aws_iam_role" "task" {
  name = "${var.project}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

# ── Security Groups ───────────────────────────────────────────
#
#  Internet → ALB (80/443)
#           → frontend (3000, from ALB only)
#             → backend (5000, from frontend only)
#               → postgres (5432, from backend only)
#               → redis    (6379, from backend only)

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "Public ALB: HTTP/HTTPS from internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project}-alb-sg" })
}

resource "aws_security_group" "frontend" {
  name        = "${var.project}-frontend-sg"
  description = "Frontend Fargate tasks: port 3000 from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "ALB to Frontend"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project}-frontend-sg" })
}

resource "aws_security_group" "backend" {
  name        = "${var.project}-backend-sg"
  description = "Backend Fargate tasks: port 5000 from frontend only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Frontend to Backend"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project}-backend-sg" })
}

resource "aws_security_group" "postgres" {
  name        = "${var.project}-postgres-sg"
  description = "Postgres Fargate task: port 5432 from backend only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Backend to Postgres"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project}-postgres-sg" })
}

resource "aws_security_group" "redis" {
  name        = "${var.project}-redis-sg"
  description = "Redis Fargate task: port 6379 from backend only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Backend to Redis"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project}-redis-sg" })
}

# ── Application Load Balancer ─────────────────────────────────
# Lives in public subnets. Routes traffic to frontend tasks.
resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  enable_http2               = true

  tags = var.tags
}

resource "aws_lb_target_group" "frontend" {
  name        = "${var.project}-frontend-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200"
  }

  deregistration_delay = 30
  tags                 = var.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# ── Cloud Map: Private DNS Namespace ──────────────────────────
# Service Connect uses this namespace to register short DNS names:
#   backend  → backend:5000
#   postgres → postgres:5432
#   redis    → redis:6379
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.project}.local"
  description = "ShopNow Service Connect namespace"
  vpc         = var.vpc_id
  tags        = var.tags
}

# ── Task Definition: Postgres ─────────────────────────────────
resource "aws_ecs_task_definition" "postgres" {
  family                   = "${var.project}-postgres"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "postgres"
    image     = "postgres:16-alpine"
    essential = true

    portMappings = [{
      name          = "postgres-port"
      containerPort = 5432
      protocol      = "tcp"
      appProtocol   = "http"
    }]

    environment = [
      { name = "POSTGRES_DB", value = var.project },
      { name = "POSTGRES_USER", value = var.project },
      { name = "POSTGRES_PASSWORD", value = var.postgres_password }
    ]

    healthCheck = {
      command     = ["CMD-SHELL", "pg_isready -U ${var.project} -d ${var.project} || exit 1"]
      interval    = 15
      timeout     = 5
      retries     = 5
      startPeriod = 30
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services["postgres"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "postgres"
      }
    }
  }])

  tags = var.tags
}

# ── Task Definition: Redis ────────────────────────────────────
resource "aws_ecs_task_definition" "redis" {
  family                   = "${var.project}-redis"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "redis"
    image     = "redis:7-alpine"
    essential = true

    portMappings = [{
      name          = "redis-port"
      containerPort = 6379
      protocol      = "tcp"
      appProtocol   = "http"
    }]

    command = [
      "redis-server",
      "--appendonly", "yes",
      "--maxmemory", "200mb",
      "--maxmemory-policy", "allkeys-lru"
    ]

    healthCheck = {
      command     = ["CMD-SHELL", "redis-cli ping || exit 1"]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services["redis"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "redis"
      }
    }
  }])

  tags = var.tags
}

# ── Task Definition: Backend ──────────────────────────────────
resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project}-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.backend_cpu
  memory                   = var.backend_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "backend"
    image     = var.backend_image
    essential = true

    portMappings = [{
      name          = "backend-port"
      containerPort = 5000
      protocol      = "tcp"
      appProtocol   = "http"
    }]

    environment = [
      {
        name  = "DATABASE_URL"
        # Service Connect resolves "postgres" to the postgres service endpoint
        value = "postgresql://${var.project}:${var.postgres_password}@postgres:5432/${var.project}"
      },
      {
        name  = "REDIS_URL"
        # Service Connect resolves "redis" to the redis service endpoint
        value = "redis://redis:6379/0"
      },
      { name = "CACHE_TTL", value = "60" },
      { name = "PORT", value = "5000" }
    ]

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:5000/health || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 30
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services["backend"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "backend"
      }
    }
  }])

  tags = var.tags
}

# ── Task Definition: Frontend ─────────────────────────────────
resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.project}-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.frontend_cpu
  memory                   = var.frontend_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = var.frontend_image
    essential = true

    portMappings = [{
      name          = "frontend-port"
      containerPort = 3000
      protocol      = "tcp"
      appProtocol   = "http"
    }]

    environment = [
      {
        name  = "BACKEND_URL"
        # Service Connect resolves "backend" to the backend service endpoint
        value = "http://backend:5000"
      },
      { name = "PORT", value = "3000" }
    ]

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:3000/health || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 20
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services["frontend"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "frontend"
      }
    }
  }])

  tags = var.tags
}

# ── ECS Service: Postgres ─────────────────────────────────────
# Runs 1 task. Reachable by other services as "postgres:5432"
resource "aws_ecs_service" "postgres" {
  name            = "${var.project}-postgres"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.postgres.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.postgres.id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn

    service {
      port_name = "postgres-port"
      client_alias {
        port     = 5432
        dns_name = "postgres"
      }
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ── ECS Service: Redis ────────────────────────────────────────
# Runs 1 task. Reachable by other services as "redis:6379"
resource "aws_ecs_service" "redis" {
  name            = "${var.project}-redis"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.redis.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.redis.id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn

    service {
      port_name = "redis-port"
      client_alias {
        port     = 6379
        dns_name = "redis"
      }
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ── ECS Service: Backend ──────────────────────────────────────
# Reachable by frontend as "backend:5000" via Service Connect.
# Also a client — connects to postgres:5432 and redis:6379.
# Jenkins redeploys this by updating the task definition revision.
resource "aws_ecs_service" "backend" {
  name            = "${var.project}-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.backend.id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn

    service {
      port_name = "backend-port"
      client_alias {
        port     = 5000
        dns_name = "backend"
      }
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  depends_on = [aws_ecs_service.postgres, aws_ecs_service.redis]

  tags = var.tags

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}

# ── ECS Service: Frontend ─────────────────────────────────────
# Sits behind the ALB. Client only — connects to backend:5000.
# Jenkins redeploys this on new image push.
resource "aws_ecs_service" "frontend" {
  name            = "${var.project}-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.frontend_desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.frontend.id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn
    # No service block — frontend is a client only, not discovered by others
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 3000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60

  depends_on = [aws_lb_listener.http, aws_ecs_service.backend]

  tags = var.tags

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}

# ── Auto Scaling: Backend ─────────────────────────────────────
resource "aws_appautoscaling_target" "backend" {
  max_capacity       = 10
  min_capacity       = var.backend_desired_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "backend_cpu" {
  name               = "${var.project}-backend-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.backend.resource_id
  scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.backend.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# ── Auto Scaling: Frontend ────────────────────────────────────
resource "aws_appautoscaling_target" "frontend" {
  max_capacity       = 10
  min_capacity       = var.frontend_desired_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.frontend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "frontend_cpu" {
  name               = "${var.project}-frontend-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.frontend.resource_id
  scalable_dimension = aws_appautoscaling_target.frontend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.frontend.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
