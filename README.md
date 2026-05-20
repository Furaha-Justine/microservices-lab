# ShopNow — AWS ECS Fargate

A production-grade e-commerce application built with Node.js, containerised with Docker,
and deployed on **AWS ECS Fargate** with managed RDS PostgreSQL, ElastiCache Redis,
Application Load Balancer, Service Connect, and a Jenkins CI/CD pipeline.

---

## Architecture

```
                         Internet
                             │
                    ┌────────▼─────────┐
                    │       ALB        │  public subnets
                    │  internet-facing │  port 80
                    └────────┬─────────┘
                             │ port 3000
               ┌─────────────▼────────────┐
               │     Frontend ECS Service  │  private subnets
               │   Node.js 20 · Express    │  2 Fargate tasks
               └─────────────┬────────────┘
                             │ Service Connect
                             │ http://backend:5000
               ┌─────────────▼────────────┐
               │     Backend ECS Service   │  private subnets
               │   Node.js 20 · Express    │  2 Fargate tasks
               └──────┬──────────┬─────────┘
                      │          │
           ┌──────────▼───┐  ┌───▼──────────────┐
           │     RDS       │  │   ElastiCache     │
           │  PostgreSQL   │  │     Redis 7       │
           │   port 5432   │  │    port 6379      │
           └───────────────┘  └──────────────────┘
```

All ECS services, RDS, and ElastiCache run in **private subnets** — nothing is publicly accessible except the ALB.

---

## How ECS Works in This Project

### Fargate — no servers to manage

This project uses the **Fargate launch type**, not EC2. That means there are no virtual machines to provision, patch, or manage. You define how much CPU and memory each container needs, and AWS handles the rest — finding capacity, starting the container, and cleaning up when it stops.

Each task runs in a **private subnet** with no public IP. The only entry point into the system is the ALB.

### awsvpc networking — each task gets its own IP

ECS tasks here use `awsvpc` network mode. Instead of sharing a host's network interface, each task gets its own **Elastic Network Interface (ENI)** with its own private IP address. This means:

- Security groups apply directly to the task, not the host
- The ALB routes traffic directly to the task's IP (target group type: `ip`)
- No port mapping conflicts — two tasks on the same container port never collide

### Task Definitions — the blueprint

A task definition describes what to run and how. For this project:

```
Frontend task definition
  ├── Container: frontend (Node.js)
  ├── Port: 3000
  ├── CPU: 256 units (0.25 vCPU)
  ├── Memory: 512 MB
  ├── Network mode: awsvpc
  ├── Log driver: awslogs → /ecs/shopnow/frontend
  └── Env vars: BACKEND_URL, PORT

Backend task definition
  ├── Container: backend (Node.js)
  ├── Port: 5000
  ├── CPU: 512 units (0.5 vCPU)
  ├── Memory: 1024 MB
  ├── Network mode: awsvpc
  ├── Log driver: awslogs → /ecs/shopnow/backend
  └── Env vars: DATABASE_URL (RDS), REDIS_URL (ElastiCache), CACHE_TTL
```

Jenkins deploys a new version by registering a new **task definition revision** (with the updated ECR image) and then calling `update-service` to point to it. ECS handles the rollout.

### ECS Services — keep N tasks running

An ECS Service wraps a task definition and ensures the desired number of tasks are always running. If a task crashes, the service scheduler starts a replacement automatically.

Both services are configured with:
```
desired_count              = 2       ← always 2 tasks running
min_healthy_percent        = 100     ← never kill a task before a replacement is healthy
max_percent                = 200     ← allows 4 tasks during a rolling deploy (2 old + 2 new)
deployment_circuit_breaker = enabled ← auto-rollback if new tasks fail health checks
```

### Rolling deployments

When Jenkins pushes a new image:

```
Before deploy:   [task v1] [task v1]         (2 running)

During deploy:   [task v1] [task v1]
                 [task v2] [task v2]          (4 running — max 200%)

After healthy:   [task v2] [task v2]         (2 running — old tasks drained and stopped)
```

The ALB only sends traffic to tasks that pass their health check (`GET /health → 200`). Users never see a failed task.

