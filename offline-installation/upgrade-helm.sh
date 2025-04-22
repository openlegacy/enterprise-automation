#!/bin/bash

# Exit script if you try to use an uninitialized variable.
set -o nounset
# Exit script if a statement returns a non-true return value.
set -o errexit
# Use the error status of the first failure, rather than that of the last item in a pipeline.
# set -o pipefail
# set -x

# Colorize
GREEN='\033[0;32m'
BLUE='\033[1;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

cat << EOF


                     //////
   **********  ####  //////
   /////////*  ####
   ///.            ****.
   ///.                        OpenLegacy Hub upgrade wizard
   ///.           ///*
   ///,           ///*
    /////*********///*
       //////////////*


EOF


########################################################################################
################################## GLOBAL VARIABLES ####################################
########################################################################################

base_path="/opt/openlegacy"

helm_charts_archive="$base_path/hub-enterprise.tgz"
helm_chart_name="hub-enterprise"
config_file="$base_path/upgrade-helm.conf"


########################################################################################
######################################### MAIN #########################################
########################################################################################

main() {
  ########################################################################################
  ################################## PRE-FLIGHT CHECKS ###################################
  ########################################################################################

  # Checking if all packages which are needed are pre-installed
  need_cmd kubectl
  need_cmd helm

  # Show user current k8s context and make them confirm they want to proceed with that context
  verify_context || return 1

  # Unarchive directory with Helm charts. This is needed before the installation because we
  # need to modify values-template.yaml
  tar -xf "$helm_charts_archive" --strip-components=3 -C "$base_path"


  ########################################################################################
  ############################### GATHER ENV VARS ########################################
  ########################################################################################

  if [[ -f "$config_file" ]]; then
    source $config_file

    check_export_vars $(cut -d= -f1 $config_file | grep -Ev 'REGISTRY_USERNAME|REGISTRY_PASSWORD|k8s_namespace')

    if [[ -n "${REGISTRY_USERNAME}" ]] && [[ -n "${REGISTRY_PASSWORD}" ]]; then
      export REGISTRY_USERNAME
      export REGISTRY_PASSWORD
    fi
  else
    echo "Gathering data needed for the upgrade..."

    read -e -rp "Enter the name of the namespace where Hub Enterprise was installed: " -i "hub-enterprise" k8s_namespace

    # Check if namespace was created beforehand
    check_k8s_namespace

    printf "\nREGISTRY\n"
    read -e -rp "Enter registry URL (example: index.docker.io): " -i "index.docker.io" REGISTRY_URL; export REGISTRY_URL
    read -e -rp "Do you need to authenticate in registry? (y/n) " need_auth_registry

    if [[ "$need_auth_registry" == "y" ]]; then
      read -e -rp "Enter registry username: " REGISTRY_USERNAME; export REGISTRY_USERNAME
      read -e -rsp "Enter registry password: " REGISTRY_PASSWORD; export REGISTRY_PASSWORD
    elif [[ "$need_auth_registry" != "n" ]]; then
      err "Illegal option."
    fi

    ### HUB ENTERPRISE ###
    printf "\nHUB ENTERPRISE\n"

    read -e -rp "Enter name and tag of the Keycloak image: " -i "openlegacy/openlegacy-keycloak:26.1.2" KEYCLOAK_IMAGE; export KEYCLOAK_IMAGE
    read -e -rp "Enter name and tag of the Hub Enterprise DB migration image: " -i "openlegacy/hub-enterprise-db-migration:3.0.7" HUB_ENT_DB_MIGR_IMAGE; export HUB_ENT_DB_MIGR_IMAGE
    read -e -rp "Enter name and tag of the Hub Enterprise image: " -i "openlegacy/hub-enterprise:3.0.7" HUB_ENT_IMAGE; export HUB_ENT_IMAGE

    prompt_resource_limits
  fi

  validate_resource_values || exit 1

  ########################################################################################
  ################################### UPGRADE ############################################
  ########################################################################################

  # Upgrade Hub Enterprise
  helm_upgrade || return 1

  printf "${GREEN}The upgrade ended successfully! ٩(^‿^)۶${NC}\n"

}


