#!/bin/bash
set -euo pipefail

# CONFIGURATION
PACKER_DIR="./packer"
TF_DIR="."
TF_AMI_VAR_FILE="$TF_DIR/ami.auto.tfvars"
ENVIRONMENT="dev"

# SANITIZE GIT METADATA
GIT_COMMIT=$(git rev-parse --short HEAD | tr -cd '[:alnum:]' | cut -c1-12)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD | tr -cd '[:alnum:]' | cut -c1-12)
GIT_TAG=$(git describe --tags --always 2>/dev/null | tr -cd '[:alnum:]' | cut -c1-12)

echo "Git commit: $GIT_COMMIT"
echo "Git branch: $GIT_BRANCH"
echo "Git tag: $GIT_TAG"

# TERRAFORM INIT AND VALIDATE
terraform -chdir="$TF_DIR" init
terraform -chdir="$TF_DIR" validate

# FETCH EFS DNS FROM TERRAFORM OUTPUT
echo "Fetching EFS DNS from Terraform output..."
EFS_DNS=$(terraform -chdir="$TF_DIR" output -raw efs_dns_name 2>/dev/null | grep -oE 'fs-[a-z0-9]+\.efs\.[a-z0-9-]+\.amazonaws\.com' | head -n1)

echo "EFS DNS resolved to: [$EFS_DNS]"

if [[ -z "$EFS_DNS" ]]; then
  echo "ERROR: EFS DNS is empty or malformed. Exiting."
  exit 1
fi

echo "EFS DNS: $EFS_DNS"

# DEBUG: SANITIZED AMI SUFFIX
echo "Final sanitized AMI suffix: [$GIT_COMMIT]"

# PACKER BUILD

# Compute outputs BEFORE changing dirs
SUBNET_ID=$(terraform -chdir="$TF_DIR" output -raw subnet_for_packer)
SG_ID=$(terraform -chdir="$TF_DIR" output -raw packer_sg_id)

cd "$PACKER_DIR"

AMI_OUTPUT=$(packer build -machine-readable \
  -var "efs_dns_name=$EFS_DNS" \
  -var "git_commit=$GIT_COMMIT" \
  -var "git_branch=$GIT_BRANCH" \
  -var "git_tag=$GIT_TAG" \
  -var "environment=$ENVIRONMENT" \
  -var "subnet_id=$SUBNET_ID" \
  -var "security_group_id=$SG_ID" \
  ./ | tee packer.log)

cd -

# PARSE AMI ID
AMI_ID=$(echo "$AMI_OUTPUT" | grep 'artifact,0,id' | cut -d, -f6 | cut -d: -f2)

if [[ -z "$AMI_ID" ]]; then
  echo "Failed to extract AMI ID"
  exit 1
fi

echo "AMI ID built: $AMI_ID"

# UPDATE TF VAR FILE
echo "ami_id = \"$AMI_ID\"" > "$TF_AMI_VAR_FILE"

