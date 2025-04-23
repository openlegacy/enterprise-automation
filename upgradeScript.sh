KEYCLOAK_IMAGE="$1"
HUB_ENT_DB_MIGR_IMAGE="$2"
HUB_ENT_IMAGE="$3"
HUB_ENT_LATEST_TAG="$4"

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


bash ./createApikey.sh "$HUB_ENT_LATEST_TAG"

