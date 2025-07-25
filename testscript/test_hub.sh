#!/bin/bash

source ./test_helper.sh

HUB_NAME="test-hub"

HUB_JSON=$(cat <<EOF
{
  "name": "${HUB_NAME}",
  "title": "Test Hub",
  "fqdn": "hub.test.local",
  "serverCert": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----",
  "serverCertKey": "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----"
}
EOF
)

UPDATED_HUB_JSON=$(cat <<EOF
{
  "name": "${HUB_NAME}",
  "title": "Updated Test Hub",
  "description": "An updated hub.",
  "fqdn": "hub.test.local",
  "serverCert": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----",
  "serverCertKey": "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----"
}
EOF
)

# --- Main Script ---
check_jq

step "P. Create prerequisite Realm for Hub Test"
curl -s -X POST -H "Content-Type: application/json" -d '{"name": "'"${REALM_NAME}"'", "title": "Hub Test Realm", "cacert": "cert", "signingKey": "a-very-long-signing-key"}' "${API_BASE_URL}/realms" > /dev/null || true
ok "Prerequisite Realm for Hub test created or already exists."

step "H1. Cleanup: Deleting hub '${HUB_NAME}' if it exists..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/hubs/${HUB_NAME}" > /dev/null || true
ok "Hub cleanup complete."

step "H2. POST /realms/${REALM_NAME}/hubs - Adding a new hub"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -d "$HUB_JSON" "${API_BASE_URL}/realms/${REALM_NAME}/hubs")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to create hub. Expected 200, got $HTTP_CODE. Body: $BODY"
ok "Hub created successfully."

step "H3. GET /realms/${REALM_NAME}/hubs/${HUB_NAME} - Retrieving the created hub"
BODY=$(curl -s "${API_BASE_URL}/realms/${REALM_NAME}/hubs/${HUB_NAME}")
ACTUAL_BODY=$(echo "$BODY" | jq 'del(.urn) | del(.realm)' | jq -S '.')
EXPECTED_BODY=$(echo "$HUB_JSON" | jq -S '.')
[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Retrieved hub does not match created one."
ok "Retrieved hub matches."

step "H4. PUT /realms/${REALM_NAME}/hubs - Updating the hub"
RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" -d "$UPDATED_HUB_JSON" "${API_BASE_URL}/realms/${REALM_NAME}/hubs")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to update hub. Expected 200, got $HTTP_CODE."
ok "Hub updated successfully."

step "H5. DELETE /realms/${REALM_NAME}/hubs/${HUB_NAME} - Deleting the hub"
RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/hubs/${HUB_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to delete hub. Expected 200, got $HTTP_CODE"
ok "Hub deleted successfully."

step "Cleanup: Deleting prerequisite Realm..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}" > /dev/null || true
ok "Cleanup complete."

step "\e[1;32mAll Hub API tests passed successfully!\e[0m"