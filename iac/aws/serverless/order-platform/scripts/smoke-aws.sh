#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"
TF="terraform -chdir=${TF_DIR}"

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }

tf_out() {
  $TF output -raw "$1" 2>/dev/null || true
}

CLIENT_ID="$(tf_out cognito_client_id)"
CLIENT_SECRET="$(tf_out cognito_client_secret)"
TOKEN_URL="$(tf_out cognito_token_endpoint)"
SCOPES="$(tf_out cognito_scopes)"
API_URL="$(tf_out api_gateway_invoke_url)"

[ -n "$CLIENT_ID" ] || { echo "cognito_client_id is empty; run make apply first" >&2; exit 1; }
[ -n "$CLIENT_SECRET" ] || { echo "cognito_client_secret is empty" >&2; exit 1; }
[ -n "$TOKEN_URL" ] || { echo "cognito_token_endpoint is empty" >&2; exit 1; }
[ -n "$API_URL" ] || { echo "api_gateway_invoke_url is empty" >&2; exit 1; }

echo "Requesting an AWS Cognito client-credentials token..."
TOKEN_RESPONSE="$(curl -sS -w '\n%{http_code}' \
  -X POST "$TOKEN_URL" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}" \
  --data-urlencode "scope=${SCOPES}")"

HTTP_CODE="$(echo "$TOKEN_RESPONSE" | tail -n1)"
BODY="$(echo "$TOKEN_RESPONSE" | sed '$d')"
[ "$HTTP_CODE" = "200" ] || { echo "$BODY" | jq . 2>/dev/null || echo "$BODY"; exit 1; }

ACCESS_TOKEN="$(echo "$BODY" | jq -r '.access_token // empty')"
[ -n "$ACCESS_TOKEN" ] || { echo "No access_token in Cognito response" >&2; exit 1; }

echo "Calling ${API_URL}/orders..."
API_RESPONSE="$(curl -sS -w '\n%{http_code}' \
  -X GET "${API_URL}/orders" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}")"
API_HTTP_CODE="$(echo "$API_RESPONSE" | tail -n1)"
API_BODY="$(echo "$API_RESPONSE" | sed '$d')"
echo "$API_BODY" | jq . 2>/dev/null || echo "$API_BODY"

if [ "$API_HTTP_CODE" -ge 200 ] && [ "$API_HTTP_CODE" -lt 300 ]; then
  echo "AWS smoke test passed."
else
  echo "AWS API call failed with HTTP ${API_HTTP_CODE}." >&2
  exit 1
fi