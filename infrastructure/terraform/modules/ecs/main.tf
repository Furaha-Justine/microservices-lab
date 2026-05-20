# ─────────────────────────────────────────────────────────────
# Module: ECS Fargate + RDS PostgreSQL + ElastiCache Redis
#
# 1 cluster · 2 task definitions · 2 ECS services
# RDS PostgreSQL (managed) replaces the Postgres ECS container
# ElastiCache Redis (managed) replaces the Redis ECS container
#
# Service topology (all in private subnets):
#   Internet → ALB (public) → frontend → backend → RDS Postgres (5432)
#                                                 → ElastiCache Redis (6379)
#
# Service Connect: AWS Cloud Map (shopnow.local)
#   backend.shopnow.local:5000  ← used by frontend
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

# ── CloudWatch Log Groups ─────────────────────────────────────
resource "aws_cloudwatch_log_group" "services" {
  for_each          = toset(["frontend", "backend"])
  name              = "/ecs/${var.project}/${each.key}"
  retention_in_days = 7
  tags              = var.tags
}

# ── IAM: Task Execution Role ──────────────────────────────────
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
#               → RDS Postgres    (5432, from backend only)
#               → ElastiCache     (6379, from backend only)

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

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "RDS PostgreSQL: port 5432 from backend only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Backend to RDS"
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

  tags = merge(var.tags, { Name = "${var.project}-rds-sg" })
}

resource "aws_security_group" "elasticache" {
  name        = "${var.project}-elasticache-sg"
  description = "ElastiCache Redis: port 6379 from backend only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Backend to ElastiCache"
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

  tags = merge(var.tags, { Name = "${var.project}-elasticache-sg" })
}

# ── Application Load Balancer ─────────────────────────────────
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
# Service Connect registers backend here so frontend can reach
# it at backend:5000 without hardcoding IPs.
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.project}.local"
  description = "ShopNow Service Connect namespace"
  vpc         = var.vpc_id
  tags        = var.tags
}

# ── RDS: PostgreSQL ───────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnet-group"
  subnet_ids = var.private_subnet_ids
  tags       = merge(var.tags, { Name = "${var.project}-db-subnet-group" })
}

resource "aws_db_instance" "main" {
  identifier        = "${var.project}-postgres"
  engine            = "postgres"
  engine_version    = var.db_engine_version
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  db_name  = replace(var.project, "-", "_")
  username = replace(var.project, "-", "_")
  password = var.postgres_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period = var.db_backup_retention_days
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = var.tags
}

# ── ElastiCache: Redis ────────────────────────────────────────
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project}-cache-subnet-group"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id    = "${var.project}-redis"
  description             = "${var.project} Redis cache"
  node_type               = var.elasticache_node_type
  num_node_groups         = 1
  replicas_per_node_group = var.elasticache_num_replicas
  engine_version          = "7.1"
  parameter_group_name    = "default.redis7"
  port                    = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]

  # Failover requires at least one replica
  automatic_failover_enabled = var.elasticache_num_replicas > 0
  multi_az_enabled           = var.elasticache_num_replicas > 0

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false

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
        value = "postgresql://${replace(var.project, "-", "_")}:${var.postgres_password}@${aws_db_instance.main.address}:5432/${replace(var.project, "-", "_")}"
      },
      {
        name  = "REDIS_URL"
        value = "redis://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379/0"
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

# ── ECS Service: Backend ──────────────────────────────────────
# Reachable by frontend as "backend:5000" via Service Connect.
# Connects to RDS and ElastiCache using their managed endpoints.
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

  # Wait for managed data services to be ready before first deploy
  depends_on = [aws_db_instance.main, aws_elasticache_replication_group.main]

  tags = var.tags

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}

# ── ECS Service: Frontend ─────────────────────────────────────
# Sits behind the ALB. Client only — connects to backend:5000
# via Service Connect.
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
