KEYCLOAK_IMAGE="$1"
HUB_ENT_DB_MIGR_IMAGE="$2"
HUB_ENT_IMAGE="$3"
HUB_ENT_ONE_BEFORE_LATEST_TAG="$4"


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

echo "Installation process completed. Creating API key for $HUB_ENT_ONE_BEFORE_LATEST_TAG"
bash ./createApikey.sh "$HUB_ENT_ONE_BEFORE_LATEST_TAG"

