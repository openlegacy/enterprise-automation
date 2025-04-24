set -o pipefail  # Propagate errors through pipes

# Function to handle errors
handle_error() {
  local exit_code=$1
  local error_message=$2
  echo "ERROR: $error_message (Exit code: $exit_code)" >&2
  exit $exit_code
}

# Keycloak
KEYCLOAK_IMAGE_REPO="openlegacy/openlegacy-keycloak"
KEYCLOAK_TAGS=($(curl -s -k "https://registry.hub.docker.com/v2/repositories/${KEYCLOAK_IMAGE_REPO}/tags?page_size=6&page=1&ordering=last_updated" | jq -r '.results[].name'))
KEYCLOAK_LATEST_TAG="${KEYCLOAK_TAGS[0]}"
KEYCLOAK_IMAGE="${KEYCLOAK_IMAGE_REPO}:${KEYCLOAK_LATEST_TAG}"

# DB Migration (all except latest)
DB_MIGR_IMAGE_REPO="openlegacy/hub-enterprise-db-migration"
DB_MIGR_TAGS=($(curl -s -k "https://registry.hub.docker.com/v2/repositories/${DB_MIGR_IMAGE_REPO}/tags?page_size=6&page=1&ordering=last_updated" | jq -r '.results[].name' | grep -v '^latest$'))
DB_MIGR_LATEST_TAG="${DB_MIGR_TAGS[0]}"
DB_MIGR_ONE_BEFORE_LATEST_TAG="${DB_MIGR_TAGS[1]}"
HUB_ENT_DB_MIGR_IMAGE="${DB_MIGR_IMAGE_REPO}:${DB_MIGR_LATEST_TAG}"
HUB_ENT_DB_MIGR_IMAGE_ONE_BEFORE="${DB_MIGR_IMAGE_REPO}:${DB_MIGR_ONE_BEFORE_LATEST_TAG}"

# Hub Enterprise (rhel only)
tmp_tags=$(curl -s -k "https://registry.hub.docker.com/v2/repositories/openlegacy/hub-enterprise/tags?page_size=6&page=1&ordering=last_updated" | jq -r '.results[].name')
mapfile -t HUB_ENT_RHEL_TAGS < <(echo "$tmp_tags" | grep -- '-rhel')
HUB_ENT_LATEST_TAG="${HUB_ENT_RHEL_TAGS[0]}"
HUB_ENT_ONE_BEFORE_LATEST_TAG="${HUB_ENT_RHEL_TAGS[1]}"
HUB_ENT_IMAGE="openlegacy/hub-enterprise:${HUB_ENT_LATEST_TAG}"
HUB_ENT_IMAGE_ONE_BEFORE="openlegacy/hub-enterprise:${HUB_ENT_ONE_BEFORE_LATEST_TAG}"

# Clean up newlines
KEYCLOAK_IMAGE=$(echo "$KEYCLOAK_IMAGE" | tr -d '\r\n')
HUB_ENT_DB_MIGR_IMAGE=$(echo "$HUB_ENT_DB_MIGR_IMAGE" | tr -d '\r\n')
HUB_ENT_DB_MIGR_IMAGE_ONE_BEFORE=$(echo "$HUB_ENT_DB_MIGR_IMAGE_ONE_BEFORE" | tr -d '\r\n')
HUB_ENT_IMAGE=$(echo "$HUB_ENT_IMAGE" | tr -d '\r\n')
HUB_ENT_IMAGE_ONE_BEFORE=$(echo "$HUB_ENT_IMAGE_ONE_BEFORE" | tr -d '\r\n')

# Print for debug
echo "Latest Keycloak image: $KEYCLOAK_IMAGE"
echo "One before latest Hub Enterprise image: $HUB_ENT_IMAGE_ONE_BEFORE"
echo "Latest Hub Enterprise image: $HUB_ENT_IMAGE"
echo "One before latest DB Migration image: $HUB_ENT_DB_MIGR_IMAGE_ONE_BEFORE"
echo "Latest DB Migration image: $HUB_ENT_DB_MIGR_IMAGE"

oc login --token=sha256~nx9KrE4P5XVTzmteQTyXRjvSRwpRD_4GXjvsU1q0D30 --server=https://api.cluster07.ol-ocp.sdk-hub.com:6443
# Delete the helm release named hub-enterprise
echo "Deleting helm release hub-enterprise..."
helm delete hub-enterprise -n qa-team
echo "Waiting 60 seconds before proceeding"
sleep 60 

target_conf="offline-installation/installer-helm.conf"
sed -i "s|^KEYCLOAK_IMAGE=.*|KEYCLOAK_IMAGE=\"$KEYCLOAK_IMAGE\"|" "$target_conf"
sed -i "s|^HUB_ENT_DB_MIGR_IMAGE=.*|HUB_ENT_DB_MIGR_IMAGE=\"$HUB_ENT_DB_MIGR_IMAGE_ONE_BEFORE\"|" "$target_conf"
sed -i "s|^HUB_ENT_IMAGE=.*|HUB_ENT_IMAGE=\"$HUB_ENT_IMAGE_ONE_BEFORE\"|" "$target_conf"
echo "Updated $target_conf with new image tags."

# Run install script and capture exit code
bash ./installScript.sh "$KEYCLOAK_IMAGE" "$HUB_ENT_DB_MIGR_IMAGE_ONE_BEFORE" "$HUB_ENT_IMAGE_ONE_BEFORE" "$HUB_ENT_ONE_BEFORE_LATEST_TAG"
INSTALL_EXIT_CODE=$?
if [ $INSTALL_EXIT_CODE -ne 0 ]; then
    handle_error $INSTALL_EXIT_CODE "Installation script failed"
fi

echo "Waiting 3 minutes before proceeding with upgrade..."
sleep 180   

target_conf="offline-installation/upgrade-helm.conf"
sed -i "s|^KEYCLOAK_IMAGE=.*|KEYCLOAK_IMAGE=\"$KEYCLOAK_IMAGE\"|" "$target_conf"
sed -i "s|^HUB_ENT_DB_MIGR_IMAGE=.*|HUB_ENT_DB_MIGR_IMAGE=\"$HUB_ENT_DB_MIGR_IMAGE\"|" "$target_conf"
sed -i "s|^HUB_ENT_IMAGE=.*|HUB_ENT_IMAGE=\"$HUB_ENT_IMAGE\"|" "$target_conf"
echo "Updated $target_conf with new image tags."

# Run upgrade script and capture exit code
bash ./upgradeScript.sh "$KEYCLOAK_IMAGE" "$HUB_ENT_DB_MIGR_IMAGE" "$HUB_ENT_IMAGE" "$HUB_ENT_LATEST_TAG"
UPGRADE_EXIT_CODE=$?
if [ $UPGRADE_EXIT_CODE -ne 0 ]; then
    handle_error $UPGRADE_EXIT_CODE "Upgrade script failed"
fi

# If we get here, both scripts completed successfully
echo "Installation and upgrade completed successfully"
exit 0

