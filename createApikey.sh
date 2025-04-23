assert() {
  if ! eval "$1"; then
    echo "Assertion failed: $2" >&2
    exit 1
  fi
}

HUB_ENT_TAG=$1
# Remove -rhel suffix if present
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
    sleep 30
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

