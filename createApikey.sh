assert() {
  if ! eval "$1"; then
    echo "Assertion failed: $2" >&2
    exit 1
  fi
}

HUB_ENT_TAG=$1


HUB_ENT_TAG=${HUB_ENT_TAG%-rhel}
echo "HUB_ENT_TAG: $HUB_ENT_TAG"

RAND_NAME=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 29)
RAND_NAME="$(tr -dc 'a-z' < /dev/urandom | head -c 1)$RAND_NAME"
# After installation, make the API request
API_BASE_URL="https://hub-enterprise-qa-team.apps.cluster07.ol-ocp.sdk-hub.com"
API_URL_VERSION="$API_BASE_URL/backend/version"
API_URL_CREATE_KEY="$API_BASE_URL/auth-service/api/v1/api-keys?account=false"


# Use x-api-key header instead of Authorization: Bearer
MAX_RETRIES=5
retry_count=0
KEYCLOAK_TOKEN_RESPONSE=""

while [ $retry_count -lt $MAX_RETRIES ] && [ -z "$KEYCLOAK_TOKEN_RESPONSE" ]; do
  echo "Attempting to get Keycloak token (attempt $(($retry_count + 1))/$MAX_RETRIES)..."
  
  KEYCLOAK_TOKEN_RESPONSE=$(curl -s -k --location 'https://hub-enterprise-keycloak-qa-team.apps.cluster07.ol-ocp.sdk-hub.com/auth/realms/ol-hub/protocol/openid-connect/token' \
    --header 'accept: application/json' \
    --header 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode 'username=ol-hub' \
    --data-urlencode 'password=openlegacy' \
    --data-urlencode 'client_id=hub-spa' \
    --data-urlencode 'grant_type=password')
  
  if [ -z "$KEYCLOAK_TOKEN_RESPONSE" ] || ! echo "$KEYCLOAK_TOKEN_RESPONSE" | grep -q "access_token"; then
    echo "Failed to get token, retrying in 30 seconds..."
    KEYCLOAK_TOKEN_RESPONSE=""
    sleep 5
  else
    echo "Successfully obtained Keycloak token"
  fi
  
  retry_count=$((retry_count + 1))
done

if [ -z "$KEYCLOAK_TOKEN_RESPONSE" ]; then
  echo "Failed to get Keycloak token after $MAX_RETRIES attempts. Exiting."
  exit 1
fi


BEARER_TOKEN=$(echo "$KEYCLOAK_TOKEN_RESPONSE" | jq -r '.access_token')
# Update license
LICENSE_UPDATE_URL="$API_BASE_URL/backoffice/api/v1/tenants/4a6bfc5d-3bae-45a3-99b9-d1e255875adb/license"

