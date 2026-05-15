#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# scripts/deploy-ecs.sh
# Forces a new deployment on ECS Fargate for both services.
# Usage: ./scripts/deploy-ecs.sh [IMAGE_TAG] [CLUSTER]
# ─────────────────────────────────────────────────────────────
set -euo pipefail

TAG="${1:-latest}"
CLUSTER="${2:-shopnow-ecs}"
REGION="${AWS_REGION:-us-east-1}"
GREEN='\033[0;32m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓ $*${NC}"; }

echo "=== ECS Deploy ==="
echo "Cluster : $CLUSTER"
echo "Tag     : $TAG"
echo ""

deploy_service() {
  local SERVICE="$1"
  echo "Deploying $SERVICE..."
  aws ecs update-service \
    --cluster "$CLUSTER" \
    --service "$SERVICE" \
    --force-new-deployment \
    --region "$REGION" > /dev/null
  echo "Waiting for $SERVICE to stabilise..."
  aws ecs wait services-stable \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION"
  ok "$SERVICE deployed and stable"
}

deploy_service "shopnow-backend"
deploy_service "shopnow-frontend"

echo ""
echo "=== Verification ==="
aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services shopnow-frontend shopnow-backend \
  --query 'services[].{Name:serviceName,Running:runningCount,Desired:desiredCount,Status:status}' \
  --output table \
  --region "$REGION"

ALB=$(aws elbv2 describe-load-balancers \
  --names "${CLUSTER%-ecs}-ecs-alb" \
  --query 'LoadBalancers[0].DNSName' \
  --output text --region "$REGION" 2>/dev/null || echo "unknown")
echo ""
ok "Deployment complete! App URL: http://$ALB"
