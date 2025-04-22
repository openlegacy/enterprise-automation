#!/bin/bash

# Exit script if you try to use an uninitialized variable.
set -o nounset
# Exit script if a statement returns a non-true return value.
set -o errexit
# Use the error status of the first failure, rather than that of the last item in a pipeline.
# set -o pipefail
# set -x
# Treat unset variables and parameters other than the special parameters ‘@’ or ‘*’ as an error
# when performing parameter expansion. An error message will be written to the standard error, and a
# non-interactive shell will exit.
set -u

# This script installs Hub Enterprise on a single server using docker-compose.
# Only CentOS/RedHat and Debian distributions are supported at this moment.

# Colorize
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

cat << EOF


                     //////
   **********  ####  //////
   /////////*  ####
   ///.            ****.
   ///.                        OpenLegacy Hub installation wizard
   ///.           ///*
   ///,           ///*
    /////*********///*
       //////////////*


EOF


########################################################################################
################################## GLOBAL VARIABLES ####################################
########################################################################################

base_path="/opt/openlegacy/upgrade"
config_file="$base_path/upgrade-docker.conf"

########################################################################################
######################################### MAIN #########################################
########################################################################################

main() {

  ########################################################################################
  ################################## PRE-FLIGHT CHECKS ###################################
  ########################################################################################

  # Checking if all packages which are needed are pre-installed
  need_cmd unzip
  need_cmd docker
  need_cmd docker-compose
  need_cmd runc
  need_cmd read
  need_cmd jq

  if [[ -f "$config_file" ]]; then
    source $config_file

    check_export_vars $(cut -d= -f1 $config_file | grep -Ev 'DB_PROVISIONED|DB_SAME_HOST|DOWNLOAD_DOCKER_IMAGES|REGISTRY_URL|REGISTRY_USERNAME|REGISTRY_PASSWORD|KEYCLOAK_REGISTRY_IMAGE_TAG|HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG|HUB_ENT_REGISTRY_IMAGE_TAG|POSTGRES_REGISTRY_IMAGE_TAG')

    if [ "$DB_PROVISIONED" == "true" ]; then
        installed_db="y"
    elif [ "$DB_PROVISIONED" != "true" ]; then
      installed_db="n"
    else
      err "Illegal option."
    fi

    check_selinux

    extract_compose_files

    if [ "$DOWNLOAD_DOCKER_IMAGES" == "true" ]; then
      if [[ -n "$REGISTRY_URL" ]]; then
        if [[ -n "${REGISTRY_USERNAME}" ]] && [[ -n "${REGISTRY_PASSWORD}" ]]; then
          docker login -u "$REGISTRY_USERNAME" -p "$REGISTRY_PASSWORD" "$REGISTRY_URL"
        fi
      fi
      export KEYCLOAK_REGISTRY_IMAGE_TAG
      export HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG
      export HUB_ENT_REGISTRY_IMAGE_TAG

      # Get more granular variables out of the full image path
      docker_pull

      if [ "$installed_db" == "n" ]; then
        export POSTGRES_REGISTRY_IMAGE_TAG
        docker_pull_postgres
      fi
    elif [ "$DOWNLOAD_DOCKER_IMAGES" != "true" ]; then
      restore_images_with_vars
    else
      err "Illegal values."
    fi

    replace_ol_hub_url

  else

    # Checking if DB is need to be installed and what h/w requirements are need to be met
    echo "Do you have Postgres DB already provisioned? (y/n)"; read -r installed_db

    check_selinux

    extract_compose_files

    # Checking if we need to pull docker images
    echo "Do you need to download docker images from your registry? (y/n)"; read -r need_dl_docker_image

    if [ "$need_dl_docker_image" == "y" ]; then
      echo "Enter registry URL: "; read -r registry_url
      echo "Do you need to supply username/password pair for the download? (y/n)"; read -r need_registry_creds
      if [ "$need_registry_creds" == "y" ]; then
        echo "Enter registry username: "; read -r registry_username
        echo "Enter registry password: "; read -rs registry_password
        docker login -u "$registry_username" -p "$registry_password" "$registry_url"
      elif [ "$need_registry_creds" != "n" ]; then
        err "Illegal option."
      fi

      read -e -rp "Enter name and tag of the Keycloak image (e.g.openlegacy/openlegacy-keycloak:15.0.2): " KEYCLOAK_REGISTRY_IMAGE_TAG; export KEYCLOAK_REGISTRY_IMAGE_TAG
      read -e -rp "Enter name and tag of the Hub Enterprise DB migration image (e.g.openlegacy/hub-enterprise-db-migration:1.42.0): " HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG; export HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG
      read -e -rp "Enter name and tag of the Hub Enterprise image (e.g.openlegacy/hub-enterprise:1.42.0): " HUB_ENT_REGISTRY_IMAGE_TAG; export HUB_ENT_REGISTRY_IMAGE_TAG

      # Get more granular variables out of the full image path
      docker_pull

      if [ "$installed_db" == "n" ]; then
        read -e -rp "Enter name and tag of the Postgres image (e.g. postgres:13): " POSTGRES_REGISTRY_IMAGE_TAG
        docker_pull_postgres
      fi

    elif [ "$need_dl_docker_image" == "n" ]; then
      restore_images_with_vars
    else
      err "Illegal option."
    fi


    ########################################################################################
    ############################### GATHER ENV VARS ########################################
    ########################################################################################

    echo -n "Gathering data needed for the installation..."

    printf "\nDATABASE\n"

    read -e -rp "Enter Postgres host: " -i "postgres" OL_DB_HOST; export OL_DB_HOST
    read -e -rp "Enter Postgres name: " -i "postgres" OL_DB_NAME; export OL_DB_NAME
    read -e -rp "Enter Postgres port: " -i "5432" OL_DB_PORT; export OL_DB_PORT

    read -e -rp "Enter Postgres username: " -i "postgres" POSTGRES_USER; export POSTGRES_USER

    if [ "$installed_db" == "y" ]; then
      read -e -rsp "Enter Postgres password: " POSTGRES_PASSWORD; export POSTGRES_PASSWORD
      read -e -rsp "Enter Postgres admin password: " POSTGRESQL_ADMIN_PASSWORD; export POSTGRESQL_ADMIN_PASSWORD
    else
      read -e -rp "Enter Postgres password: " -i "postgres" POSTGRES_PASSWORD; export POSTGRES_PASSWORD
      read -e -rp "Enter Postgres admin password: " -i "postgres" POSTGRESQL_ADMIN_PASSWORD; export POSTGRESQL_ADMIN_PASSWORD
    fi

    printf "\nHUB ENTERPRISE\n"

    read -e -rp "Enter URL which will be used to access the OpenLegacy Hub Web UI (e.g. 10.10.0.10): " OL_HUB_URL; export OL_HUB_URL

    replace_ol_hub_url
  fi
  # If SELinux enabled - add Z option.
  # This will label the content inside the container with the exact MCS label that the container will run with.
  KEYCLOAK_VOLUME="./keycloak/realms:/opt/jboss/keycloak/imports"
  VOLUME_HUB_ENT="~/ol-hub-data:/home/ubuntu/ol-hub-tenant-artifacts"
  VOLUME_HUB_ENT_LIBS="~/ol-hub-data/libs:/usr/app/lib"

  if $selinux; then
    KEYCLOAK_VOLUME="$KEYCLOAK_VOLUME:Z"
    VOLUME_HUB_ENT="$VOLUME_HUB_ENT:Z"
    VOLUME_HUB_ENT_LIBS="$VOLUME_HUB_ENT_LIBS:Z"
  fi

  mkdir -p ~/ol-hub-data/libs

  export KEYCLOAK_VOLUME
  export VOLUME_HUB_ENT
  export VOLUME_HUB_ENT_LIBS

  # Auth variables
  touch $base_path/config.cnf
  cat << EOF > $base_path/config.cnf
[req]
distinguished_name = OL_HUB
prompt = no

[OL_HUB]
commonName = OpenLegacy Hub
organizationName = OpenLegacy
EOF
  OL_HUB_PK_API_KEY_SIGN=$(docker inspect --format='{{json .Config.Env}}' hub-enterprise |  jq -r --arg var "OL_HUB_PK_API_KEY_SIGN" '.[] | select(startswith($var + "=")) | sub("^.*?="; "")'); export OL_HUB_PK_API_KEY_SIGN
  OL_HUB_ENCRYPT_SECRET=$(docker inspect --format='{{json .Config.Env}}' hub-enterprise | jq -r --arg var "OL_HUB_ENCRYPT_SECRET" '.[] | select(startswith($var + "=")) | sub("^.*?="; "")'); export OL_HUB_ENCRYPT_SECRET


  ########################################################################################
  ################################### INSTALLATION #######################################
  ########################################################################################

  echo "Upgrading Hub Enterprise..."
  docker_up "$installed_db" || return 1

  printf "${GREEN}The Upgrade has ended successfully! ٩(^‿^)۶${NC}\n"
}

  ########################################################################################
  ##################################### FUNCTIONS ########################################
  ########################################################################################