### Circuit Breaker — automatic rollback

If the new tasks fail their health checks during a deployment, ECS automatically rolls back to the previous task definition revision. No manual intervention needed.

### Service Connect — internal service discovery

Frontend tasks reach the backend using `http://backend:5000` — no IPs, no hardcoded hostnames. Service Connect (built on AWS Cloud Map) handles the DNS resolution:

```
Frontend task
  → http://backend:5000
  → Service Connect resolves "backend" to a healthy backend task IP
  → Request delivered to backend container
```

When a backend task starts, ECS registers its IP. When it stops or fails health checks, ECS deregisters it. The frontend always connects to a healthy task.

### Auto Scaling — scale on CPU

Both services scale automatically based on CPU utilisation:

```
CPU ≥ 70%  →  scale out (add tasks, 60s cooldown)
CPU < 70%  →  scale in  (remove tasks, 300s cooldown)
Min tasks: 2  |  Max tasks: 10
```

The 300s scale-in cooldown prevents flapping — tasks aren't removed the moment a burst ends.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Node.js 20, Express — serves static HTML/JS, proxies API to backend |
| Backend | Node.js 20, Express — REST API, business logic, DB queries |
| Database | RDS PostgreSQL 16 — managed, private subnet, automated backups |
| Cache | ElastiCache Redis 7 — managed, caches product listings (60s TTL) |
| Container runtime | AWS ECS Fargate — serverless containers, no EC2 to manage |
| Load balancer | AWS ALB — internet-facing, health checks, target group type: IP |
| Service discovery | AWS Service Connect (Cloud Map) — frontend reaches backend via `backend:5000` |
| Infrastructure | Terraform — all AWS resources defined as code |
| CI/CD | Jenkins — test → build → push to ECR → deploy to ECS |

---

## Repository Structure

```
shopnow/
├── frontend/
│   ├── Dockerfile               # Multi-stage Node.js 20 build
│   ├── server.js                # Express: proxy, static files, health check, rate limit
│   ├── public/index.html        # Single-page storefront (vanilla JS)
│   └── tests/                   # Jest unit tests
│
├── backend/
│   ├── Dockerfile               # Multi-stage Node.js 20 build
│   ├── src/
│   │   ├── server.js            # Express routes: products, cart, orders, wishlist, reviews
│   │   ├── db.js                # PostgreSQL pool, schema init, seed data
│   │   └── cache.js             # Redis client with graceful fallback
│   └── tests/                   # Jest unit tests
│
├── docker-compose.yml           # Local dev stack (Postgres + Redis + backend + frontend)
├── Jenkinsfile                  # CI/CD pipeline: test → build → push → deploy → verify
│
└── infrastructure/terraform/
    ├── bootstrap/               # S3 state bucket + DynamoDB lock table (run once)
    ├── modules/
    │   ├── vpc/                 # VPC, public/private subnets, NAT gateways, Flow Logs
    │   ├── ecs/                 # Cluster, task definitions, services, ALB, RDS, ElastiCache
    │   ├── iam/                 # Jenkins CI/CD IAM user and access keys
    │   └── bastion/             # EC2 bastion host for SSH tunnel to RDS
    └── environments/
        └── prod/                # Production environment wiring all modules together
```

---

## API Endpoints

