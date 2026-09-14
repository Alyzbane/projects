#!/bin/bash
# Quick end-to-end check of the serverless stack running on LocalStack.
#
# Usage: ./scripts/localstack-smoke-test.sh
# Requires: lstk, curl, jq (optional, for pretty output)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(dirname "$SCRIPT_DIR")/terraform"

# `terraform output` only reads state, so plain terraform (no lstk wrapper,
# no provider override needed) works fine here even with -chdir.
REST_API_ID="$(terraform -chdir="$TF_DIR" output -raw rest_api_id)"

API_BASE="http://localhost:4566/restapis/${REST_API_ID}/prod/_user_request_"
echo "==> API_BASE = $API_BASE"

echo "==> Seeding test data (POST /simulate)"
curl -sf -X POST "$API_BASE/simulate" -H 'Content-Type: application/json' -d '{"players": 10}' | (jq . 2>/dev/null || cat)
echo

echo "==> Fetching leaderboard (GET /leaderboard)"
curl -sf "$API_BASE/leaderboard?period=all-time&limit=10" | (jq . 2>/dev/null || cat)
echo

echo "==> Done. If both calls returned JSON above, DynamoDB + Lambda + API Gateway are wired up correctly."
