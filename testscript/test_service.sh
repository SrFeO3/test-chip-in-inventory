#!/bin/bash

source ./test_helper.sh

HUB_NAME="test-hub" # 依存先リソース
SERVICE_NAME="test-service"

SERVICE_JSON=$(cat <<EOF
{
  "name": "${SERVICE_NAME}",
  "title": "Test Service",
  "realm": "${REALM_NAME}",
  "hubName": "${HUB_NAME}",
  "providers": ["provider1"],
  "consumers": ["consumer1"]
}
EOF
)

UPDATED_SERVICE_JSON=$(cat <<EOF
{
  "name": "${SERVICE_NAME}",
  "title": "Updated Test Service",
  "description": "An updated service.",
  "realm": "${REALM_NAME}",
  "hubName": "${HUB_NAME}",
  "providers": ["provider1", "provider2"],
  "consumers": ["consumer1", "consumer2"]
}
EOF
)

# --- Main Script ---
check_jq

step "P. Create prerequisite Realm and Hub for Service Test"
# Realm
curl -s -X POST -H "Content-Type: application/json" -d '{"name": "'"${REALM_NAME}"'", "title": "Service Test Realm", "cacert": "cert", "signingKey": "a-very-long-signing-key"}' "${API_BASE_URL}/realms" > /dev/null || true
# Hub
curl -s -X POST -H "Content-Type: application/json" -d '{"name": "'"${HUB_NAME}"'", "title": "Test Hub", "fqdn": "h.test", "serverCert": "c", "serverCertKey": "k"}' "${API_BASE_URL}/realms/${REALM_NAME}/hubs" > /dev/null || true
ok "Prerequisites for Service test created or already exist."

step "S1. Cleanup: Deleting service '${SERVICE_NAME}' if it exists..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/hubs/${HUB_NAME}/services/${SERVICE_NAME}" > /dev/null || true
ok "Service cleanup complete."

step "S2. POST /realms/${REALM_NAME}/hubs/${HUB_NAME}/services - Adding a new service"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -d "$SERVICE_JSON" "${API_BASE_URL}/realms/${REALM_NAME}/hubs/${HUB_NAME}/services")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to create service. Expected 200, got $HTTP_CODE. Body: $BODY"
ok "Service created successfully."

step "S3. GET /realms/${REALM_NAME}/hubs/${HUB_NAME}/services/${SERVICE_NAME} - Retrieving the created service"
BODY=$(curl -s "${API_BASE_URL}/realms/${REALM_NAME}/hubs/${HUB_NAME}/services/${SERVICE_NAME}")
ACTUAL_BODY=$(echo "$BODY" | jq 'del(.urn) | del(.hub)' | jq -S '.')
EXPECTED_BODY=$(echo "$SERVICE_JSON" | jq -S '.')
[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Retrieved service does not match created one."
ok "Retrieved service matches."

step "S4. PUT /realms/${REALM_NAME}/hubs/${HUB_NAME}/services - Updating the service"
RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" -d "$UPDATED_SERVICE_JSON" "${API_BASE_URL}/realms/${REALM_NAME}/hubs/${HUB_NAME}/services")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to update service. Expected 200, got $HTTP_CODE."
ok "Service updated successfully."

step "S5. DELETE /realms/${REALM_NAME}/hubs/${HUB_NAME}/services/${SERVICE_NAME} - Deleting the service"
RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/hubs/${HUB_NAME}/services/${SERVICE_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to delete service. Expected 200, got $HTTP_CODE"
ok "Service deleted successfully."

step "Cleanup: Deleting prerequisite Realm and Hub..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/hubs/${HUB_NAME}" > /dev/null || true
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}" > /dev/null || true
ok "Cleanup complete."

step "\e[1;32mAll Service API tests passed successfully!\e[0m"