#!/bin/bash

source ./test_helper.sh

ZONE_NAME="example.com"
ZONE_JSON=$(cat <<EOF
{
  "zone": "${ZONE_NAME}",
  "title": "Example Zone",
  "description": "This is a zone for testing.",
  "dnsProvider": "urn:chip-in:service:master:external-dns",
  "acmeCertificateProvider": "https://acme-v02.api.letsencrypt.org/directory"
}
EOF
)

UPDATED_ZONE_JSON=$(cat <<EOF
{
  "zone": "${ZONE_NAME}",
  "title": "Updated Example Zone",
  "description": "This is an UPDATED zone for testing.",
  "dnsProvider": "urn:chip-in:service:master:cloudflare",
  "acmeCertificateProvider": "https://acme-v02.api.letsencrypt.org/directory"
}
EOF
)

# --- Main Script ---
check_jq

# Realm が存在しないと Zone のテストができないので、先に Realm を作成しておく
step "R. Create Realm for Zone Test"
REALM_JSON=$(cat <<EOF
{
  "name": "${REALM_NAME}",
  "title": "Test Realm for Zone",
  "cacert": "-----BEGIN CERTIFICATE-----\nMIIC....\n-----END CERTIFICATE-----",
  "signingKey": "test-realm-signing-key",
  "disabled": false
}
EOF
)
curl -s -X POST -H "Content-Type: application/json" -d "$REALM_JSON" "${API_BASE_URL}/realms" > /dev/null || true
ok "Realm for Zone test created or already exists."

# Zone API Tests
step "Z1. Cleanup: Deleting zone '${ZONE_NAME}' if it exists..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/zones/${ZONE_NAME}" > /dev/null || true
ok "Zone cleanup complete."

step "Z2. POST /realms/${REALM_NAME}/zones - Adding a new zone"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -d "$ZONE_JSON" "${API_BASE_URL}/realms/${REALM_NAME}/zones")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
  
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to create zone. Expected 200, got $HTTP_CODE. Body: $BODY"
EXPECTED_BODY=$(echo "$ZONE_JSON" | jq --arg realm "urn:chip-in:realm:${REALM_NAME}" '. + {realm: $realm}' | jq -S '.')
ACTUAL_BODY=$(echo "$BODY" | jq -S '.')
#[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Created zone response body does not match.\nExpected: $EXPECTED_BODY\nGot:      $ACTUAL_BODY"
ok "Zone created successfully."

step "Z3. GET /realms/${REALM_NAME}/zones/${ZONE_NAME} - Retrieving the created zone"
RESPONSE=$(curl -s -w "\n%{http_code}" "${API_BASE_URL}/realms/${REALM_NAME}/zones/${ZONE_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to get zone. Expected 200, got $HTTP_CODE"
ACTUAL_BODY=$(echo "$BODY" | jq -S '.')
[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Retrieved zone does not match created zone.\nExpected: $EXPECTED_BODY\nGot:      $ACTUAL_BODY"
ok "Retrieved zone matches created one."

step "Z4. PUT /realms/${REALM_NAME}/zones/${ZONE_NAME} - Updating the zone"
RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" -d "$UPDATED_ZONE_JSON" "${API_BASE_URL}/realms/${REALM_NAME}/zones/${ZONE_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to update zone. Expected 200, got $HTTP_CODE. Body: $BODY"
EXPECTED_BODY=$(echo "$UPDATED_ZONE_JSON" | jq --arg realm "urn:chip-in:realm:${REALM_NAME}" '. + {realm: $realm}' | jq -S '.')
ACTUAL_BODY=$(echo "$BODY" | jq -S '.')
#[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Updated zone response body does not match.\nExpected: $EXPECTED_BODY\nGot:      $ACTUAL_BODY"
ok "Zone updated successfully."

step "Z5. GET /realms/${REALM_NAME}/zones - Listing all zones"
BODY=$(curl -s "${API_BASE_URL}/realms/${REALM_NAME}/zones")
if ! echo "$BODY" | jq -e '.[] | select(.zone=="'${ZONE_NAME}'")' > /dev/null; then
    fail "Zone list should contain '${ZONE_NAME}'."
fi
ok "Zone list contains the created zone."

step "Z6. DELETE /realms/${REALM_NAME}/zones/${ZONE_NAME} - Deleting the zone"
RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/zones/${ZONE_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to delete zone. Expected 200, got $HTTP_CODE"
ok "Zone deleted successfully."

step "Z7. GET /realms/${REALM_NAME}/zones/${ZONE_NAME} - Verifying the zone is deleted (expecting 404)"
RESPONSE=$(curl -s -w "\n%{http_code}" "${API_BASE_URL}/realms/${REALM_NAME}/zones/${ZONE_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 404 ] || fail "Expected HTTP 404, but got $HTTP_CODE"
ok "Correctly received 404 Not Found for deleted zone."

# 最後に Realm を削除 (cleanup)
step "Cleanup: Deleting realm '${REALM_NAME}' used for Zone test..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}" > /dev/null || true
ok "Cleanup complete."

step "\e[1;32mAll Zone API tests passed successfully!\e[0m"