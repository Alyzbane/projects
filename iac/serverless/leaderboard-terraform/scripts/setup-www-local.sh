#!/bin/bash

# Run this after `terraform apply`

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$ROOT_DIR/terraform"
WWW_DIR="$ROOT_DIR/www/html"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Reading Terraform outputs"
REST_API_ID="$(terraform -chdir="$TF_DIR" output -raw rest_api_id 2>/dev/null || true)"
INSTANCE_ID="$(terraform -chdir="$TF_DIR" output -raw dashboard_instance_id 2>/dev/null || true)"
AMI_ID="$(terraform -chdir="$TF_DIR" output -raw dashboard_ami_id 2>/dev/null || true)"

if [[ -z "$REST_API_ID" ]]; then
  echo "Error: Could not read rest_api_id from Terraform outputs." >&2
  exit 1
fi

API_BASE="http://localhost:4566/restapis/${REST_API_ID}/prod/_user_request_"
echo "    API_BASE    = $API_BASE"
echo "    INSTANCE_ID = $INSTANCE_ID"
echo "    AMI_ID      = $AMI_ID"

echo "==> Resolving Docker container from Terraform outputs"
CONTAINER_ID=""

# Find the EC2 instance's Docker container by matching the Instance ID returned by Terraform
# AMI ID returned by Terraform
if [[ -z "$CONTAINER_ID" && -n "$AMI_ID" ]]; then
  CONTAINER_ID=$(docker ps --format "{{.ID}}\t{{.Image}}" | grep "$AMI_ID" | awk '{print $1}' | head -n 1)
fi

# Fallback to any active LocalStack EC2 container
if [[ -z "$CONTAINER_ID" ]]; then
  CONTAINER_ID=$(docker ps --filter "name=i-" -q | head -n 1)
fi

if [[ -z "$CONTAINER_ID" ]]; then
  echo "Error: Could not find Docker container for Instance $INSTANCE_ID / AMI $AMI_ID" >&2
  exit 1
fi

echo "    Target Container ID = $CONTAINER_ID"

echo "==> Rendering env.js"
sed "s|__API_BASE__|${API_BASE}|g" "$WWW_DIR/env.js.tpl" > "$WORK_DIR/env.js"
cp "$WWW_DIR/index.html" "$WORK_DIR/index.html"

echo "==> Waiting for nginx (user_data) to finish installing"
for i in $(seq 1 18); do
  if ! docker exec "$CONTAINER_ID" command -v nginx &>/dev/null; then 
    echo "    nginx is installed"
    break
  fi
  if [[ "$i" -eq 18 ]]; then
    echo "Timed out waiting for nginx to install via user_data" >&2
    exit 1
  fi
  sleep 10
done

echo "==> Copying web files to container /var/www/html"
docker cp "$WORK_DIR/index.html" "$CONTAINER_ID:/var/www/html/index.html"
docker cp "$WORK_DIR/env.js" "$CONTAINER_ID:/var/www/html/env.js"

echo "==> Setting permissions and restarting nginx"
docker exec "$CONTAINER_ID" bash -c "
  rm -f /var/www/html/index.nginx-debian.html && \
  chown -R www-data:www-data /var/www/html/ && \
  (service nginx restart || systemctl restart nginx)
"

echo "==> Done. Frontend deployed to LocalStack container ($CONTAINER_ID)."