LICENSE_RESPONSE=$(curl -s -k \
  -X PUT "$LICENSE_UPDATE_URL" \
  -H "Accept: application/json, text/plain, */*" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  --data-raw '{"license":"eyJhbGciOiJSUzI1NiJ9.eyJtYXN0ZXJMaWNlbnNlSWQiOiIxZDE1MTFiYy04NTY5LTQ5OTUtOGU3MC05NGYwNzBhYjRkZjAiLCJleHBpcmF0aW9uRGF0ZSI6IjIwMzItMDUtMDZUMDA6MDA6MDBaIiwiaXNzdWVEYXRlIjoiMjAyNC0xMC0wN1QwNzo0ODowMi4yNjI0MTlaIiwidGVuYW50SWQiOiJjYmFiNWMxNy0wNzUzLTQ3MDEtYTljMy1kM2YyMWZlMTU5NzQiLCJncmFjZVBlcmlvZERheXMiOjkwLCJsaWNlbnNlVHlwZSI6Ik1BU1RFUiIsInJ1bnRpbWVMaW1pdGF0aW9ucyI6eyJNRVRIT0RTIjotMSwiU0NSRUVOUyI6MCwiUlBDX0FTU0VUUyI6LTEsIlBSRU1JVU1fTUVUSE9EUyI6LTF9LCJrZXkiOiIiLCJkZXZLZXkiOiJleUpoYkdjaU9pSlNVekkxTmlKOS5leUp0WVhOMFpYSk1hV05sYm5ObFNXUWlPaUl4WkRFMU1URmlZeTA0TlRZNUxUUTVPVFV0T0dVM01DMDVOR1l3TnpCaFlqUmtaakFpTENKbGVIQnBjbUYwYVc5dVJHRjBaU0k2SWpJd016SXRNRFV0TURaVU1EQTZNREE2TURCYUlpd2lhWE56ZFdWRVlYUmxJam9pTWpBeU5DMHhNQzB3TjFRd056bzBPRG93TVM0MU1EQTNNekJhSWl3aWRHVnVZVzUwU1dRaU9pSmpZbUZpTldNeE55MHdOelV6TFRRM01ERXRZVGxqTXkxa00yWXlNV1psTVRVNU56UWlMQ0puY21GalpWQmxjbWx2WkVSaGVYTWlPamt3TENKc2FXTmxibk5sVkhsd1pTSTZJa1JGVmtWTVQxQk5SVTVVSW4wLlpDczNWMGVDeVZfakJrR2tvbENZR2pQMTNWVGxkV1Z4WWdSczVFa1JLb2VMLU1kSGE2amdNQm13YU5GZ2ljUWNyZ3k1NEZnV0tVTkRiT0FReFljb1J6SDNnbWNjZ2FYb1REakVDWFZwNG45LU5BLVR4cjN2UV9ZVWUtSk5tTWVlTnJ2T1l0dmV5NTYtbDF2TGVFU21YT2thQkZoWTVtVnJFaXd1Q0lTbjFnckNhZkctMk1sT1lmUC1JRWMwaWgxal9uV282cXVYWmJzNXN4OVhRSTZ2NklBcWU3Tk03S3BXeWpYeVJNdVlkbjJXU1JZUnRqbFVZdkJfbUt4cG16Y3JLc3ZqUnBnbUxIaEpjV3ZXZ1lNTVJ1R2Z5MjhYRERjc2RVazE2TmhsZUpuMVVqZU1jQ3czVjlKOWNlTUF1aU5CUTJOQS03RXFzWUZPbklDMTlQN1huZyJ9.bD9rveIjtLooU98dKav8RijhJtBrbO9BbVanFUAHqERWwGwGc6BtyvgOnwibmHIG8xA8e4FNTNU_3Cs1LbmbHgPPpVC25KbA88bBQeO3u4F8e0QZ-ZZplKamFJMmLd_Fg4cFwk53kSbuGegMxDEnc69D_-4oXEMQrUkka8CLol-3HsNOzR9dqo3fk6QASqDw3viB9acGBgDPNv6cYLaFrb5cC_g0phyi67W8MCdJY0Dr_qUrXkVtAJC-EHhfdaN9v6v4Ypd6wA6sX6hWbSlWHNeCQD4qENx3eEzdaBz3VfSuRIPAIKrIJLCJq7CQYGNBLXnCtJki2m9fFgRYuSCgZg"}')

echo "License update response: $LICENSE_RESPONSE"

# --- Version check logic ---
VERSION_RESPONSE=$(curl -s -k \
  -H "Accept: application/json, text/plain, */*" \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  "$API_URL_VERSION")

HUB_VERSION=$(echo "$VERSION_RESPONSE" | jq -r '."hub-version"')
echo "Hub version from API: $HUB_VERSION"
echo "Expected HUB_ENT_TAG: $HUB_ENT_TAG"

assert "[[ \"$HUB_VERSION\" == \"$HUB_ENT_TAG\" ]]" "Hub version mismatch: expected $HUB_ENT_TAG, got $HUB_VERSION"

response=$(curl -s -k -w "\n%{http_code}" \
  -X POST "$API_URL_CREATE_KEY" \
  -H "Accept: application/json, text/plain, */*" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  --data-raw '{"name":"'$RAND_NAME'","description":"enterprise-qa-team-automation"}')

status_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | sed '$d')

if [ "$status_code" -eq 201 ]; then
  echo "API key creation succeeded (201 Created)"
  echo "Response: $response_body"
else
  echo "API key creation failed. Status code: $status_code"
  echo "Response: $response_body"
fi
assert "[[ \"$status_code\" -eq 201 ]]" "API key creation failed. Status code: $status_code"