| Method | Path | Description | Cached |
|---|---|---|---|
| GET | /health | Liveness check | No |
| GET | /ready | Readiness — checks DB + Redis | No |
| GET | /metrics | Prometheus metrics | No |
| GET | /api/products | List products (filter by category) | Yes — 60s |
| GET | /api/products/search | Search products by keyword | No |
| GET | /api/categories | List categories with counts | Yes — 5min |
| GET | /api/products/:id | Single product with reviews summary | No |
| POST | /api/products | Create product | No |
| PUT | /api/products/:id | Update product | No |
| DELETE | /api/products/:id | Delete product | No |
| POST | /api/cart | Add item to cart | No |
| GET | /api/cart/:session_id | View cart | No |
| PUT | /api/cart/:session_id/item/:product_id | Update quantity | No |
| DELETE | /api/cart/:session_id/item/:product_id | Remove item | No |
| DELETE | /api/cart/:session_id | Clear cart | No |
| POST | /api/orders | Checkout (converts cart to order) | No |
| GET | /api/orders | List orders by session | No |
| GET | /api/orders/:id | Order detail with items | No |
| PUT | /api/orders/:id/status | Update order status | No |
| POST | /api/products/:id/reviews | Submit review | No |
| GET | /api/products/:id/reviews | Get reviews | No |
| POST | /api/wishlist | Add to wishlist | No |
| GET | /api/wishlist/:session_id | View wishlist | No |
| DELETE | /api/wishlist/:session_id/item/:product_id | Remove from wishlist | No |
| GET | /api/stats | Store-wide stats | No |

---

## Local Development

### Prerequisites
- Docker Desktop

### Run the full stack

```bash
git clone https://github.com/Furaha-Justine/microservices-lab.git
cd microservices-lab

docker compose up --build
```

Then open `http://localhost:3000`.

### Verify everything is healthy

```bash
curl http://localhost:3000/health          # frontend
curl http://localhost:5001/health          # backend (direct)
curl http://localhost:5001/ready           # checks DB + Redis
curl http://localhost:5001/api/products    # product list from DB
```

### Run tests

```bash
cd frontend && npm ci && npm test
cd ../backend && npm ci && npm test
```

### Debug UIs (optional)

```bash
docker compose --profile debug up -d

# pgAdmin         → http://localhost:5050  (admin@shopnow.local / admin)
# Redis Commander → http://localhost:8081
```

### Reset the database

```bash
docker compose down -v   # -v removes volumes (wipes DB)
docker compose up --build
```

---

## Infrastructure — Terraform

### Step 1 — Bootstrap (run once ever)

Creates the S3 bucket and DynamoDB table that store Terraform state.

```bash
cd infrastructure/terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

### Step 2 — Create an EC2 key pair

In the AWS Console → EC2 → Key Pairs → Create key pair:
- Name: `shopnow-bastion`
- Type: RSA, Format: .pem

```bash
mv ~/Downloads/shopnow-bastion.pem ~/.ssh/
chmod 400 ~/.ssh/shopnow-bastion.pem
```

### Step 3 — Deploy prod

```bash
cd infrastructure/terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region           = "eu-west-1"
project              = "shopnow"
environment          = "prod"
vpc_cidr             = "10.0.0.0/16"
postgres_password    = "yourStrongPassword"   # min 8 chars, no @/"/space
bastion_key_name     = "shopnow-bastion"
bastion_allowed_cidr = "YOUR_IP/32"           # curl https://checkip.amazonaws.com
```

```bash
terraform init
terraform plan
terraform apply
```

### Outputs after apply

```bash
terraform output app_url                         # live site URL
terraform output alb_dns_name                    # for Jenkins ALB_DNS
terraform output ecr_frontend_url                # ECR image URL
terraform output ecr_backend_url                 # ECR image URL
terraform output jenkins_access_key_id           # for Jenkins credentials
terraform output -raw jenkins_secret_access_key  # for Jenkins credentials
terraform output bastion_ip                      # for SSH tunnel to RDS
terraform output rds_endpoint                    # RDS hostname:port
terraform output elasticache_address             # Redis hostname
```

---

## Security Groups

Traffic is allowed only in one direction down the chain:

```
Internet       →  ALB SG        (port 80)
ALB SG         →  Frontend SG   (port 3000)
Frontend SG    →  Backend SG    (port 5000)
Backend SG     →  RDS SG        (port 5432)
Backend SG     →  ElastiCache SG (port 6379)
Bastion SG     →  RDS SG        (port 5432)
Your IP        →  Bastion SG    (port 22)
```

---

## Connecting to RDS

RDS is in a private subnet and has no public access. Use the bastion host to SSH tunnel in:

```bash
# Open the tunnel (keep this terminal running)
ssh -L 5432:<rds-endpoint>:5432 ec2-user@<bastion-ip> \
  -i ~/.ssh/shopnow-bastion.pem -N

