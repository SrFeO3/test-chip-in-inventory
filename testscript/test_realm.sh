#!/bin/bash

source ./test_helper.sh

# OpenAPIの仕様に基づいたRealmのJSONデータ
REALM_JSON=$(cat <<EOF
{
  "name": "${REALM_NAME}",
  "title": "Test Realm",
  "description": "This is a realm for testing.",
  "cacert": "-----BEGIN CERTIFICATE-----\nMIIC....\n-----END CERTIFICATE-----",
  "signingKey": "super-secret-key-for-testing-123",
  "sessionTimeout": 3600,
  "administrators": ["admin@test.com"],
  "disabled": false
}
EOF
)

UPDATED_REALM_JSON=$(cat <<EOF
{
  "name": "${REALM_NAME}",
  "title": "Updated Test Realm",
  "description": "This is an UPDATED realm for testing.",
  "cacert": "-----BEGIN CERTIFICATE-----\nMIIC....\n-----END CERTIFICATE-----",
  "signingKey": "super-secret-key-for-testing-123",
  "sessionTimeout": 7200,
  "administrators": ["admin@test.com", "another-admin@test.com"],
  "disabled": false
}
EOF
)

# --- Main Script ---
check_jq
step "0. Sanity Check: Verifying connection to API server"
if ! curl -fs -o /dev/null --max-time 5 "${API_BASE_URL}/realms"; then
    fail "Could not connect to the API server at ${API_BASE_URL}. Please ensure the server is running and accessible."
fi
ok "API server is responding."

step "1. Cleanup: Deleting realm '${REALM_NAME}' if it exists..."
curl -s -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}" > /dev/null || true
ok "Cleanup complete."

step "2. GET /realms - Listing all realms (should not contain '${REALM_NAME}')"
BODY=$(curl -s "${API_BASE_URL}/realms")
if echo "$BODY" | jq -e '.[] | select(.name=="'${REALM_NAME}'")' > /dev/null; then
    fail "Test realm '${REALM_NAME}' should not exist at the beginning."
fi
ok "Realm list is clean as expected."

step "3. POST /realms - Adding a new realm '${REALM_NAME}'"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -d "$REALM_JSON" "${API_BASE_URL}/realms")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to create realm. Expected 200, got $HTTP_CODE. Body: $BODY"
ok "Realm created successfully with status 200."

step "4. POST /realms - Trying to add an existing realm (expecting 409 Conflict)"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -d "$REALM_JSON" "${API_BASE_URL}/realms")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
[ "$HTTP_CODE" -eq 409 ] || fail "Expected HTTP 409, but got $HTTP_CODE"
ok "Correctly received 409 Conflict."

step "5. GET /realms/${REALM_NAME} - Retrieving the created realm"
RESPONSE=$(curl -s -w "\n%{http_code}" "${API_BASE_URL}/realms/${REALM_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to get realm. Expected 200, got $HTTP_CODE"
EXPECTED_BODY=$(echo "$REALM_JSON" | jq -S '.')
ACTUAL_BODY=$(echo "$BODY" | jq -S '.')
[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Retrieved realm does not match created realm.\nExpected: $EXPECTED_BODY\nGot:      $ACTUAL_BODY"
ok "Retrieved realm matches created one."

step "6. PUT /realms - Updating the realm '${REALM_NAME}'"
RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" -d "$UPDATED_REALM_JSON" "${API_BASE_URL}/realms")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
[ "$HTTP_CODE" -eq 200 ] || fail "Failed to update realm. Expected 200, got $HTTP_CODE. Body: $BODY"
EXPECTED_BODY=$(echo "$UPDATED_REALM_JSON" | jq -S '.')
ACTUAL_BODY=$(echo "$BODY" | jq -S '.')
[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Updated response body does not match.\nExpected: $EXPECTED_BODY\nGot:      $ACTUAL_BODY"
ok "Realm updated successfully."

step "7. GET /realms/${REALM_NAME} - Verifying the updated realm"
BODY=$(curl -s "${API_BASE_URL}/realms/${REALM_NAME}")
EXPECTED_BODY=$(echo "$UPDATED_REALM_JSON" | jq -S '.')
ACTUAL_BODY=$(echo "$BODY" | jq -S '.')
[ "$EXPECTED_BODY" == "$ACTUAL_BODY" ] || fail "Retrieved realm after update does not match.\nExpected: $EXPECTED_BODY\nGot:      $ACTUAL_BODY"

step "8. DELETE /realms/${REALM_NAME} - Deleting the realm"
RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "${API_BASE_URL}/realms/${REALM_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

[ "$HTTP_CODE" -eq 200 ] || fail "Failed to delete realm. Expected 200, got $HTTP_CODE"
ok "Realm deleted successfully."

# 9. 削除されたRealmを取得 (404 Not Foundを期待)
step "9. GET /realms/${REALM_NAME} - Verifying the realm is deleted (expecting 404)"
RESPONSE=$(curl -s -w "\n%{http_code}" "${API_BASE_URL}/realms/${REALM_NAME}")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

[ "$HTTP_CODE" -eq 404 ] || fail "Expected HTTP 404, but got $HTTP_CODE"
ok "Correctly received 404 Not Found."

step "\e[1;32mAll Realm API tests passed successfully!\e[0m"