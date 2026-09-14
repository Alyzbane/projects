#!/bin/bash
# Destroys the AWS resources created by terraform apply.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"

terraform -chdir="$TF_DIR" destroy
rm -f "$ROOT_DIR"/leaderboard-key.pem