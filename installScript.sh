# Get the latest and one-before-latest tag for openlegacy/openlegacy-keycloak
KEYCLOAK_IMAGE_REPO="openlegacy/openlegacy-keycloak"
KEYCLOAK_TAGS=($(curl -s -k "https://registry.hub.docker.com/v2/repositories/${KEYCLOAK_IMAGE_REPO}/tags?page_size=6&page=1&ordering=last_updated" | jq -r '.results[].name'))
KEYCLOAK_LATEST_TAG="${KEYCLOAK_TAGS[0]}"
KEYCLOAK_IMAGE="${KEYCLOAK_IMAGE_REPO}:${KEYCLOAK_LATEST_TAG}"
# Get the latest and one-before-latest tag for openlegacy/hub-enterprise-db-migration
DB_MIGR_IMAGE_REPO="openlegacy/hub-enterprise-db-migration"
# Get all tags except "latest"
DB_MIGR_TAGS=($(curl -s -k "https://registry.hub.docker.com/v2/repositories/${DB_MIGR_IMAGE_REPO}/tags?page_size=6&page=1&ordering=last_updated" | jq -r '.results[].name' | grep -v '^latest$'))
DB_MIGR_LATEST_TAG="${DB_MIGR_TAGS[0]}"
DB_MIGR_ONE_BEFORE_LATEST_TAG="${DB_MIGR_TAGS[1]}"
HUB_ENT_DB_MIGR_IMAGE="${DB_MIGR_IMAGE_REPO}:${DB_MIGR_LATEST_TAG}"
HUB_ENT_DB_MIGR_IMAGE_ONE_BEFORE="${DB_MIGR_IMAGE_REPO}:${DB_MIGR_ONE_BEFORE_LATEST_TAG}"

# Get the latest and one-before-latest tag for openlegacy/hub-enterprise with '-rhel' only
tmp_tags=$(curl -s -k "https://registry.hub.docker.com/v2/repositories/openlegacy/hub-enterprise/tags?page_size=6&page=1&ordering=last_updated" | jq -r '.results[].name')
HUB_ENT_RHEL_TAGS=($(echo "$tmp_tags" | grep -- '-rhel'))
HUB_ENT_LATEST_TAG="${HUB_ENT_RHEL_TAGS[0]}"
HUB_ENT_ONE_BEFORE_LATEST_TAG="${HUB_ENT_RHEL_TAGS[1]}"
HUB_ENT_IMAGE="openlegacy/hub-enterprise:${HUB_ENT_LATEST_TAG}"
HUB_ENT_IMAGE_ONE_BEFORE="openlegacy/hub-enterprise:${HUB_ENT_ONE_BEFORE_LATEST_TAG}"

echo "Latest Keycloak image: $KEYCLOAK_IMAGE"
echo "One before latest Hub Enterprise image: $HUB_ENT_IMAGE_ONE_BEFORE"
echo "Latest Hub Enterprise image: $HUB_ENT_IMAGE"
echo "One before latest DB Migration image: $HUB_ENT_DB_MIGR_IMAGE_ONE_BEFORE"
echo "Latest DB Migration image: $HUB_ENT_DB_MIGR_IMAGE"



# Remove any newlines or carriage returns from the variables
KEYCLOAK_IMAGE=$(echo "$KEYCLOAK_IMAGE" | tr -d '\r\n')
HUB_ENT_DB_MIGR_IMAGE_ONE_BEFORE=$(echo "$HUB_ENT_DB_MIGR_IMAGE_ONE_BEFORE" | tr -d '\r\n')
HUB_ENT_IMAGE_ONE_BEFORE=$(echo "$HUB_ENT_IMAGE_ONE_BEFORE" | tr -d '\r\n')

# Update offline-installation/installer-helm.conf with the new image tags
target_conf="offline-installation/installer-helm.conf"

# Use sed to update the values in-place
sed -i "s|^KEYCLOAK_IMAGE=.*|KEYCLOAK_IMAGE=\"$KEYCLOAK_IMAGE\"|" "$target_conf"
sed -i "s|^HUB_ENT_DB_MIGR_IMAGE=.*|HUB_ENT_DB_MIGR_IMAGE=\"$HUB_ENT_DB_MIGR_IMAGE_ONE_BEFORE\"|" "$target_conf"
sed -i "s|^HUB_ENT_IMAGE=.*|HUB_ENT_IMAGE=\"$HUB_ENT_IMAGE_ONE_BEFORE\"|" "$target_conf"

echo "Updated $target_conf with new image tags."

# Log in to OpenShift before running the installer
#oc login --username=qaautomation --password='y4#fB7C9Nf1dgbtd3s1' --server=https://api.cluster07.ol-ocp.sdk-hub.com:6443
oc login --token=sha256~E9R1Ru3Ank6l69L8XhkW5KGcy1wwW6YE7G5W37Cm_cg --server=https://api.cluster07.ol-ocp.sdk-hub.com:6443

ANSWERS="y
openlegacy
n
$KEYCLOAK_IMAGE
$HUB_ENT_DB_MIGR_IMAGE_ONE_BEFORE
$HUB_ENT_IMAGE_ONE_BEFORE
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

# Run the installer script
offline_install_sh="offline-installation/installer-helm.sh"
if [ -x "$offline_install_sh" ]; then
    printf "%s" "$ANSWERS" | "$offline_install_sh"
else
    printf "%s" "$ANSWERS" | bash "$offline_install_sh"
fi


bash ./createApikey.sh "$HUB_ENT_ONE_BEFORE_LATEST_TAG"

