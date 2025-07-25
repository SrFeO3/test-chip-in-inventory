#!/bin/bash

source ./test_helper.sh

ZONE_NAME="example.com"
SUBDOMAIN_NAME="www"

SUBDOMAIN_JSON=$(cat <<EOF
{
  "name": "${SUBDOMAIN_NAME}",
  "title": "Test Subdomain",
  "description": "A subdomain for testing purposes.",
  "destinationRealm": "urn:chip-in:realm:${REALM_NAME}"
}
EOF
)

UPDATED_SUBDOMAIN_JSON=$(cat <<EOF
{
  "name": "${SUBDOMAIN_NAME}",
  "title": "Updated Test Subdomain",
  "description": "An updated subdomain.",
  "destinationRealm": "urn:chip-in:realm:${REALM_NAME}",
  "shareCookie": true
}
EOF
)

# --- Main Script ---
check_jq

step "P. Create prerequisite Realm and Zone for Subdomain Test"
# Realm
curl -s -X POST -H "Content-Type: application/json" -d '{"name": "'"${REALM_NAME}"'", "title": "Subdomain Test Realm", "cacert": "cert", "signingKey": "a-very-long-signing-key"}' "${API_BASE_URL}/realms" > /dev/null || true
# Zone
curl -s -X POST -H "Content-Type: application/json" -d '{"zone": "'"${ZONE_NAME}"'", "title": "Test Zone"}' "${API_BASE_URL}/realms/${REALM_NAME}/zones" > /dev/null || true
ok "Prerequisites for Subdomain test created or already exist."


step "SD1. Cleanup: Deleting subdomain '${SUBDOMAIN_NAME}' if it exists..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/zones/${ZONE_NAME}/subdomains/${SUBDOMAIN_NAME}" > /dev/null || true
ok "Subdomain cleanup complete."

step "SD2. POST /realms/${REALM_NAME}/zones/${ZONE_NAME}/subdomains - Adding a new subdomain"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -d "$SUBDOMAIN_JSON" "${API_BASE_URL}/realms/${REALM_NAME}/zones/${ZONE_NAME}/subdomains")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to create subdomain. Expected 200, got $HTTP_CODE. Body: $BODY"

EXPECTED_FQDN="${SUBDOMAIN_NAME}.${ZONE_NAME}"
EXPECTED_ZONE_URN="urn:chip-in:zone:${REALM_NAME}:${ZONE_NAME}"
EXPECTED_BODY=$(echo "$SUBDOMAIN_JSON" | jq \
    --arg fqdn "$EXPECTED_FQDN" \
    --arg zone_urn "$EXPECTED_ZONE_URN" \
    '. + {fqdn: $fqdn, zone: $zone_urn, shareCookie: false}' | jq -S '.')
ACTUAL_BODY=$(echo "$BODY" | jq -S '.')
[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Created subdomain response body does not match.\nExpected: $EXPECTED_BODY\nGot:      $ACTUAL_BODY"
ok "Subdomain created successfully."

step "SD3. GET /realms/${REALM_NAME}/zones/${ZONE_NAME}/subdomains/${SUBDOMAIN_NAME} - Retrieving the created subdomain"
BODY=$(curl -s "${API_BASE_URL}/realms/${REALM_NAME}/zones/${ZONE_NAME}/subdomains/${SUBDOMAIN_NAME}")
ACTUAL_BODY=$(echo "$BODY" | jq -S '.')
[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Retrieved subdomain does not match created one."
ok "Retrieved subdomain matches."

step "SD4. PUT /realms/${REALM_NAME}/zones/${ZONE_NAME}/subdomains - Updating the subdomain"
RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" -d "$UPDATED_SUBDOMAIN_JSON" "${API_BASE_URL}/realms/${REALM_NAME}/zones/${ZONE_NAME}/subdomains")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to update subdomain. Expected 200, got $HTTP_CODE."
ok "Subdomain updated successfully."

step "SD5. DELETE /realms/${REALM_NAME}/zones/${ZONE_NAME}/subdomains/${SUBDOMAIN_NAME} - Deleting the subdomain"
RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/zones/${ZONE_NAME}/subdomains/${SUBDOMAIN_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to delete subdomain. Expected 200, got $HTTP_CODE"
ok "Subdomain deleted successfully."

step "SD6. GET /realms/${REALM_NAME}/zones/${ZONE_NAME}/subdomains/${SUBDOMAIN_NAME} - Verifying deletion"
RESPONSE=$(curl -s -w "\n%{http_code}" "${API_BASE_URL}/realms/${REALM_NAME}/zones/${ZONE_NAME}/subdomains/${SUBDOMAIN_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 404 ] || fail "Expected HTTP 404, but got $HTTP_CODE"
ok "Correctly received 404 Not Found for deleted subdomain."

step "Cleanup: Deleting prerequisite Realm and Zone..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}/zones/${ZONE_NAME}" > /dev/null || true
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}" > /dev/null || true
ok "Cleanup complete."

step "\e[1;32mAll Subdomain API tests passed successfully!\e[0m"