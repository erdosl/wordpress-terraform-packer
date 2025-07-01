#!/bin/bash
exec > >(tee /var/log/github-runner-bootstrap.log|logger -t user-data -s 2>/dev/console) 2>&1
set -euxo pipefail

echo "[BOOTSTRAP] GitHub Actions Runner setup started..."

# --- Wait for network ---
echo "[NETWORK] Waiting for network connectivity..."
for i in {1..60}; do
  if curl -s http://amazon.com >/dev/null; then
    echo "[NETWORK] Network is up."
    break
  fi
  echo "[NETWORK] Not ready yet... retrying..."
  sleep 10
done

# Final network check
if ! curl -s http://amazon.com >/dev/null; then
  echo "[ERROR] Network not reachable after multiple attempts. Exiting."
  exit 1
fi

# --- Install Required Packages ---
echo "[ACTION] Installing jq, tar, gzip, SSM & CloudWatch agents..."
dnf update -y
dnf install -y jq tar zip gzip nodejs python3.9 amazon-ssm-agent amazon-cloudwatch-agent

# --- GitHub Setup Info ---

GH_OWNER="__GH_OWNER__"
GH_REPO="__GH_REPO__"
RUNNER_VERSION="$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')"
ARCH="__ARCH__"
RUNNER_USER="__RUNNER_USER__"
RUNNER_HOME="/home/${RUNNER_USER}"
RUNNER_DIR="${RUNNER_HOME}/actions-runner"
PARAM_NAME="/github/actions/runner-pat"

# --- Get AWS Region Securely via IMDSv2 ---
echo "[ACTION] Fetching AWS region from instance metadata..."
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)

echo "[INFO] TOKEN=${TOKEN}"
echo "[INFO] AWS_REGION=${AWS_REGION}"

if [ -z "$AWS_REGION" ]; then
  AWS_REGION="eu-west-2" # TODO: remove fallback region
  echo "[WARN] Metadata failed; using fallback region: $AWS_REGION"
else
  echo "[INFO] Detected AWS region: $AWS_REGION"
fi

echo "[INFO] GH_OWNER=${GH_OWNER}"
echo "[INFO] GH_REPO=${GH_REPO}"
echo "[INFO] RUNNER_VERSION=${RUNNER_VERSION}"
echo "[INFO] ARCH=${ARCH}"
echo "[INFO] RUNNER_DIR=${RUNNER_DIR}"
echo "[INFO] SSM PARAM_NAME=${PARAM_NAME}"

# --- Fetch IAM credentials ---
echo "[ACTION] Fetching IAM credentials using IMDSv2..."

# Request a metadata token
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Fetch IAM role name
ROLE_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/)

if [ -z "$ROLE_NAME" ]; then
  echo "[ERROR] No IAM role attached to instance. Exiting."
  exit 1
fi
echo "[INFO] IAM role: $ROLE_NAME"

# Fetch credentials JSON
IAM_JSON=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/${ROLE_NAME})

# Extract values
AWS_ACCESS_KEY_ID=$(echo "$IAM_JSON" | jq -r .AccessKeyId)
AWS_SECRET_ACCESS_KEY=$(echo "$IAM_JSON" | jq -r .SecretAccessKey)
AWS_SESSION_TOKEN=$(echo "$IAM_JSON" | jq -r .Token)
AWS_EXPIRATION=$(echo "$IAM_JSON" | jq -r .Expiration)

# Validate
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ "$AWS_ACCESS_KEY_ID" == "null" ]; then
  echo "[ERROR] Failed to retrieve IAM credentials. Exiting."
  exit 1
fi

echo "[INFO] IAM credentials retrieved. Expires at: $AWS_EXPIRATION"

# --- Start agents after IAM is ready ---
echo "[ACTION] Enabling & starting SSM and CloudWatch agents..."
systemctl enable amazon-ssm-agent amazon-cloudwatch-agent
systemctl restart amazon-ssm-agent amazon-cloudwatch-agent


# --- Fetch GitHub PAT from SSM ---
echo "[ACTION] Fetching GitHub PAT from SSM..."

echo "[SSM] Get and decrypt GitHub PAT from AWS Parameter Store"
GITHUB_PAT=$(
  (export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
   export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
   export AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN"
   aws ssm get-parameter \
     --region="$AWS_REGION" \
     --name="$PARAM_NAME" \
     --with-decryption \
     --query "Parameter.Value" \
     --output text)
)

if [ -z "$GITHUB_PAT" ]; then
  echo "[ERROR] Failed to retrieve GitHub PAT. Exiting."
  exit 1
fi

echo "[INFO] GitHub PAT retrieved successfully (length: ${#GITHUB_PAT})"

# --- Request GitHub Runner Registration Token ---
echo "[ACTION] Requesting runner registration token from GitHub API..."

GITHUB_RUNNER_TOKEN=$(curl -s -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_PAT" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/actions/runners/registration-token \
  | jq -r .token)

if [ -z "$GITHUB_RUNNER_TOKEN" ] || [ "$GITHUB_RUNNER_TOKEN" == "null" ]; then
  echo "[ERROR] Failed to retrieve GitHub runner registration token. Exiting."
  exit 1
fi

# --- Create and Own Runner Directory ---
echo "[ACTION] Preparing runner directory: $RUNNER_DIR"
mkdir -p "$RUNNER_DIR"
chown ec2-user:ec2-user "$RUNNER_DIR"

# --- Bootstrap GitHub Runner ---
echo "[ACTION] Bootstrapping runner as $RUNNER_USER ..."
su - "$RUNNER_USER" -c "
  set -euxo pipefail
  cd $RUNNER_DIR
  echo '[RUNNER] Downloading GitHub runner...'
  curl -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz
  echo '[RUNNER] Extracting...'
  tar xzf runner.tar.gz

  echo '[RUNNER] Installing dependencies...'
  sudo dnf install -y libicu openssl-libs krb5-libs libunwind lttng-ust zlib || true
  sudo ./bin/installdependencies.sh || true

  echo '[RUNNER] Configuring runner...'
  ./config.sh --url https://github.com/${GH_OWNER}/${GH_REPO} \
              --token ${GITHUB_RUNNER_TOKEN} \
              --labels self-hosted,linux,ci \
              --unattended

  echo '[RUNNER] Installing and starting runner service...'
  sudo ./svc.sh install
  sudo ./svc.sh start
"

echo "[BOOTSTRAP] GitHub Actions Runner setup complete."
