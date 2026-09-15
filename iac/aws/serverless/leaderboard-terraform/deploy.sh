#!/bin/bash
# One-shot deploy: provisions everything with Terraform, then pushes the
# frontend files to the EC2 dashboard host.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"

echo "==> terraform init"
terraform -chdir="$TF_DIR" init -input=false

echo "==> terraform apply"
terraform -chdir="$TF_DIR" apply -auto-approve

echo "==> Deploying frontend (/www files) to the dashboard host"
"$ROOT_DIR/scripts/setup-www.sh"

API_URL="$(terraform -chdir="$TF_DIR" output -raw api_invoke_url)"
DASH_IP="$(terraform -chdir="$TF_DIR" output -raw dashboard_public_ip)"

cat <<EOF

==================================================
 Deploy complete
--------------------------------------------------
 API:       $API_URL
 Dashboard: http://$DASH_IP
==================================================
EOF
