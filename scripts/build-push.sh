#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# scripts/build-push.sh
# Builds and pushes frontend and backend images to ECR.
# Usage: ./scripts/build-push.sh [TAG]
# If TAG is omitted, uses git SHA short + date.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

REGION="${AWS_REGION:-eu-west-1}"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
PROJECT="shopnow"
TAG="${1:-$(date +%Y%m%d)-$(git rev-parse --short HEAD 2>/dev/null || echo manual)}"

GREEN='\033[0;32m'; NC='\033[0m'
ok() { echo -e "${GREEN}✓ $*${NC}"; }

echo "=== ShopNow Build & Push ==="
echo "Registry : $REGISTRY"
echo "Tag      : $TAG"
echo ""

# ── ECR Login ─────────────────────────────────────────────────
echo "Logging in to ECR..."
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$REGISTRY"
ok "ECR login successful"

# ── Build Frontend ─────────────────────────────────────────────
echo ""
echo "Building frontend..."
docker build \
  --target production \
  --tag "${REGISTRY}/${PROJECT}/frontend:${TAG}" \
  --tag "${REGISTRY}/${PROJECT}/frontend:latest" \
  --cache-from "${REGISTRY}/${PROJECT}/frontend:latest" \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  ./frontend
ok "Frontend image built"

echo "Pushing frontend..."
docker push "${REGISTRY}/${PROJECT}/frontend:${TAG}"
docker push "${REGISTRY}/${PROJECT}/frontend:latest"
ok "Frontend pushed: ${TAG}"

# ── Build Backend ──────────────────────────────────────────────
echo ""
echo "Building backend..."
docker build \
  --target production \
  --tag "${REGISTRY}/${PROJECT}/backend:${TAG}" \
  --tag "${REGISTRY}/${PROJECT}/backend:latest" \
  --cache-from "${REGISTRY}/${PROJECT}/backend:latest" \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  ./backend
ok "Backend image built"

echo "Pushing backend..."
docker push "${REGISTRY}/${PROJECT}/backend:${TAG}"
docker push "${REGISTRY}/${PROJECT}/backend:latest"
ok "Backend pushed: ${TAG}"

echo ""
echo "=== Done ==="
echo "Frontend : ${REGISTRY}/${PROJECT}/frontend:${TAG}"
echo "Backend  : ${REGISTRY}/${PROJECT}/backend:${TAG}"
echo ""
echo "To deploy to ECS:"
echo "  ./scripts/deploy-ecs.sh $TAG"