need_cmd() {
    if ! check_cmd "$1"; then
        err "need '$1' (command not found)"
    fi
}


check_cmd() {
    command -v "$1" > /dev/null 2>&1
}


err() {
    say "$1" >&2
    exit 1
}

say() {
    printf "${PURPLE}hub-ent: %s${NC}\n" "$1"
}


check_selinux() {
  selinuxenabled

  if [ $? -ne 0 ]
  then
      selinux="false"
      echo "SELinux is DISABLED"
  else
      selinux="true"
      echo "SELinux is ENABLED"
  fi
}


extract_compose_files() {
  tar -xf $base_path/docker-compose-files.tar --strip-components=6 -C $base_path
}


replace_ol_hub_url() {
  search="localhost:8081"; replace="$OL_HUB_URL:8080"; sed -i "s/$search/$replace/" $base_path/docker-compose/keycloak/realms/ol-hub-realm.json
}


restore_images_with_vars() {
  echo "Restoring docker images"
  KEYCLOAK_REGISTRY_IMAGE="openlegacy/openlegacy-keycloak"; export KEYCLOAK_REGISTRY_IMAGE
  HUB_ENT_DB_MIGR_REGISTRY_IMAGE="openlegacy/hub-enterprise-db-migration"; export HUB_ENT_DB_MIGR_REGISTRY_IMAGE
  HUB_ENT_REGISTRY_IMAGE="openlegacy/hub-enterprise"; export HUB_ENT_REGISTRY_IMAGE
  POSTGRES_REGISTRY_IMAGE="postgres"; export POSTGRES_REGISTRY_IMAGE

  HUB_ENT_TAG="$(ls $base_path | grep hub-enterprise: | cut -d: -f2)"; HUB_ENT_TAG="${HUB_ENT_TAG%.*}"; export HUB_ENT_TAG
  HUB_ENT_DB_MIGR_TAG="$(ls $base_path | grep hub-enterprise-db-migration: | cut -d: -f2)"; HUB_ENT_DB_MIGR_TAG="${HUB_ENT_DB_MIGR_TAG%.*}"; export HUB_ENT_DB_MIGR_TAG
  KEYCLOAK_TAG="$(ls $base_path | grep openlegacy-keycloak: | cut -d: -f2)"; KEYCLOAK_TAG="${KEYCLOAK_TAG%.*}"; export KEYCLOAK_TAG
  POSTGRES_TAG="13"; export POSTGRES_TAG

  restore_docker_images "$installed_db" || return 1
}