########################################################################################
##################################### FUNCTIONS ########################################
########################################################################################


check_cmd() {
    command -v "$1" > /dev/null 2>&1
}


need_cmd() {
    if ! check_cmd "$1"; then
        err "need '$1' (command not found)"
    fi
}


err() {
    say "$1" >&2
    exit 1
}


say() {
    printf "${PURPLE}hub-ent: %s${NC}\n" "$1"
}

prompt_resource_limits() {
    echo "Configure Resource Limits"
    echo "------------------------"

    # Keycloak resources
    echo "Keycloak Resource Limits:"
    read -p "CPU limit (e.g., 1000m): " KEYCLOAK_CPU_LIMIT
    read -p "Memory limit (e.g., 1024Mi): " KEYCLOAK_MEMORY_LIMIT
    read -p "CPU request (e.g., 500m): " KEYCLOAK_CPU_REQUEST
    read -p "Memory request (e.g., 512Mi): " KEYCLOAK_MEMORY_REQUEST

    # Hub Enterprise resources
    echo -e "\nHub Enterprise Resource Limits:"
    read -p "CPU limit (e.g., 1000m): " HUB_CPU_LIMIT
    read -p "Memory limit (e.g., 1024Mi): " HUB_MEMORY_LIMIT
    read -p "CPU request (e.g., 500m): " HUB_CPU_REQUEST
    read -p "Memory request (e.g., 512Mi): " HUB_MEMORY_REQUEST
}
validate_resource_values() {
    local cpu_pattern='^[0-9]+m$'
    local memory_pattern='^[0-9]+[MGT]i$'

    # Validate CPU format
    if ! [[ $KEYCLOAK_CPU_LIMIT =~ $cpu_pattern ]] || \
       ! [[ $KEYCLOAK_CPU_REQUEST =~ $cpu_pattern ]] || \
       ! [[ $HUB_CPU_LIMIT =~ $cpu_pattern ]] || \
       ! [[ $HUB_CPU_REQUEST =~ $cpu_pattern ]]; then
        echo "Error: CPU values must be in millicores format (e.g., 1000m)"
        return 1
    fi

    # Validate memory format
    if ! [[ $KEYCLOAK_MEMORY_LIMIT =~ $memory_pattern ]] || \
       ! [[ $KEYCLOAK_MEMORY_REQUEST =~ $memory_pattern ]] || \
       ! [[ $HUB_MEMORY_LIMIT =~ $memory_pattern ]] || \
       ! [[ $HUB_MEMORY_REQUEST =~ $memory_pattern ]]; then
        echo "Error: Memory values must be in format like 1024Mi, 2Gi, etc."
        return 1
    fi

    # Validate that requests don't exceed limits
    if [[ "${KEYCLOAK_CPU_REQUEST%m}" -gt "${KEYCLOAK_CPU_LIMIT%m}" ]] || \
       [[ "${HUB_CPU_REQUEST%m}" -gt "${HUB_CPU_LIMIT%m}" ]]; then
        echo "Error: CPU requests cannot exceed limits"
        return 1
    fi

    return 0
}

verify_context() {
  # Display the current context
  current_context=$(kubectl config current-context)
  printf "You current kubernetes context is ${BLUE}%s.${NC}\n Do you want to proceed? (y/n) " "$current_context"
  read -r context_is_correct
  if [[ $context_is_correct == "y" ]]; then
    printf "Proceeding with the upgrade...\n"
  elif [[ $context_is_correct == "n" ]]; then
    read -e -rp "Enter the correct k8s cluster name: " cluster_name
    kubectl config use-context "$cluster_name"
    current_context=$(kubectl config current-context)
    printf "${GREEN}Changed kubernetes context to %s.${NC}" "$current_context"
  else
    err "Illegal option."
  fi
}

