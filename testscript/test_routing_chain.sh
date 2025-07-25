#!/bin/bash

source ./test_helper.sh

ROUTING_CHAIN_NAME="test-chain"

ROUTING_CHAIN_JSON=$(cat <<EOF
{
  "name": "${ROUTING_CHAIN_NAME}",
  "title": "Test Routing Chain",
  "description": "A routing chain for testing.",
  "rules": [
    {
      "match": "request.path == \\"/test\\"",
      "action": {
        "type": "proxy",
        "target": "urn:chip-in:service:test:test-service"
      }
    }
  ]
}
EOF
)

UPDATED_ROUTING_CHAIN_JSON=$(cat <<EOF
{
  "name": "${ROUTING_CHAIN_NAME}",
  "title": "Updated Test Routing Chain",
  "description": "An updated routing chain for testing.",
   "rules": []
}
EOF
)

# --- Main Script ---
check_jq

step "P. Create prerequisite Realm for RoutingChain Test"
curl -s -X POST -H "Content-Type: application/json" -d '{"name": "'"${REALM_NAME}"'", "title": "RC Test Realm", "cacert": "cert", "signingKey": "a-very-long-signing-key"}' "${API_BASE_URL}/realms" > /dev/null || true
ok "Prerequisite Realm for RoutingChain test created or already exists."

step "RC1. Cleanup: Deleting routing chain '${ROUTING_CHAIN_NAME}' if it exists..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/routing-chains/${ROUTING_CHAIN_NAME}" > /dev/null || true
ok "Routing chain cleanup complete."

step "RC2. POST /realms/${REALM_NAME}/routing-chains - Adding a new routing chain"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -d "$ROUTING_CHAIN_JSON" "${API_BASE_URL}/realms/${REALM_NAME}/routing-chains")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to create routing chain. Expected 200, got $HTTP_CODE. Body: $BODY"
ok "Routing chain created successfully."

step "RC3. GET /realms/${REALM_NAME}/routing-chains/${ROUTING_CHAIN_NAME} - Retrieving the created routing chain"
BODY=$(curl -s "${API_BASE_URL}/realms/${REALM_NAME}/routing-chains/${ROUTING_CHAIN_NAME}")
ACTUAL_BODY=$(echo "$BODY" | jq 'del(.urn) | del(.realm)' | jq -S '.')
EXPECTED_BODY=$(echo "$ROUTING_CHAIN_JSON" | jq -S '.')
[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Retrieved routing chain does not match created one."
ok "Retrieved routing chain matches."

step "RC4. PUT /realms/${REALM_NAME}/routing-chains - Updating the routing chain"
RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" -d "$UPDATED_ROUTING_CHAIN_JSON" "${API_BASE_URL}/realms/${REALM_NAME}/routing-chains")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to update routing chain. Expected 200, got $HTTP_CODE."
ok "Routing chain updated successfully."

step "RC5. DELETE /realms/${REALM_NAME}/routing-chains/${ROUTING_CHAIN_NAME} - Deleting the routing chain"
RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/routing-chains/${ROUTING_CHAIN_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to delete routing chain. Expected 200, got $HTTP_CODE"
ok "Routing chain deleted successfully."

step "Cleanup: Deleting prerequisite Realm..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}" > /dev/null || true
ok "Cleanup complete."

step "\e[1;32mAll RoutingChain API tests passed successfully!\e[0m"