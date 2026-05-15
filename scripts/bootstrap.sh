#!/usr/bin/env bash
# scripts/bootstrap.sh — one-time AWS setup for ECS Fargate deployment
# Usage: ./scripts/bootstrap.sh [AWS_REGION] [GITHUB_ORG/REPO]
set -euo pipefail

REGION="${1:-us-east-1}"
GITHUB_REPO="${2:-your-org/shopnow}"
PROJECT="shopnow"
BUCKET="${PROJECT}-terraform-state"
DYNAMO_TABLE="${PROJECT}-terraform-locks"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

echo "=== ShopNow Bootstrap (ECS Fargate) ==="
echo "Region  : $REGION  |  Account : $ACCOUNT  |  Repo : $GITHUB_REPO"
echo ""

echo "[1/5] S3 state bucket..."
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "  ✓ $BUCKET already exists"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    $([[ "$REGION" != "us-east-1" ]] && echo "--create-bucket-configuration LocationConstraint=$REGION" || echo "")
  aws s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
  echo "  ✓ Created $BUCKET"
fi

echo "[2/5] DynamoDB lock table..."
if aws dynamodb describe-table --table-name "$DYNAMO_TABLE" --region "$REGION" 2>/dev/null; then
  echo "  ✓ $DYNAMO_TABLE already exists"
else
  aws dynamodb create-table --table-name "$DYNAMO_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST --region "$REGION"
  echo "  ✓ Created $DYNAMO_TABLE"
fi

echo "[3/5] GitHub OIDC provider..."
OIDC_ARN="arn:aws:iam::${ACCOUNT}:oidc-provider/token.actions.githubusercontent.com"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" 2>/dev/null; then
  echo "  ✓ OIDC provider already exists"
else
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
  echo "  ✓ Created OIDC provider"
fi

echo "[4/5] GitHub Actions IAM role..."
ROLE_NAME="github-actions-shopnow"
TRUST=$(cat <<TRUST
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::${ACCOUNT}:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPO}:*" }
    }
  }]
}
TRUST
)
if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
  echo "  ✓ Role $ROLE_NAME already exists"
else
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST"
  for POLICY in AmazonECS_FullAccess AmazonEC2ContainerRegistryFullAccess \
                ElasticLoadBalancingFullAccess AmazonVPCFullAccess; do
    aws iam attach-role-policy --role-name "$ROLE_NAME" \
      --policy-arn "arn:aws:iam::aws:policy/$POLICY"
  done
  echo "  ✓ Created role $ROLE_NAME"
fi

echo "[5/5] ECR repositories..."
for REPO in "${PROJECT}/frontend" "${PROJECT}/backend"; do
  if aws ecr describe-repositories --repository-names "$REPO" --region "$REGION" 2>/dev/null; then
    echo "  ✓ ECR $REPO already exists"
  else
    aws ecr create-repository --repository-name "$REPO" --region "$REGION" \
      --image-scanning-configuration scanOnPush=true
    echo "  ✓ Created ECR $REPO"
  fi
done

echo ""
echo "=== Bootstrap Complete ==="
echo "Next: add AWS_ACCOUNT_ID=$ACCOUNT as a GitHub Actions secret"
echo "Then: cd infrastructure/terraform/environments/prod && terraform init"