check_k8s_namespace() {
  namespace_exists=$(kubectl get namespace "$k8s_namespace")
  if [[ -z "$namespace_exists" ]]; then
    err "Namespace doesn't exist."
  fi
}

check_export_vars() {
  var_unset=""
  var_names=("$@")
  for var_name in "${var_names[@]}"; do
    if [[ -z "${!var_name}" ]]; then
      echo "$var_name is unset. Please recheck" && var_unset=true
    else
      export $var_name
    fi
  done
  if [[ -n "$var_unset" ]]; then
    exit 1
  fi
  return 0
}

helm_upgrade() {
  helm upgrade --install "$helm_chart_name" "$base_path/$helm_chart_name" \
     --atomic \
     --timeout 5m \
     --namespace="$k8s_namespace" \
     --reuse-values \
     --set keycloak.image="$KEYCLOAK_IMAGE" \
     --set dbMigration.image="$HUB_ENT_DB_MIGR_IMAGE" \
     --set hubEnterprise.image="$HUB_ENT_IMAGE" \
     --set hubEnterprise.service.type="ClusterIP" \
     --set imageCredentials.registry="$REGISTRY_URL" \
     --set imageCredentials.username="$REGISTRY_USERNAME" \
     --set imageCredentials.password="$REGISTRY_PASSWORD" \
     --set hubEnterprise.LibStorage.size=1G \
     --set hubEnterprise.LibStorage.mountPath="/usr/app/lib" \
     --set keycloak.resources.limits.cpu="$KEYCLOAK_CPU_LIMIT" \
     --set keycloak.resources.limits.memory="$KEYCLOAK_MEMORY_LIMIT" \
     --set keycloak.resources.requests.cpu="$KEYCLOAK_CPU_REQUEST" \
     --set keycloak.resources.requests.memory="$KEYCLOAK_MEMORY_REQUEST" \
     --set hubEnterprise.resources.limits.cpu="$HUB_CPU_LIMIT" \
     --set hubEnterprise.resources.limits.memory="$HUB_MEMORY_LIMIT" \
     --set hubEnterprise.resources.requests.cpu="$HUB_CPU_REQUEST" \
     --set hubEnterprise.resources.requests.memory="$HUB_MEMORY_REQUEST" \
     --dry-run
  helm upgrade --install "$helm_chart_name" "$base_path/$helm_chart_name" \
     --atomic \
     --timeout 5m \
     --namespace="$k8s_namespace" \
     --reuse-values \
     --set keycloak.image="$KEYCLOAK_IMAGE" \
     --set dbMigration.image="$HUB_ENT_DB_MIGR_IMAGE" \
     --set hubEnterprise.image="$HUB_ENT_IMAGE" \
     --set hubEnterprise.service.type="ClusterIP" \
     --set imageCredentials.registry="$REGISTRY_URL" \
     --set imageCredentials.username="$REGISTRY_USERNAME" \
     --set imageCredentials.password="$REGISTRY_PASSWORD" \
     --set hubEnterprise.LibStorage.size=1G \
     --set hubEnterprise.LibStorage.mountPath="/usr/app/lib" \
     --set keycloak.resources.limits.cpu="$KEYCLOAK_CPU_LIMIT" \
     --set keycloak.resources.limits.memory="$KEYCLOAK_MEMORY_LIMIT" \
     --set keycloak.resources.requests.cpu="$KEYCLOAK_CPU_REQUEST" \
     --set keycloak.resources.requests.memory="$KEYCLOAK_MEMORY_REQUEST" \
     --set hubEnterprise.resources.limits.cpu="$HUB_CPU_LIMIT" \
     --set hubEnterprise.resources.limits.memory="$HUB_MEMORY_LIMIT" \
     --set hubEnterprise.resources.requests.cpu="$HUB_CPU_REQUEST" \
     --set hubEnterprise.resources.requests.memory="$HUB_MEMORY_REQUEST"
}


########################################################################################
############################# START THE UPGRADE ########################################
########################################################################################

main "$@" || exit 1
