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
API_BASE="$(terraform -chdir="$TF_DIR" output -raw api_invoke_url)"
HOST_IP="$(terraform -chdir="$TF_DIR" output -raw dashboard_public_ip)"
KEY_PATH="$(terraform -chdir="$TF_DIR" output -raw ssh_private_key_path)"
# ssh_private_key_path is relative to the terraform/ dir
KEY_PATH="$TF_DIR/$KEY_PATH"

if [[ -z "$API_BASE" || -z "$HOST_IP" ]]; then
  echo "Could not read Terraform outputs. Did 'terraform apply' finish successfully?" >&2
  exit 1
fi

echo "    API_BASE = $API_BASE"
echo "    HOST_IP  = $HOST_IP"

echo "==> Rendering env.js"
sed "s|__API_BASE__|${API_BASE}|g" "$WWW_DIR/env.js.tpl" > "$WORK_DIR/env.js"
cp "$WWW_DIR/index.html" "$WORK_DIR/index.html"

SSH_OPTS=(-i "$KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)

echo "==> Waiting for SSH on $HOST_IP (instance may still be booting)"
for i in $(seq 1 30); do
  if ssh "${SSH_OPTS[@]}" "ubuntu@$HOST_IP" "true" 2>/dev/null; then
    echo "    SSH is up"
    break
  fi
  if [[ "$i" -eq 30 ]]; then
    echo "Timed out waiting for SSH on $HOST_IP" >&2
    exit 1
  fi
  sleep 10
done

echo "==> Waiting for nginx (user_data) to finish installing"
for i in $(seq 1 18); do
  if ssh "${SSH_OPTS[@]}" "ubuntu@$HOST_IP" "command -v nginx" 2>/dev/null; then
    echo "    nginx is installed"
    break
  fi
  if [[ "$i" -eq 18 ]]; then
    echo "Timed out waiting for nginx to install via user_data" >&2
    exit 1
  fi
  sleep 10
done

echo "==> Copying www files to the dashboard host"
scp "${SSH_OPTS[@]}" "$WORK_DIR/index.html" "$WORK_DIR/env.js" "ubuntu@$HOST_IP:/tmp/"

echo "==> Installing files into /var/www/html and restarting nginx"
ssh "${SSH_OPTS[@]}" "ubuntu@$HOST_IP" bash -s <<'REMOTE'
set -e
sudo mv /tmp/index.html /tmp/env.js /var/www/html/
sudo rm -f /var/www/html/index.nginx-debian.html
sudo chown www-data:www-data /var/www/html/index.html /var/www/html/env.js
sudo systemctl restart nginx
REMOTE

echo "==> Done. Dashboard: http://$HOST_IP"