# In a new terminal, connect with psql
psql -h localhost -U shopnow -d shopnow
```

Replace `<rds-endpoint>` and `<bastion-ip>` with the values from `terraform output`.

---

## CI/CD — Jenkins Pipeline

### Stages

```
push to main
    │
    ├── Test (parallel)
    │     ├── Backend tests  (npm ci + jest)
    │     └── Frontend tests (npm ci + jest)
    │
    ├── ECR Login
    │     aws ecr get-login-password | docker login
    │
    ├── Build & Push (parallel)
    │     ├── docker build frontend → push to ECR
    │     └── docker build backend  → push to ECR
    │     (tagged with git SHA + :latest)
    │
    ├── Deploy Backend
    │     Register new task definition revision → update ECS service → wait stable
    │
    ├── Deploy Frontend
    │     Register new task definition revision → update ECS service → wait stable
    │
    └── Verify
          Poll ALB /health until HTTP 200
```

### Jenkins setup (one-time)

**1. Add AWS credentials**
```
Manage Jenkins → Credentials → Global → Add Credentials (×2)

Kind: Secret text | ID: shopnow-aws-key-id     | Secret: <jenkins_access_key_id>
Kind: Secret text | ID: shopnow-aws-secret-key | Secret: <jenkins_secret_access_key>
```

**2. Set ALB DNS global env var**
```
Manage Jenkins → System → Global properties → Environment variables

Name: ALB_DNS   Value: <alb_dns_name from terraform output>
```

**3. Create pipeline job**
```
New Item → shopnow → Pipeline → OK

Pipeline:
  Definition: Pipeline script from SCM
  SCM: Git
  Repository URL: https://github.com/Furaha-Justine/microservices-lab.git
  Branch: */main
  Script Path: Jenkinsfile
```

---

## ECS Services

| | Frontend | Backend |
|---|---|---|
| CPU | 256 units (0.25 vCPU) | 512 units (0.5 vCPU) |
| Memory | 512 MB | 1024 MB |
| Desired tasks | 2 | 2 |
| Auto-scale max | 10 | 10 |
| Scale-out at | CPU ≥ 70% | CPU ≥ 70% |
| Log group | /ecs/shopnow/frontend | /ecs/shopnow/backend |
| Network | private subnets, no public IP | private subnets, no public IP |

ECS circuit breaker is enabled on both services — a failed deployment automatically rolls back to the previous task definition revision.

---

## Service Connect

The frontend reaches the backend using `http://backend:5000` — no hardcoded IPs.

AWS Service Connect registers the backend service under the `shopnow.local` Cloud Map namespace. When a backend task starts, ECS registers its IP. When it stops, ECS deregisters it. The frontend always resolves `backend` to a healthy task.

---

## Monitoring

```bash
# Live logs
aws logs tail /ecs/shopnow/backend  --follow --format short
aws logs tail /ecs/shopnow/frontend --follow --format short

# Service health
aws ecs describe-services \
  --cluster shopnow-cluster \
  --services shopnow-frontend shopnow-backend \
  --query 'services[].{Name:serviceName,Running:runningCount,Desired:desiredCount}' \
  --output table

# Prometheus metrics (from within VPC or bastion)
curl http://backend:5000/metrics
```

---

## Resiliency

To demonstrate ECS self-healing:

**Terminal A — watch availability:**
```bash
ALB=shopnow-alb-575861398.eu-west-1.elb.amazonaws.com
while true; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$ALB/api/products")
  echo "$(date '+%H:%M:%S')  $CODE"
  sleep 1
done
```

**Terminal B — stop a task:**
```bash
TASK=$(aws ecs list-tasks --cluster shopnow-cluster \
  --service-name shopnow-backend --query 'taskArns[0]' --output text)
aws ecs stop-task --cluster shopnow-cluster --task $TASK
```

ECS detects the task stopped, launches a replacement, and the ALB routes traffic to the surviving task. Terminal A shows no failed requests.

---

*ShopNow — ECS Fargate · RDS · ElastiCache · Jenkins · Terraform*
