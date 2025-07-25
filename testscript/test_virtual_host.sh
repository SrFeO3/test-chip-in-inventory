#!/bin/bash

source ./test_helper.sh

VIRTUAL_HOST_NAME="www.test"
ROUTING_CHAIN_NAME="test-chain" # 依存先リソース

VIRTUAL_HOST_JSON=$(cat <<EOF
{
  "name": "${VIRTUAL_HOST_NAME}",
  "title": "Test Virtual Host",
  "description": "A virtual host for testing purposes.",
  "subdomain": "test-subdomain",
  "routingChain": "urn:chip-in:routing-chain:${REALM_NAME}:${ROUTING_CHAIN_NAME}"
}
EOF
)

UPDATED_VIRTUAL_HOST_JSON=$(cat <<EOF
{
  "name": "${VIRTUAL_HOST_NAME}",
  "title": "Updated Test Virtual Host",
  "description": "An updated virtual host.",
  "subdomain": "test-subdomain",
  "routingChain": "urn:chip-in:routing-chain:${REALM_NAME}:${ROUTING_CHAIN_NAME}",
  "disabled": true
}
EOF
)

# --- Main Script ---
check_jq

step "P. Create prerequisite Realm and RoutingChain for VirtualHost Test"
# Realm
curl -s -X POST -H "Content-Type: application/json" -d '{"name": "'"${REALM_NAME}"'", "title": "VH Test Realm", "cacert": "cert", "signingKey": "a-very-long-signing-key"}' "${API_BASE_URL}/realms" > /dev/null || true
# RoutingChain
curl -s -X POST -H "Content-Type: application/json" -d '{"name": "'"${ROUTING_CHAIN_NAME}"'", "title": "Test Chain"}' "${API_BASE_URL}/realms/${REALM_NAME}/routing-chains" > /dev/null || true
ok "Prerequisites for VirtualHost test created or already exist."


step "VH1. Cleanup: Deleting virtual host '${VIRTUAL_HOST_NAME}' if it exists..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/virtual-hosts/${VIRTUAL_HOST_NAME}" > /dev/null || true
ok "Virtual host cleanup complete."

step "VH2. POST /realms/${REALM_NAME}/virtual-hosts - Adding a new virtual host"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -d "$VIRTUAL_HOST_JSON" "${API_BASE_URL}/realms/${REALM_NAME}/virtual-hosts")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to create virtual host. Expected 200, got $HTTP_CODE. Body: $BODY"
EXPECTED_BODY=$(echo "$VIRTUAL_HOST_JSON" | jq --arg realm "${REALM_NAME}" '. + {realm: $realm, disabled: false, certificate: []}' | jq -S '.')
ACTUAL_BODY=$(echo "$BODY" | jq -S '.')
[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Created virtual host response body does not match.\nExpected: $EXPECTED_BODY\nGot:      $ACTUAL_BODY"
ok "Virtual host created successfully."

step "VH3. GET /realms/${REALM_NAME}/virtual-hosts/${VIRTUAL_HOST_NAME} - Retrieving the created virtual host"
BODY=$(curl -s "${API_BASE_URL}/realms/${REALM_NAME}/virtual-hosts/${VIRTUAL_HOST_NAME}")
ACTUAL_BODY=$(echo "$BODY" | jq -S '.')
[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Retrieved virtual host does not match created one."
ok "Retrieved virtual host matches."

step "VH4. PUT /realms/${REALM_NAME}/virtual-hosts - Updating the virtual host"
RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" -d "$UPDATED_VIRTUAL_HOST_JSON" "${API_BASE_URL}/realms/${REALM_NAME}/virtual-hosts")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to update virtual host. Expected 200, got $HTTP_CODE."
ok "Virtual host updated successfully."

step "VH5. DELETE /realms/${REALM_NAME}/virtual-hosts/${VIRTUAL_HOST_NAME} - Deleting the virtual host"
RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/virtual-hosts/${VIRTUAL_HOST_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to delete virtual host. Expected 200, got $HTTP_CODE"
ok "Virtual host deleted successfully."

step "VH6. GET /realms/${REALM_NAME}/virtual-hosts/${VIRTUAL_HOST_NAME} - Verifying deletion"
RESPONSE=$(curl -s -w "\n%{http_code}" "${API_BASE_URL}/realms/${REALM_NAME}/virtual-hosts/${VIRTUAL_HOST_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 404 ] || fail "Expected HTTP 404, but got $HTTP_CODE"
ok "Correctly received 404 Not Found for deleted virtual host."

step "Cleanup: Deleting prerequisite Realm and RoutingChain..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/routing-chains/${ROUTING_CHAIN_NAME}" > /dev/null || true
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}" > /dev/null || true
ok "Cleanup complete."

step "\e[1;32mAll VirtualHost API tests passed successfully!\e[0m"