docker_pull() {
  KEYCLOAK_REGISTRY_IMAGE="$(echo "$KEYCLOAK_REGISTRY_IMAGE_TAG" | cut -d: -f1)"; export KEYCLOAK_REGISTRY_IMAGE    #openlegacy/openlegacy-keycloak
  KEYCLOAK_TAG="$(echo "$KEYCLOAK_REGISTRY_IMAGE_TAG" | cut -d: -f2)"; export KEYCLOAK_TAG   # 15.0.2

  HUB_ENT_DB_MIGR_REGISTRY_IMAGE="$(echo "$HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG" | cut -d: -f1)"; export HUB_ENT_DB_MIGR_REGISTRY_IMAGE
  HUB_ENT_DB_MIGR_TAG="$(echo "$HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG" | cut -d: -f2)"; export HUB_ENT_DB_MIGR_TAG

  HUB_ENT_REGISTRY_IMAGE="$(echo "$HUB_ENT_REGISTRY_IMAGE_TAG" | cut -d: -f1)"; export HUB_ENT_REGISTRY_IMAGE
  HUB_ENT_TAG="$(echo "$HUB_ENT_REGISTRY_IMAGE_TAG" | cut -d: -f2)"; export HUB_ENT_TAG

  docker pull "$KEYCLOAK_REGISTRY_IMAGE_TAG"
  docker pull "$HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG"
  docker pull "$HUB_ENT_REGISTRY_IMAGE_TAG"
}


