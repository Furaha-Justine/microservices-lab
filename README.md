# ShopNow — AWS ECS Fargate (Full Project)

> A production-grade 3-tier e-commerce application containerised with Docker and
> deployed exclusively on **AWS ECS Fargate** with service discovery (Cloud Map),
> load balancing (ALB), auto-scaling, full test coverage, and demonstrated resiliency.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Repository Structure](#2-repository-structure)
3. [Application Tiers](#3-application-tiers)
4. [Containerisation](#4-containerisation)
5. [Local Development](#5-local-development)
6. [Infrastructure as Code](#6-infrastructure-as-code)
7. [ECS Fargate Deployment](#7-ecs-fargate-deployment)
8. [Service Discovery — AWS Cloud Map](#8-service-discovery--aws-cloud-map)
9. [Load Balancing — ALB](#9-load-balancing--alb)
10. [Auto-Scaling](#10-auto-scaling)
11. [Resiliency Demonstration](#11-resiliency-demonstration)
12. [CI/CD Pipeline](#12-cicd-pipeline)
13. [Monitoring & Observability](#13-monitoring--observability)
14. [Security Hardening](#14-security-hardening)
15. [Live Walkthrough Script](#15-live-walkthrough-script)

---

## 1. Architecture Overview

```
                     ┌──────────────────────────┐
                     │         Internet          │
                     └──────────────┬────────────┘
                                    │ HTTP / HTTPS
                     ┌──────────────▼────────────┐
                     │  Application Load Balancer │
                     │  internet-facing · port 80 │
                     │  public subnets · 3 AZs    │
                     └──────────────┬────────────┘
                                    │ port 3000
          ┌─────────────────────────▼──────────────────────┐
          │             Frontend ECS Service                │
          │       2 Fargate tasks · Node.js 20              │
          │       private subnets · spread across AZs       │
          └─────────────────────────┬──────────────────────┘
                                    │ http://backend.shopnow.local:5000
                                    │ (AWS Cloud Map DNS)
          ┌─────────────────────────▼──────────────────────┐
          │              Backend ECS Service                │
          │       2 Fargate tasks · Node.js 20/Express     │
          │       private subnets · spread across AZs       │
          └──────────────┬──────────────────┬──────────────┘
                         │                  │
          ┌──────────────▼──────┐  ┌────────▼───────────────┐
          │  RDS PostgreSQL 16  │  │  ElastiCache Redis 7    │
          │  Multi-AZ · TLS     │  │  TLS · 2 nodes (prod)   │
          │  private subnets    │  │  private subnets         │
          └─────────────────────┘  └────────────────────────┘
```

---

## 2. Repository Structure

```
shopnow/
├── frontend/
│   ├── Dockerfile                  # Multi-stage Node.js 20 build
│   ├── package.json                # Deps + jest config
│   ├── server.js                   # Express: proxy, health, rate-limit
│   ├── public/index.html           # Single-page storefront
│   └── tests/server.test.js        # Jest unit tests (health, proxy, cart)
│
├── backend/
│   ├── Dockerfile                  # Multi-stage Node.js 20 build
│   ├── requirements.txt            # Express, SQLAlchemy, Redis, Prometheus
│   ├── package.json devDependencies — jest, supertest
│   └── app/
│       ├── __init__.py
│       ├── main.py                 # Express routes, DB init, Redis cache
│       └── tests/
│           ├── __init__.py
│           └── server.test.js  # Jest: health, products, cart, cache
│
├── docker-compose.yml              # Full 4-service local stack
├── .env.example                    # Safe local env template
├── .gitignore
│
├── infrastructure/
│   └── terraform/
│       ├── modules/
│       │   ├── vpc/                # VPC, subnets, NAT GWs, Flow Logs
│       │   ├── ecs/                # Cluster, tasks, services, ALB, Cloud Map, scaling
│       │   ├── rds/                # PostgreSQL 16, parameter group, alarms
│       │   └── elasticache/        # Redis 7, TLS, slow-log, alarms
│       └── environments/
│           ├── prod/               # Multi-AZ, 2 tasks, full capacity
│           │   ├── main.tf
│           │   ├── variables.tf
│           │   ├── outputs.tf
│           │   └── terraform.tfvars.example
│           └── staging/            # Single-AZ, 1 task, t3.micro
│               └── main.tf
│
└── scripts/
│   ├── bootstrap.sh                # One-time AWS setup (S3, DDB, IAM, ECR)
│   ├── build-push.sh               # Build + push images to ECR
│   ├── deploy-ecs.sh               # Deploy to ECS, wait for stable
│   └── resiliency-test.sh          # Kill task, measure recovery, report downtime
│
└── .github/
    └── workflows/
        ├── deploy.yml              # test → build → deploy to ECS
        └── terraform-validate.yml  # fmt + validate on PRs touching Terraform
```

---

## 3. Application Tiers

| Tier | Technology | Port | Responsibility |
|------|-----------|------|----------------|
| Frontend | Node.js 20 + Express | 3000 | Serves HTML/JS, proxies API calls to backend |
| Backend API | Node.js 20 + Express | 5000 | REST endpoints, business logic, DB, Redis cache |
| Cache | Redis 7 | 6379 | Product list cache, 60 s TTL, reduces DB load |
| Database | PostgreSQL 16 | 5432 | Products and cart tables |

**Backend API endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| GET | /health | Liveness check — always fast |
| GET | /ready | Readiness — verifies DB + Redis |
| GET | /metrics | Prometheus metrics |
| GET | /api/products | Product list (Redis-cached) |
| GET | /api/products/{id} | Single product |
| POST | /api/cart | Add item to cart |
| GET | /api/cart/{session_id} | View cart |

---

## 4. Containerisation

### Multi-stage builds

```
Frontend (node:20-alpine)            Backend (node:20-alpine)
──────────────────────────           ───────────────────────────────
Stage 1 — builder:                   Stage 1 — builder:
  npm ci --only=production             apt: gcc libpq-dev
  npm run build                        npm ci --only=production

Stage 2 — production:                Stage 2 — production:
  COPY --from=builder                  COPY from builder
  adduser appuser UID 1001             non-root user UID 1001
  EXPOSE 3000                          adduser appuser UID 1001
  HEALTHCHECK wget /health             EXPOSE 5000
  STOPSIGNAL SIGTERM                   HEALTHCHECK wget /health
  CMD node server.js                   STOPSIGNAL SIGTERM
                                       CMD uvicorn --workers 2
```

| Image | Naive | Multi-stage | Saving |
|-------|-------|-------------|--------|
| Frontend | ~400 MB | ~120 MB | 70% |
| Backend | ~850 MB | ~180 MB | 79% |

Security properties in every image: non-root UID 1001, SIGTERM graceful drain, HEALTHCHECK gates traffic, no compiler or dev tools in final layer.

---

## 5. Local Development

```bash
git clone https://github.com/your-org/shopnow.git
cd shopnow
cp .env.example .env

docker compose up --build
open http://localhost:3000

# Verify
curl http://localhost:3000/health           # {"status":"ok","service":"frontend"}
curl http://localhost:5000/ready            # {"status":"ready","checks":{...}}
curl http://localhost:5000/api/products     # product list from DB
curl -X POST http://localhost:5000/api/cart \
  -H "Content-Type: application/json" \
  -d '{"product_id":"p001","quantity":2,"session_id":"demo"}'

# Run tests
cd frontend && npm ci && npm test
cd ../backend && npm ci && npm test -- --verbose

# Debug UIs
docker compose --profile debug up -d
# pgAdmin         → http://localhost:5050
# Redis Commander → http://localhost:8081

docker compose down -v
```

---

## 6. Infrastructure as Code

### Terraform module map

```
environments/prod/main.tf
  ├── module.vpc
  │     10.0.0.0/16 · 3 public subnets (ALB) · 3 private (tasks/RDS/Redis)
  │     3 NAT Gateways (1 per AZ) · VPC Flow Logs → CloudWatch 14 days
  │
  ├── aws_ecr_repository  (frontend + backend)
  │     scan_on_push=true · lifecycle: keep last 10 images
  │
  ├── aws_sns_topic + subscription  (alarm notifications → email)
  │
  ├── module.rds
  │     PostgreSQL 16 · gp3 encrypted · Performance Insights
  │     Enhanced Monitoring · CloudWatch logs (postgresql + upgrade)
  │     Alarms: CPU >80%, FreeStorage <5 GB
  │
  ├── module.elasticache
  │     Redis 7 · allkeys-lru · TLS at-rest + in-transit
  │     Slow-log → CloudWatch · Alarms: CPU >80%, Memory >85%
  │
  └── module.ecs
        ECS Cluster (Container Insights enabled)
        IAM: task execution role + task role
        Security Groups: ALB → Frontend → Backend (least-privilege chain)
        ALB + Target Group (type:ip) + HTTP Listener
        Cloud Map: shopnow.local namespace + backend service
        Task Definitions: frontend (0.25vCPU/512MB) + backend (0.5vCPU/1GB)
        Services: desired=2, circuit breaker + rollback
        App Auto Scaling: CPU ≥ 70% → scale out (min 2, max 10)
```

### Staging vs prod differences

| | Prod | Staging |
|-|------|---------|
| AZs | 3 | 2 |
| RDS | db.t3.medium, Multi-AZ | db.t3.micro, single-AZ |
| Redis | 2 nodes, cache.t3.micro | 1 node, cache.t3.micro |
| Tasks | 2 per service | 1 per service |
| Task CPU/RAM | 512/1024 (backend) | 256/512 |

### Bootstrap and deploy

```bash
# One-time setup (S3 bucket, DynamoDB, OIDC, IAM role, ECR)
./scripts/bootstrap.sh us-east-1 your-org/shopnow

# Deploy infrastructure
cd infrastructure/terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars  # fill in db_password, alarm_email
terraform init
terraform plan
terraform apply

terraform output app_url         # → http://<alb-dns>
terraform output ecs_cluster_name
```

---

## 7. ECS Fargate Deployment

### Task definitions

| | Frontend | Backend |
|--|----------|---------|
| CPU | 256 units (0.25 vCPU) | 512 units (0.5 vCPU) |
| Memory | 512 MB | 1024 MB |
| Network | awsvpc (own ENI per task) | awsvpc |
| Key env var | `BACKEND_URL=http://backend.shopnow.local:5000` | `DATABASE_URL`, `REDIS_URL` |
| Log group | /ecs/shopnow/frontend | /ecs/shopnow/backend |

### Service settings (both services)

```
desired_count              = 2
capacity_provider          = FARGATE (base=1) + FARGATE_SPOT
min_healthy_percent        = 100   ← never drop below desired count
max_percent                = 200   ← surge to 4 tasks during deploy
health_check_grace_period  = 60 s
deployment_circuit_breaker = enabled + auto-rollback
```

### Build, push, and deploy

```bash
# All-in-one
./scripts/build-push.sh && ./scripts/deploy-ecs.sh

# Or step by step
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin \
  $ACCOUNT.dkr.ecr.$REGION.amazonaws.com

docker build --target production \
  -t $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/shopnow/backend:latest ./backend
docker push $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/shopnow/backend:latest

aws ecs update-service --cluster shopnow-ecs \
  --service shopnow-backend --force-new-deployment
aws ecs wait services-stable --cluster shopnow-ecs --services shopnow-backend

# Verify
aws ecs describe-services --cluster shopnow-ecs \
  --services shopnow-frontend shopnow-backend \
  --query 'services[].{Name:serviceName,Running:runningCount,Desired:desiredCount}' \
  --output table
```

---

## 8. Service Discovery — AWS Cloud Map

Terraform creates a **private DNS namespace** `shopnow.local` inside the VPC. The backend ECS service registers into it as `backend`.

**What happens at runtime:**
- When a backend task starts → ECS registers its ENI IP as an `A` record under `backend.shopnow.local`
- When a task stops or fails its health check → ECS deregisters its IP within 10 seconds (matching the TTL)
- Routing policy is **MULTIVALUE** → all healthy task IPs returned in DNS responses

**DNS resolution flow:**
```
Frontend task
  → BACKEND_URL = "http://backend.shopnow.local:5000"
  → getaddrinfo("backend.shopnow.local")
  → Route 53 Resolver (169.254.169.253 — built into every VPC)
  → Cloud Map returns: [10.0.2.45, 10.0.3.78]
  → Node.js HTTP client connects to one IP:5000
```

**Verify:**
```bash
NS_ID=$(aws servicediscovery list-namespaces \
  --query 'Namespaces[?Name==`shopnow.local`].Id' --output text)
SVC_ID=$(aws servicediscovery list-services \
  --filters Name=NAMESPACE_ID,Values=$NS_ID,Condition=EQ \
  --query 'Services[?Name==`backend`].Id' --output text)
aws servicediscovery list-instances --service-id $SVC_ID \
  --query 'Instances[].Attributes.AWS_INSTANCE_IPV4'

# From inside a running task
aws ecs execute-command --cluster shopnow-ecs \
  --task <TASK_ARN> --container frontend --interactive \
  --command "nslookup backend.shopnow.local"
```

---

## 9. Load Balancing — ALB

```
ALB (shopnow-ecs-alb)
  scheme:           internet-facing
  subnets:          public subnets (all 3 AZs)
  security group:   inbound 80 from 0.0.0.0/0

Listener (port 80)
  └─ Default action: forward → Frontend Target Group

Frontend Target Group
  type:             ip  (routes directly to task ENI IPs)
  protocol/port:    HTTP:3000
  health check:     GET /health → 200
                    interval 30s · healthy threshold 2 · unhealthy threshold 3
  deregistration:   30 s drain (in-flight connections finish cleanly)
```

**Security group chain:**
```
Internet       → ALB SG        (80, 443)
ALB SG         → Frontend SG   (3000)
Frontend SG    → Backend SG    (5000)
VPC CIDR       → RDS SG        (5432)
VPC CIDR       → Redis SG      (6379)
```

---

## 10. Auto-Scaling

Both services use CPU-based target tracking via App Auto Scaling:

| | Frontend | Backend |
|--|----------|---------|
| Min tasks | 2 | 2 |
| Max tasks | 10 | 10 |
| Scale-out at | CPU ≥ 70% | CPU ≥ 70% |
| Scale-out cooldown | 60 s | 60 s |
| Scale-in cooldown | 300 s | 300 s |

The 300 s scale-in cooldown prevents flapping — tasks aren't removed the moment a burst ends.

```bash
# Watch scaling activity
aws application-autoscaling describe-scaling-activities \
  --service-namespace ecs \
  --resource-id service/shopnow-ecs/shopnow-backend

# Current counts
aws ecs describe-services --cluster shopnow-ecs --services shopnow-backend \
  --query 'services[0].{Running:runningCount,Desired:desiredCount,Pending:pendingCount}'
```

---

## 11. Resiliency Demonstration

### Automated script

```bash
# Runs end-to-end: starts poller, kills a task, waits for recovery, reports
./scripts/resiliency-test.sh shopnow-ecs shopnow-backend
```

### Manual — Terminal A (start first)
```bash
ALB=$(aws elbv2 describe-load-balancers --names shopnow-ecs-alb \
  --query 'LoadBalancers[0].DNSName' --output text)
while true; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$ALB/api/products")
  echo "$(date '+%H:%M:%S')  $CODE"
  sleep 1
done
```

### Manual — Terminal B (kill a task)
```bash
TASK=$(aws ecs list-tasks --cluster shopnow-ecs \
  --service-name shopnow-backend --query 'taskArns[0]' --output text)
aws ecs stop-task --cluster shopnow-ecs --task $TASK --reason "Resiliency demo"

watch -n 2 "aws ecs describe-services --cluster shopnow-ecs \
  --services shopnow-backend \
  --query 'services[0].{Running:runningCount,Pending:pendingCount}'"
```

### Expected sequence

```
t=0s   stop-task → runningCount: 2 → 1
t=2s   ECS scheduler: actual < desired → pendingCount=1
t=20s  New task passes health check → Cloud Map registers new IP
t=25s  runningCount: 2 restored

Terminal A: uninterrupted 200 OK — zero failures
```

**Why zero downtime?** The ALB removes a task from its target group as soon as the health check fails — before the task is fully stopped. The surviving task handles all traffic while the replacement starts.

---

## 12. CI/CD Pipeline

```
push to main (or staging)
  │
  ├─ test-frontend   (npm ci + jest --coverage)
  ├─ test-backend    (npm ci + jest --coverage)
  │
  ├─ build           (only after both tests pass, only on main/staging)
  │    docker buildx → ECR
  │    tag: {branch}-{YYYYMMDD}-{SHA7} + :latest (or :staging)
  │    both frontend and backend, with GHA layer caching
  │
  └─ deploy          (waits for build)
       backend: update-service → wait services-stable
       frontend: update-service → wait services-stable
       smoke test: curl /health → assert 200
       verify: describe-services table output
```

On pull requests: only tests run — no build, no deploy.

Separate `terraform-validate.yml` workflow runs on every PR touching `infrastructure/terraform/`:
- `terraform fmt -check` on all `.tf` files
- `terraform init -backend=false` + `terraform validate` for both prod and staging

**Required secret:** `AWS_ACCOUNT_ID` — everything else uses GitHub OIDC (no static keys).

---

## 13. Monitoring & Observability

```bash
# Service health
aws ecs describe-services --cluster shopnow-ecs \
  --services shopnow-frontend shopnow-backend \
  --query 'services[].{Name:serviceName,Running:runningCount,Status:status}' \
  --output table

# Live logs
aws logs tail /ecs/shopnow/backend  --follow --format short
aws logs tail /ecs/shopnow/frontend --follow --format short

# CPU over last hour (Container Insights)
aws cloudwatch get-metric-statistics \
  --namespace ECS/ContainerInsights \
  --metric-name CpuUtilized \
  --dimensions Name=ClusterName,Value=shopnow-ecs \
               Name=ServiceName,Value=shopnow-backend \
  --start-time $(date -u -d '1 hour ago' +%FT%TZ) \
  --end-time   $(date -u +%FT%TZ) \
  --period 60 --statistics Average

# Error count (Log Insights)
aws logs start-query \
  --log-group-name /ecs/shopnow/backend \
  --start-time $(date -d '1 hour ago' +%s) --end-time $(date +%s) \
  --query-string 'filter @message like /ERROR/ | stats count()'

# Deployment events
aws ecs describe-services --cluster shopnow-ecs --services shopnow-backend \
  --query 'services[0].events[:5]'

# RDS + Redis alarms (created automatically by Terraform modules)
aws cloudwatch describe-alarms \
  --alarm-name-prefix shopnow \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}'
```

Prometheus metrics available at `GET /metrics` on the backend (port 5000). Scrape from within the VPC or via ECS Exec.

---

## 14. Security Hardening

### Implemented

- [x] Non-root containers (UID 1001)
- [x] Multi-stage builds — no compiler or dev tools in prod images
- [x] ECR `scan_on_push = true` — vulnerabilities caught before deploy
- [x] ECR lifecycle policy — max 10 images, old ones auto-purged
- [x] All ECS tasks in private subnets (no public IPs)
- [x] Least-privilege security group chain (ALB → Frontend → Backend)
- [x] RDS: AES-256 at-rest encryption, Multi-AZ, TLS in transit
- [x] ElastiCache: TLS at-rest + in-transit (`rediss://`)
- [x] VPC Flow Logs → CloudWatch (14-day retention, all traffic)
- [x] GitHub OIDC — no long-lived AWS credentials stored anywhere
- [x] Terraform state: S3 encrypted + DynamoDB lock
- [x] Container Insights + RDS Enhanced Monitoring
- [x] CloudWatch alarms: RDS CPU, RDS storage, Redis CPU, Redis memory
- [x] SNS → email notifications for alarms

### Recommended before production launch

- [ ] AWS WAF on ALB — rate limiting, SQLi/XSS protection
- [ ] AWS Secrets Manager + ECS secrets reference — replace plaintext env vars
- [ ] VPC Endpoints for ECR, CloudWatch, S3 — eliminate NAT for AWS API calls
- [ ] AWS GuardDuty — runtime threat detection
- [ ] HTTPS listener on ALB + ACM certificate

---

## 15. Live Walkthrough Script

```bash
# ══════════════════════════════════════════════════════
# PART 1 — Local Docker stack
# ══════════════════════════════════════════════════════
cd shopnow
docker compose up --build -d
docker compose ps                          # All 4 services Up + healthy
docker images | grep shopnow              # Show multi-stage size savings
curl http://localhost:3000/health
curl http://localhost:5000/ready
open http://localhost:3000

# ══════════════════════════════════════════════════════
# PART 2 — Tests
# ══════════════════════════════════════════════════════
cd frontend && npm test -- --verbose 2>&1 | tail -15
cd ../backend && npm test -- --verbose 2>&1 | tail -15

# ══════════════════════════════════════════════════════
# PART 3 — Terraform plan
# ══════════════════════════════════════════════════════
cd ../infrastructure/terraform/environments/prod
terraform init && terraform plan -var="db_password=demo" 2>&1 | \
  grep -E "^(Plan| \+)" | head -20

# ══════════════════════════════════════════════════════
# PART 4 — Live ECS cluster
# ══════════════════════════════════════════════════════
aws ecs describe-services --cluster shopnow-ecs \
  --services shopnow-frontend shopnow-backend \
  --query 'services[].{Name:serviceName,Running:runningCount,Desired:desiredCount}' \
  --output table

ALB=$(aws elbv2 describe-load-balancers --names shopnow-ecs-alb \
  --query 'LoadBalancers[0].DNSName' --output text)
open http://$ALB

# Show Cloud Map registrations
NS_ID=$(aws servicediscovery list-namespaces \
  --query 'Namespaces[?Name==`shopnow.local`].Id' --output text)
SVC_ID=$(aws servicediscovery list-services \
  --filters Name=NAMESPACE_ID,Values=$NS_ID,Condition=EQ \
  --query 'Services[?Name==`backend`].Id' --output text)
aws servicediscovery list-instances --service-id $SVC_ID \
  --query 'Instances[].Attributes.AWS_INSTANCE_IPV4'

# ══════════════════════════════════════════════════════
# PART 5 — Resiliency demo
# ══════════════════════════════════════════════════════

# Terminal A: availability poller
while true; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$ALB/api/products")
  echo "$(date '+%H:%M:%S')  $CODE"; sleep 1
done

# Terminal B: automated kill + recovery
./scripts/resiliency-test.sh shopnow-ecs shopnow-backend
# Output: Recovery in ~22 seconds | 0 failures — ZERO DOWNTIME ✓

# ══════════════════════════════════════════════════════
# PART 6 — Trigger CI/CD
# ══════════════════════════════════════════════════════
git commit --allow-empty -m "chore: pipeline demo"
git push origin main
# GitHub Actions: test-frontend + test-backend → build → deploy
```

---

*ShopNow · ECS Fargate · Production-grade DevOps project*
