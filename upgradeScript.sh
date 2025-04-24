KEYCLOAK_IMAGE="$1"
HUB_ENT_DB_MIGR_IMAGE="$2"
HUB_ENT_IMAGE="$3"
HUB_ENT_LATEST_TAG="$4"

set -o pipefail  # Propagate errors through pipes

# Function to handle errors
handle_error() {
  local exit_code=$1
  local error_message=$2
  echo "ERROR: $error_message (Exit code: $exit_code)" >&2
  exit $exit_code
}

ANSWERS="y
qa-team
n
$KEYCLOAK_IMAGE
$HUB_ENT_DB_MIGR_IMAGE
$HUB_ENT_IMAGE
https://hub-enterprise-qa-team.apps.cluster07.ol-ocp.sdk-hub.com
https://hub-enterprise-keycloak-qa-team.apps.cluster07.ol-ocp.sdk-hub.com
2
qa-team
hub-enterprise-postgres
5432
postgres
postgres
postgres
n
y
"

offline_upgrade_sh="offline-installation/upgrade-helm.sh"
if [ -x "$offline_upgrade_sh" ]; then
    printf "%s" "$ANSWERS" | "$offline_upgrade_sh"
else
    printf "%s" "$ANSWERS" | bash "$offline_upgrade_sh"
fi

echo "Upgrade process completed. Creating API key for $HUB_ENT_LATEST_TAG"
bash ./createApikey.sh "$HUB_ENT_LATEST_TAG"

API_KEY_EXIT_CODE=$?
if [ $API_KEY_EXIT_CODE -ne 0 ]; then
    handle_error $API_KEY_EXIT_CODE "API key creation failed with assert error"
fi

# If we get here, both scripts completed successfully
exit 0