docker_pull_postgres() {
  POSTGRES_REGISTRY_IMAGE="$(echo "$POSTGRES_REGISTRY_IMAGE_TAG" | cut -d: -f1)"; export POSTGRES_REGISTRY_IMAGE
  POSTGRES_TAG="$(echo "$POSTGRES_REGISTRY_IMAGE_TAG" | cut -d: -f2)"; export POSTGRES_TAG
  docker pull "$POSTGRES_REGISTRY_IMAGE_TAG"
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


restore_docker_images() {
    installed_db=$1

    if [ "$installed_db" == "n" ]; then
      docker load < $base_path/postgres:13.tar
    fi

    docker load < "$base_path/openlegacy-keycloak:$KEYCLOAK_TAG.tar"
    docker load < "$base_path/hub-enterprise:$HUB_ENT_TAG.tar"
    docker load < "$base_path/hub-enterprise-db-migration:$HUB_ENT_DB_MIGR_TAG.tar"
}


docker_up() {
    installed_db=$1
    # Create docker network
    docker network create hub-enterprise

    # Run docker containers
    if [ "$installed_db" == "n" ]; then
      docker-compose -f $base_path/docker-compose/postgres.yaml up -d
      printf "${BLUE}Waiting for the container to set up, do not cancel the script...${NC}\n"; sleep 1m
      check_docker_container_status postgres || return 1
    fi

    docker-compose -f $base_path/docker-compose/hub-enterprise-db-migration.yaml up -d
    printf "${BLUE}Waiting for the container to set up, do not cancel the script...${NC}\n"; sleep 5s
    check_docker_container_status hub-enterprise-db-migration || return 1
    docker-compose -f $base_path/docker-compose/keycloak.yaml up -d
    printf "${BLUE}Waiting for the container to set up, do not cancel the script...${NC}\n"; sleep 90s
    check_docker_container_status keycloak || return 1
    docker-compose -f $base_path/docker-compose/hub-enterprise.yaml up -d
    printf "${BLUE}Waiting for the container to set up, do not cancel the script...${NC}\n"; sleep 1m
}

check_docker_container_status() {
  container_name=$1
  container_id=$(docker ps -aqf "name=$container_name")
  container_status=$(docker inspect "$container_id" --format='{{.State.ExitCode}}')
  if [[ "$container_status" != 0 ]]; then
    err "There was a problem with starting a container"
  fi
}

########################################################################################
############################# START THE INSTALLATION ###################################
########################################################################################

main "$@" || exit 1
