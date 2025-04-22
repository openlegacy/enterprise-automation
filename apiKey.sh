RAND_NAME=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 29)
RAND_NAME="$(tr -dc 'a-z' < /dev/urandom | head -c 1)$RAND_NAME"

# After installation, make the API request
API_URL="https://hub-enterprise-qa-team.apps.cluster07.ol-ocp.sdk-hub.com/auth-service/api/v1/api-keys?account=false"

# Use x-api-key header instead of Authorization: Bearer
KEYCLOAK_TOKEN_RESPONSE=$(curl -s --location 'https://hub-enterprise-keycloak-qa-team.apps.cluster07.ol-ocp.sdk-hub.com/auth/realms/ol-hub/protocol/openid-connect/token' \
  --header 'accept: application/json' \
  --header 'content-type: application/x-www-form-urlencoded' \
  --data-urlencode 'username=ol-hub' \
  --data-urlencode 'password=openlegacy' \
  --data-urlencode 'client_id=hub-spa' \
  --data-urlencode 'grant_type=password')

BEARER_TOKEN=$(echo "$KEYCLOAK_TOKEN_RESPONSE" | jq -r '.access_token')

status_code=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$API_URL" \
  -H "Accept: application/json, text/plain, */*" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  --data-raw '{"name":"'$RAND_NAME'","description":"enterprise-qa-team-automation"}')

if [ "$status_code" -eq 201 ]; then
  echo "API key creation succeeded (201 Created)"
else
  echo "API key creation failed. Status code: $status_code"
fi
