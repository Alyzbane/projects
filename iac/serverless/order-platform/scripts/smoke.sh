#!/usr/bin/env bash
#
# smoke.sh — end-to-end sanity check for the Cognito M2M -> HTTP API flow on LocalStack.
#
# What it does, in order:
#   1. Pulls client id / secret / pool id / endpoints straight out of Terraform state
#      (never trust values copy-pasted from a console — always re-read from state).
#   2. Requests an access token from the deployed Cognito endpoint.
#   3. Calls the deployed HTTP API directly (bypassing CloudFront) with the token and
#      reports pass/fail.
#
# This script is intentionally LocalStack-only. Use smoke-aws.sh for real AWS.
# Requires terraform, curl, and jq.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"
TF="lstk terraform -chdir=${TF_DIR}"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$1"; }
die()  { fail "$1"; exit 1; }

command -v jq   >/dev/null 2>&1 || die "jq is required (brew install jq / apt install jq)"
command -v curl >/dev/null 2>&1 || die "curl is required"

# ------------------------------------------------------------------------------------
# Pull everything we need from Terraform outputs
# ------------------------------------------------------------------------------------
log "Reading Terraform outputs"

tf_out() {
  $TF output -raw "$1" 2>/dev/null || true
}

CLIENT_ID=$(tf_out cognito_client_id)
CLIENT_SECRET=$(tf_out cognito_client_secret)
SCOPES=$(tf_out cognito_scopes)
API_ID=$(tf_out api_gateway_id)
LOCALSTACK_URL="${LOCALSTACK_URL:-http://localhost.localstack.cloud:4566}"
TOKEN_URL="${LOCALSTACK_URL}/_aws/cognito-idp/oauth2/token"
API_URL="http://${API_ID}.execute-api.localhost.localstack.cloud:4566"

[ -n "$CLIENT_ID" ]     || die "cognito_client_id is empty — did you run 'make apply' first?"
[ -n "$CLIENT_SECRET" ] || die "cognito_client_secret is empty"
[ -n "$TOKEN_URL" ]     || die "token endpoint is empty — did you run 'make apply' first?"
[ -n "$API_URL" ]       || die "API URL is empty — did you run 'make apply' first?"
[ -n "$API_ID" ]         || die "api_gateway_id is empty — re-apply Terraform to create the new output"

echo "  client_id   : ${CLIENT_ID}"
echo "  token_url   : ${TOKEN_URL}"
echo "  scopes      : ${SCOPES}"
echo "  api_url     : ${API_URL}"

# ------------------------------------------------------------------------------------
# Request a token via client_credentials
# ------------------------------------------------------------------------------------
log "Requesting access token (client_credentials grant)"

TOKEN_RESPONSE=$(curl -sS -w '\n%{http_code}' \
  -X POST "$TOKEN_URL" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}" \
  --data-urlencode "scope=${SCOPES}")

HTTP_CODE=$(echo "$TOKEN_RESPONSE" | tail -n1)
BODY=$(echo "$TOKEN_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
  fail "Token request returned HTTP ${HTTP_CODE}"
  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
  die "Stopping — fix the token request before testing the API. Common causes: wrong endpoint, incorrect USE_LOCALSTACK setting, or a stale client secret."
fi

ACCESS_TOKEN=$(echo "$BODY" | jq -r '.access_token // empty')
[ -n "$ACCESS_TOKEN" ] || die "No access_token in response: $BODY"
ok "Got an access token"

# ------------------------------------------------------------------------------------
# Call the actual API with the token
# ------------------------------------------------------------------------------------
log "Calling GET ${API_URL}/orders with the token"

API_RESPONSE=$(curl -sS -w '\n%{http_code}' \
  -X GET "${API_URL}/orders" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}")

API_HTTP_CODE=$(echo "$API_RESPONSE" | tail -n1)
API_BODY=$(echo "$API_RESPONSE" | sed '$d')

echo "  HTTP ${API_HTTP_CODE}"
echo "$API_BODY" | jq . 2>/dev/null || echo "$API_BODY"

if [ "$API_HTTP_CODE" -ge 200 ] && [ "$API_HTTP_CODE" -lt 300 ]; then
  ok "API call succeeded — Cognito + JWT authorizer + integration are wired up correctly"
elif [ "$API_HTTP_CODE" == "401" ]; then
  fail "401 Unauthorized — the authorizer rejected the token. Re-check the issuer/audience output above."
elif [ "$API_HTTP_CODE" == "403" ]; then
  fail "403 Forbidden — token was valid but missing a required scope. Check 'scope' above against the route's authorization_scopes."
else
  fail "Unexpected status ${API_HTTP_CODE} — check the Lambda/integration itself, this is past the auth layer."
fi
