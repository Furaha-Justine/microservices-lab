#!/usr/bin/env bash
# scripts/resiliency-test.sh — ECS Fargate resiliency test
# Kills one backend task and measures automatic recovery.
# Usage: ./scripts/resiliency-test.sh [CLUSTER] [SERVICE]
set -euo pipefail

CLUSTER="${1:-shopnow-ecs}"
SERVICE="${2:-shopnow-backend}"
REGION="${AWS_REGION:-us-east-1}"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

ok()   { echo -e "${GREEN}$(date '+%H:%M:%S')  ✓ $*${NC}"; }
fail() { echo -e "${RED}$(date '+%H:%M:%S')  ✗ $*${NC}"; }
warn() { echo -e "${YELLOW}$(date '+%H:%M:%S')  ⚠ $*${NC}"; }
log()  { echo "$(date '+%H:%M:%S')  $*"; }

echo "=== ECS Fargate Resiliency Test ==="
log "Cluster : $CLUSTER  |  Service : $SERVICE"

# Detect ALB
ALB=$(aws elbv2 describe-load-balancers \
  --names "${CLUSTER%-ecs}-ecs-alb" \
  --query 'LoadBalancers[0].DNSName' \
  --output text --region "$REGION" 2>/dev/null || echo "")
[[ -z "$ALB" ]] && ALB="${ALB_URL:-localhost:3000}"
log "App URL : http://$ALB"

# Start background availability poller
(while true; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
    "http://$ALB/api/products" 2>/dev/null || echo "000")
  [[ "$CODE" == "200" ]] && echo "OK $(date '+%H:%M:%S')" || echo "FAIL $(date '+%H:%M:%S') HTTP_${CODE}"
  sleep 1
done) > /tmp/shopnow_poll.log &
POLL_PID=$!
log "Availability poller started (PID $POLL_PID)"
sleep 3

# Show current state
log "Current task counts:"
aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].{Running:runningCount,Desired:desiredCount,Pending:pendingCount}' \
  --output table --region "$REGION"

# Pick a task to kill
TASK=$(aws ecs list-tasks --cluster "$CLUSTER" \
  --service-name "$SERVICE" \
  --query 'taskArns[0]' --output text --region "$REGION")

if [[ "$TASK" == "None" || -z "$TASK" ]]; then
  fail "No running tasks found in $SERVICE"; kill $POLL_PID; exit 1
fi

warn "Killing task: ${TASK##*/}"
T_KILL=$(date +%s)
aws ecs stop-task --cluster "$CLUSTER" --task "$TASK" \
  --reason "Resiliency test $(date)" --region "$REGION" > /dev/null

# Poll until recovered
log "Waiting for recovery..."
for i in $(seq 1 60); do
  sleep 2
  RUNNING=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].runningCount' --output text --region "$REGION")
  DESIRED=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].desiredCount' --output text --region "$REGION")
  log "  running=$RUNNING  desired=$DESIRED"
  if [[ "$RUNNING" -ge "$DESIRED" ]]; then
    T_RECOVER=$(date +%s)
    ok "Recovered in $(( T_RECOVER - T_KILL )) seconds"
    break
  fi
done

sleep 5
kill $POLL_PID 2>/dev/null || true

TOTAL=$(wc -l < /tmp/shopnow_poll.log)
FAILS=$(grep -c "^FAIL" /tmp/shopnow_poll.log 2>/dev/null || echo 0)
echo ""
log "=== Availability Results ==="
ok  "Successful polls : $(( TOTAL - FAILS )) / $TOTAL"
if [[ "$FAILS" -gt 0 ]]; then
  fail "Failed polls     : $FAILS — DOWNTIME DETECTED"
  grep "^FAIL" /tmp/shopnow_poll.log | head -5
else
  ok  "Failed polls     : 0 — ZERO DOWNTIME ✓"
fi
