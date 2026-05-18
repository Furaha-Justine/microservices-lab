#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# bootstrap.sh — Run ONCE before your first `terraform init`
#
# Creates the S3 bucket and DynamoDB table that Terraform uses
# to store state and prevent concurrent runs.
#
# Usage:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh                        # uses defaults below
#   ./bootstrap.sh my-bucket us-west-2   # custom bucket + region
# ─────────────────────────────────────────────────────────────
set -euo pipefail

BUCKET="${1:-shopnow-terraform-state-445567114084}"
REGION="${2:-eu-west-1}"
TABLE="shopnow-terraform-locks"

echo "──────────────────────────────────────────────"
echo "  ShopNow Terraform Bootstrap"
echo "  Bucket : $BUCKET"
echo "  Region : $REGION"
echo "  Table  : $TABLE"
echo "──────────────────────────────────────────────"

# ── S3 bucket ─────────────────────────────────────────────────
echo ""
echo "→ Creating S3 bucket..."

if [ "$REGION" = "us-east-1" ]; then
  # us-east-1 does not accept a LocationConstraint
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" 2>/dev/null || echo "  (bucket already exists)"
else
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null \
    || echo "  (bucket already exists)"
fi

echo "→ Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

echo "→ Enabling server-side encryption..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

echo "→ Blocking all public access..."
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# ── DynamoDB table ────────────────────────────────────────────
echo ""
echo "→ Creating DynamoDB lock table..."
aws dynamodb create-table \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema             AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" 2>/dev/null || echo "  (table already exists)"

# ── Done ──────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────────"
echo "  Bootstrap complete. Next steps:"
echo ""
echo "  1. Copy the tfvars example:"
echo "     cp environments/prod/terraform.tfvars.example \\"
echo "        environments/prod/terraform.tfvars"
echo "     # then edit terraform.tfvars with your real values"
echo ""
echo "  2. Initialise Terraform:"
echo "     cd environments/prod"
echo "     terraform init"
echo ""
echo "  3. Preview what will be created:"
echo "     terraform plan"
echo ""
echo "  4. Apply:"
echo "     terraform apply"
echo ""
echo "  5. Get your Jenkins credentials:"
echo "     terraform output jenkins_access_key_id"
echo "     terraform output -raw jenkins_secret_access_key"
echo "──────────────────────────────────────────────"
