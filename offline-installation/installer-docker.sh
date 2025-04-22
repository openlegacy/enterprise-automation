#!/bin/bash

################################################################################
# OpenLegacy Hub Enterprise Docker Installer
# Description: Installs Hub Enterprise on a single server using docker-compose
# Supported OS: CentOS/RedHat and Debian distributions
################################################################################

# Exit configuration
set -o nounset  # Exit on uninitialized variable
set -o errexit  # Exit on error
set -u          # Treat unset variables as errors
set -a          # Export all variables

################################################################################
# Constants
################################################################################

# Color definitions
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# System requirements
readonly MIN_CPU=2
readonly MIN_RAM_SEPARATE=4  # GB
readonly MIN_RAM_COMBINED=8  # GB
readonly MIN_DISK_SEPARATE=8 # GB
readonly MIN_DISK_COMBINED=20 # GB

# Paths
readonly BASE_PATH="/opt/openlegacy"
readonly CONFIG_FILE="$BASE_PATH/installer-docker.conf"

# Volume definitions
KEYCLOAK_VOLUME="./keycloak/realms:/opt/keycloak/data/import"
VOLUME_HUB_ENT="$BASE_PATH/volumes/hub-enterprise/ol-hub-tenant-artifacts:/home/ubuntu/ol-hub-tenant-artifacts"
VOLUME_HUB_ENT_LIBS="$BASE_PATH/volumes/hub-enterprise/libs:/usr/app/lib"
COMPOSE_CMD=""

################################################################################
# System Requirements Display Function
################################################################################

print_requirements() {
    printf "\nSystem Requirements:\n"
    printf "${BLUE}====================${NC}\n\n"

    printf "Minimum CPU Requirements:\n"
    printf "${GREEN}► ${MIN_CPU} CPU cores${NC}\n\n"

    printf "Minimum RAM Requirements:\n"
    printf "${GREEN}► ${MIN_RAM_SEPARATE} GB${NC} (when database is on a separate machine)\n"
    printf "${GREEN}► ${MIN_RAM_COMBINED} GB${NC} (when database is on the same machine)\n\n"

    printf "Minimum Disk Space Requirements:\n"
    printf "${GREEN}► ${MIN_DISK_SEPARATE} GB${NC} (when database is on a separate machine)\n"
    printf "${GREEN}► ${MIN_DISK_COMBINED} GB${NC} (when database is on the same machine)\n\n"

    printf "Additional Requirements:\n"
    printf "${GREEN}► Docker Engine installed and running\n"
    printf "► Docker Compose (plugin or standalone)\n"
    printf "► Unzip utility\n"
    printf "► Internet connection (for downloading images)${NC}\n\n"

    printf "Note: These are minimum requirements. For production environments,\n"
    printf "higher specifications are recommended for better performance.\n\n"
}

################################################################################
# Utility Functions
################################################################################

err() {
    say "$1" >&2
    exit 1
}

say() {
    printf "${PURPLE}hub-ent: %s${NC}\n" "$1"
}

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "need '$1' (command not found)"
    fi
}

print_banner() {
    cat << 'EOF'

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
}

################################################################################
# Docker Compose Detection Function
################################################################################

detect_docker_compose() {
    # First try the new plugin-based compose
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        return 0
    fi

    # Then try the standalone docker-compose
    if docker-compose --version >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
        return 0
    fi

    err "Neither docker compose plugin nor docker-compose standalone is installed"
}

################################################################################
# System Check Functions
################################################################################

check_prerequisites() {
    # Check required commands
    for cmd in unzip docker runc read; do
        need_cmd "$cmd"
    done

    # Check OS and SELinux
    check_os_distro
    check_selinux
    check_docker_group
}

check_os_distro() {
    echo "Checking OS distribution..."
    local distribution
    distribution=$(awk -F= '$1=="ID_LIKE" { print $2 ;}' /etc/os-release | tr -d '"')

    if [[ "$distribution" =~ ^(fedora|debian)$ ]]; then
        printf "${GREEN}Supported (✿°ᴗ°)${NC}\n"
        return 0
    else
        err "Your OS distribution ($distribution) is not supported"
    fi
}

check_selinux() {
    if ! selinuxenabled; then
        echo "SELinux is DISABLED"
    else
        KEYCLOAK_VOLUME="$KEYCLOAK_VOLUME:Z"
        VOLUME_HUB_ENT="$VOLUME_HUB_ENT:Z"
        VOLUME_HUB_ENT_LIBS="$VOLUME_HUB_ENT_LIBS:Z"
        echo "SELinux is ENABLED"
    fi
}

check_docker_group() {
    echo "Checking if current user is added to the docker group"
    if [[ ! $(groups) =~ docker ]] && [[ $(whoami) != "root" ]]; then
        err "Current user either needs to be added to the docker group or this script should be run by root"
    fi
}

################################################################################
# Resource Check Functions
################################################################################

kb_to_gb() {
    echo $(($1/1024/1024))
}

get_system_resources() {
    local -n cpu=$1
    local -n mem=$2
    local -n disk=$3

    cpu=$(nproc --all)
    mem=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    disk=$(df -Ph / | awk 'NR==2 {print $4}' | tr -dc '0-9')
}

check_hw_requirements() {
    local option=$1
    local cpu_total mem_total disk_free

    print_requirements "$option"
    get_system_resources cpu_total mem_total disk_free

    # Display system information
    printf "\nSystem Resources:\n"
    printf "CPU: %d cores\n" "$cpu_total"
    printf "RAM: %dGB available (%d KB)\n" "$(kb_to_gb $mem_total)" "$mem_total"
    printf "DISK: %dGB available\n\n" "$disk_free"

    validate_resources "$option" "$cpu_total" "$mem_total" "$disk_free"
}

validate_resources() {
    local option=$1 cpu_total=$2 mem_total=$3 disk_free=$4

    [[ $cpu_total -lt $MIN_CPU ]] && err "Node should have minimum $MIN_CPU CPUs"

    case $option in
        1)  # DB on separate node
            [[ $(kb_to_gb $mem_total) -lt $MIN_RAM_SEPARATE ]] &&
                err "Node should have minimum ${MIN_RAM_SEPARATE}GB RAM"
            [[ $disk_free -lt $MIN_DISK_SEPARATE ]] &&
                err "Node should have minimum ${MIN_DISK_SEPARATE}GB disk space"
            ;;
        2)  # DB on this node
            [[ $(kb_to_gb $mem_total) -lt $MIN_RAM_COMBINED ]] &&
                err "Node should have minimum ${MIN_RAM_COMBINED}GB RAM"
            [[ $disk_free -lt $MIN_DISK_COMBINED ]] &&
                err "Node should have minimum ${MIN_DISK_COMBINED}GB disk space"
            ;;
        *)
            err "Invalid parameter. Use 1 or 2"
            ;;
    esac

    printf "${GREEN}Hardware requirements are met (✿°ᴗ°)${NC}\n"
}

################################################################################
# Interactive Configuration Functions
################################################################################

gather_new_config() {
    # Database configuration
    configure_database

    # Monitoring configuration
    configure_monitoring

    # Screen configuration
    configure_screen

    # Docker registry configuration
    configure_docker_registry

    # Database connection details
    configure_db_connection

    # Hub Enterprise configuration
    configure_hub_enterprise
}

configure_database() {
    echo "Do you have Postgres DB already provisioned? (y/n)"
    read -r installed_db

    case "$installed_db" in
        y)
            echo "Is Postgres DB provisioned on this node? (y/n)"
            read -r db_on_this_node
            case "$db_on_this_node" in
                y) option_db="2" ;;
                n) option_db="1" ;;
                *) err "Illegal db option." ;;
            esac
            ;;
        n)
            option_db="2"
            ;;
        *)
            err "Illegal db input option."
            ;;
    esac

    # Check hardware requirements based on database option
    check_hw_requirements "$option_db" || return 1
}

configure_monitoring() {
    echo "Do you need to install monitoring? (y/n)"
    read -r install_monitoring
    if [[ "$install_monitoring" != "y" && "$install_monitoring" != "n" ]]; then
        err "Illegal monitor option."
    fi
}

configure_screen() {
    echo "Do you need to install Emulator screen? (y/n)"
    read -r install_screen
    if [[ "$install_screen" != "y" && "$install_screen" != "n" ]]; then
        err "Illegal screen input option."
    fi

    export OL_SCREEN=false
    export OL_SCREEN_PORT='1512'

    if [ "$install_screen" == "y" ]; then
        read -e -rp "Enter Emulator screen port: " -i "1512" OL_SCREEN_PORT
        export OL_SCREEN=true
    fi
}

configure_docker_registry() {
    echo "Do you need to download docker images from your registry? (y/n)"
    read -r need_dl_docker_image

    case "$need_dl_docker_image" in
        y)
            configure_registry_access
            configure_image_tags
            ;;
        n)
            restore_images_with_vars
            ;;
        *)
            err "Illegal option."
            ;;
    esac
}

configure_registry_access() {
    read -r -p "Enter registry URL: " registry_url
    echo "Do you need to supply username/password pair for the download? (y/n)"
    read -r need_registry_creds

    if [ "$need_registry_creds" == "y" ]; then
        read -r -p "Enter registry username: " registry_username
        read -r -s -p "Enter registry password: " registry_password
        echo # New line after password input
        docker login -u "$registry_username" -p "$registry_password" "$registry_url" ||
            err "Docker login failed"
    elif [ "$need_registry_creds" != "n" ]; then
        err "Illegal option."
    fi
}

configure_image_tags() {
    read -e -rp "Enter name and tag of the Keycloak image: " KEYCLOAK_REGISTRY_IMAGE_TAG
    read -e -rp "Enter name and tag of the Hub Enterprise DB migration image: " HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG
    read -e -rp "Enter name and tag of the Hub Enterprise image: " HUB_ENT_REGISTRY_IMAGE_TAG

    export KEYCLOAK_REGISTRY_IMAGE_TAG
    export HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG
    export HUB_ENT_REGISTRY_IMAGE_TAG

    docker_pull

    if [ "$installed_db" == "n" ]; then
        read -e -rp "Enter name and tag of the Postgres image: " POSTGRES_REGISTRY_IMAGE_TAG
        export POSTGRES_REGISTRY_IMAGE_TAG
        docker_pull_postgres
    fi

    if [ "$install_monitoring" == "y" ]; then
        read -e -rp "Enter name and tag of the LOKI image: " LOKI_REGISTRY_IMAGE_TAG
        read -e -rp "Enter name and tag of the GRAFANA image: " GRAFANA_REGISTRY_IMAGE_TAG
        read -e -rp "Enter name and tag of the PROMETHEUS image: " PROMETHEUS_REGISTRY_IMAGE_TAG
        read -e -rp "Enter name and tag of the PUSHGATEWAY image: " PUSHGATEWAY_REGISTRY_IMAGE_TAG

        export LOKI_REGISTRY_IMAGE_TAG GRAFANA_REGISTRY_IMAGE_TAG
        export PROMETHEUS_REGISTRY_IMAGE_TAG PUSHGATEWAY_REGISTRY_IMAGE_TAG

        docker_pull_monitoring
    fi
}

configure_db_connection() {
    printf "\nDATABASE\n"
    read -e -rp "Enter Postgres host: " -i "postgres" OL_DB_HOST
    read -e -rp "Enter Postgres name: " -i "postgres" OL_DB_NAME
    read -e -rp "Enter Postgres port: " -i "5432" OL_DB_PORT
    read -e -rp "Enter Postgres username: " -i "postgres" POSTGRES_USER

    if [ "$installed_db" == "y" ]; then
        read -e -rsp "Enter Postgres password: " POSTGRES_PASSWORD
        echo # New line after password input
        read -e -rsp "Enter Postgres admin password: " POSTGRESQL_ADMIN_PASSWORD
        echo # New line after password input
    else
        read -e -rp "Enter Postgres password: " -i "postgres" POSTGRES_PASSWORD
        read -e -rp "Enter Postgres admin password: " -i "postgres" POSTGRESQL_ADMIN_PASSWORD
    fi

    export OL_DB_HOST OL_DB_NAME OL_DB_PORT POSTGRES_USER POSTGRES_PASSWORD POSTGRESQL_ADMIN_PASSWORD
}

configure_hub_enterprise() {
    printf "\nHUB ENTERPRISE\n"
    read -e -rp "Enter URL which will be used to access the OpenLegacy Hub Web UI: " OL_HUB_URL
    export OL_HUB_URL
    replace_ol_hub_url
}

################################################################################
# Docker Functions
################################################################################
restore_images_with_vars() {
    echo "Restoring docker images"

    # Declare and set BASE_PATH if not set externally
    declare BASE_PATH="${BASE_PATH:-.}"

    # Define registry images with their default values
    declare -A registry_images=(
        ["hub-enterprise"]="openlegacy/hub-enterprise"
        ["hub-enterprise-db-migration"]="openlegacy/hub-enterprise-db-migration"
        ["openlegacy-keycloak"]="openlegacy/openlegacy-keycloak"
        ["postgres"]="postgres"
    )

    # Define variable mappings for tags
    declare -A tag_vars=(
        ["hub-enterprise"]="HUB_ENT_TAG"
        ["hub-enterprise-db-migration"]="HUB_ENT_DB_MIGR_TAG"
        ["openlegacy-keycloak"]="KEYCLOAK_TAG"
        ["postgres"]="POSTGRES_TAG"
    )

    # Define export variable mappings
    declare -A export_vars=(
        ["hub-enterprise"]="HUB_ENT_REGISTRY_IMAGE_TAG"
        ["hub-enterprise-db-migration"]="HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG"
        ["openlegacy-keycloak"]="KEYCLOAK_REGISTRY_IMAGE_TAG"
        ["postgres"]="POSTGRES_REGISTRY_IMAGE_TAG"
    )

    # Define registry variable mappings
    declare -A registry_vars=(
        ["hub-enterprise"]="HUB_ENT_REGISTRY_IMAGE"
        ["hub-enterprise-db-migration"]="HUB_ENT_DB_MIGR_REGISTRY_IMAGE"
        ["openlegacy-keycloak"]="KEYCLOAK_REGISTRY_IMAGE"
        ["postgres"]="POSTGRES_REGISTRY_IMAGE"
    )

    # Process each service
    for service in "${!registry_images[@]}"; do
        found=0
        for file in "${BASE_PATH}"/${service}*.tar; do
            if [[ -f "$file" ]]; then
                # Extract tag using parameter expansion
                tag="${file#*:}"         # Remove everything up to first ':'
                tag="${tag%.tar}"        # Remove .tar extension

                # Store tag in corresponding variable
                declare "${tag_vars[$service]}=$tag"
                found=1
                echo "Found ${service} with tag: ${tag}"
                break
            fi
        done

        # Error handling if no matching file was found
        if (( ! found )); then
            echo "Error: No matching file found for $service in ${BASE_PATH}" >&2
            return 1
        fi
    done

    # Export the final image tags and registry images in a loop
    for service in "${!registry_images[@]}"; do
        tag_var="${tag_vars[$service]}"
        export_var="${export_vars[$service]}"
        registry_var="${registry_vars[$service]}"

        # Export the full image tag (registry/image:tag)
        export "${export_var}=${registry_images[$service]}:${!tag_var}"
        # Export the registry image name separately
        export "${registry_var}=${registry_images[$service]}"

        echo "Exported ${export_var}=${registry_images[$service]}:${!tag_var}"
    done

    # Configure monitoring images if needed
    if [ "$install_monitoring" == "y" ]; then
        configure_monitoring_images || return 1
    fi

    restore_docker_images "$installed_db" "$install_monitoring" || return 1
}

restore_docker_images() {
    local installed_db=$1
    local install_monitoring=$2

    echo "Restoring docker images..."

    # Restore core images
    docker load -i "$BASE_PATH/${KEYCLOAK_REGISTRY_IMAGE_TAG##*/}.tar" || err "Failed to restore Keycloak image"
    docker load -i "$BASE_PATH/${HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG##*/}.tar" || err "Failed to restore DB migration image"
    docker load -i "$BASE_PATH/${HUB_ENT_REGISTRY_IMAGE_TAG##*/}.tar" || err "Failed to restore Hub Enterprise image"

    # Restore PostgreSQL image if needed
    if [ "$installed_db" == "n" ]; then
        docker load -i "$BASE_PATH/${POSTGRES_REGISTRY_IMAGE_TAG##*/}.tar" || err "Failed to restore PostgreSQL image"
    fi

    # Restore monitoring images if needed
    if [ "$install_monitoring" == "y" ]; then
        docker load -i "$BASE_PATH/${LOKI_REGISTRY_IMAGE_TAG##*/}.tar" || err "Failed to restore Loki image"
        docker load -i "$BASE_PATH/${GRAFANA_REGISTRY_IMAGE_TAG##*/}.tar" || err "Failed to restore Grafana image"
        docker load -i "$BASE_PATH/${PROMETHEUS_REGISTRY_IMAGE_TAG##*/}.tar" || err "Failed to restore Prometheus image"
        docker load -i "$BASE_PATH/${PUSHGATEWAY_REGISTRY_IMAGE_TAG##*/}.tar" || err "Failed to restore Pushgateway image"
    fi

    printf "${GREEN}Docker images restored successfully${NC}\n"
}

configure_monitoring_images() {
    # Define registry images
    declare -A registry_images=(
        ["loki"]="grafana/loki"
        ["grafana"]="grafana/grafana"
        ["prometheus"]="prom/prometheus"
        ["pushgateway"]="prom/pushgateway"
    )

    # Define variable mappings for tags
    declare -A tag_vars=(
        ["loki"]="LOKI_TAG"
        ["grafana"]="GRAFANA_TAG"
        ["prometheus"]="PROMETHEUS_TAG"
        ["pushgateway"]="PUSHGATEWAY_TAG"
    )

    # Process each service
    for service in "${!registry_images[@]}"; do
        found=0
        for file in "$BASE_PATH"/*"$service:"*; do
            if [[ -f "$file" ]]; then
                # Extract tag using parameter expansion
                tag="${file##*:}"    # Remove everything up to last ':'
                tag="${tag%.*}"      # Remove extension

                # Store tag in corresponding variable
                declare "${tag_vars[$service]}=$tag"
                found=1
                break
            fi
        done

        # Error handling if no matching file was found
        if (( ! found )); then
            echo "Error: No matching file found for $service in $BASE_PATH" >&2
            return 1
        fi
    done

    # Export the final image tags and generate output
    for service in "${!registry_images[@]}"; do
        tag_var="${tag_vars[$service]}"
        export_var="${service^^}_REGISTRY_IMAGE_TAG"  # Convert to uppercase
        export "${export_var}=${registry_images[$service]}:${!tag_var}"
        echo "Exported ${export_var}=${registry_images[$service]}:${!tag_var}"
    done
}


docker_pull() {
    docker pull "$KEYCLOAK_REGISTRY_IMAGE_TAG" || err "Failed to pull Keycloak image"
    docker pull "$HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG" || err "Failed to pull DB migration image"
    docker pull "$HUB_ENT_REGISTRY_IMAGE_TAG" || err "Failed to pull Hub Enterprise image"
}

docker_pull_postgres() {
    docker pull "$POSTGRES_REGISTRY_IMAGE_TAG" || err "Failed to pull Postgres image"
}

docker_pull_monitoring() {
    docker pull "$LOKI_REGISTRY_IMAGE_TAG" || err "Failed to pull Loki image"
    docker pull "$GRAFANA_REGISTRY_IMAGE_TAG" || err "Failed to pull Grafana image"
    docker pull "$PROMETHEUS_REGISTRY_IMAGE_TAG" || err "Failed to pull Prometheus image"
    docker pull "$PUSHGATEWAY_REGISTRY_IMAGE_TAG" || err "Failed to pull Pushgateway image"
}

docker_up() {
    local installed_db=$1
    local install_monitoring=$2

    # Create docker network
    docker network create hub-enterprise || true

    # Deploy containers based on configuration
    deploy_database "$installed_db"
    deploy_monitoring "$install_monitoring"
    deploy_hub_enterprise
}

deploy_database() {
    local installed_db=$1
    if [ "$installed_db" == "n" ]; then
        $COMPOSE_CMD -f "$BASE_PATH/docker-compose/postgres.yaml" up -d
        printf "${BLUE}Waiting for database initialization...${NC}\n"
        sleep 10
        check_docker_container_status postgres
    fi
}

deploy_monitoring() {
    local install_monitoring=$1
    if [ "$install_monitoring" == "y" ]; then
        $COMPOSE_CMD -f "$BASE_PATH/docker-compose/monitoring/monitoring.yaml" up -d
        printf "${BLUE}Waiting for monitoring initialization...${NC}\n"
        sleep 30
        for container in loki prometheus pushgateway grafana; do
            check_docker_container_status "$container"
        done
    fi
}

deploy_hub_enterprise() {
    # Deploy DB migration
    $COMPOSE_CMD -f "$BASE_PATH/docker-compose/hub-enterprise-db-migration.yaml" up -d
    sleep 5
    check_docker_container_status hub-enterprise-db-migration

    # Deploy Keycloak
    $COMPOSE_CMD -f "$BASE_PATH/docker-compose/keycloak.yaml" up -d
    sleep 60
    check_docker_container_status keycloak

    # Deploy Hub Enterprise
    if [ "${OL_SCREEN:-}" = "true" ]; then
        $COMPOSE_CMD --profile ol-screen-profile -f "$BASE_PATH/docker-compose/hub-enterprise.yaml" up -d
    else
        $COMPOSE_CMD --profile default -f "$BASE_PATH/docker-compose/hub-enterprise.yaml" up -d
    fi
    sleep 20
}

check_docker_container_status() {
    local container_name=$1
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        # Get container status
        local status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null)

        # For regular containers
        if [[ "$status" == "running" ]]; then
            echo "Container $container_name is running"
            return 0
        fi

        # For jobs/one-off containers
        if [[ "$status" == "exited" ]]; then
            # Check exit code
            local exit_code=$(docker inspect --format='{{.State.ExitCode}}' "$container_name" 2>/dev/null)
            if [[ "$exit_code" == "0" ]]; then
                echo "Job $container_name completed successfully"
                return 0
            else
                # Show logs if job failed
                echo "Job $container_name failed with exit code $exit_code"
                docker logs "$container_name"
                return 1
            fi
        fi

        sleep 2
        ((retry_count++))
        echo "Waiting for container/job $container_name (attempt $retry_count of $max_retries)..."
    done

    err "Container/Job $container_name failed to complete successfully after $max_retries attempts"
    # Show logs for debugging
    echo "Container logs:"
    docker logs "$container_name"
    return 1
}

################################################################################
# Configuration Functions
################################################################################

setup_config() {
    mkdir -p "${BASE_PATH}"
    mkdir -p "${VOLUME_HUB_ENT%%:*}"
    mkdir -p "${VOLUME_HUB_ENT_LIBS%%:*}"

    chmod -R 777 "${VOLUME_HUB_ENT%%:*}"
    chmod -R 777 "${VOLUME_HUB_ENT_LIBS%%:*}"

    generate_ssl_config
    extract_compose_files
}

generate_ssl_config() {
    cat << EOF > "$BASE_PATH/config.cnf"
[req]
distinguished_name = OL_HUB
prompt = no

[OL_HUB]
commonName = OpenLegacy Hub
organizationName = OpenLegacy
EOF

    openssl req -newkey rsa:2048 -new -nodes -x509 -days 3650 \
        -keyout "$BASE_PATH/hub-ent.pem" -batch -config "$BASE_PATH/config.cnf" -noout

    export OL_HUB_PK_API_KEY_SIGN=$(cat "$BASE_PATH/hub-ent.pem")
    export OL_HUB_ENCRYPT_SECRET=$(openssl rand -base64 32 | tr -dc A-Za-z0-9 | head -c 32)
}

extract_compose_files() {
    tar -xf "$BASE_PATH/docker-compose-files.tar" --strip-components=6 -C "$BASE_PATH"
}

replace_ol_hub_url() {
    local search="localhost:8081"
    local replace="$OL_HUB_URL:8080"
    sed -i -e "s^${search}^${replace}^g" "$BASE_PATH/docker-compose/keycloak/realms/ol-hub-realm.json"
}

################################################################################
# Configuration Processing Functions
################################################################################

process_existing_config() {
    source "$CONFIG_FILE"

    # Check required environment variables
    check_export_vars $(
        cut -d= -f1 "$CONFIG_FILE" |
        grep -Ev '
          DB_PROVISIONED|
          DB_SAME_HOST|
          DOWNLOAD_DOCKER_IMAGES|
          REGISTRY_URL|
          REGISTRY_USERNAME|
          REGISTRY_PASSWORD|
          KEYCLOAK_REGISTRY_IMAGE_TAG|
          HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG|
          HUB_ENT_REGISTRY_IMAGE_TAG|
          POSTGRES_REGISTRY_IMAGE_TAG|
          MONITORING|
          LOKI_REGISTRY_IMAGE_TAG|
          GRAFANA_REGISTRY_IMAGE_TAG|
          PROMETHEUS_REGISTRY_IMAGE_TAG|
          PUSHGATEWAY_REGISTRY_IMAGE_TAG|
          OL_SCREEN|
          OL_SCREEN_PORT
        '
    )

    process_db_config
    check_hw_requirements "$option_db" || return 1
    process_monitoring_config
    process_docker_images
    replace_ol_hub_url
}

process_db_config() {
    if [ "$DB_PROVISIONED" == "true" ]; then
        installed_db="y"
        if [ "$DB_SAME_HOST" == "true" ]; then
            option_db="2"
        else
            option_db="1"
        fi
    elif [ "$DB_PROVISIONED" != "true" ]; then
        installed_db="n"
        option_db="2"
    else
        err "Illegal db option."
    fi
}

process_monitoring_config() {
    if [ "$MONITORING" == "true" ]; then
        install_monitoring="y"
    elif [ "$MONITORING" == "false" ]; then
        install_monitoring="n"
    else
        err "Illegal monitoring option."
    fi
}

process_docker_images() {
    if [ "$DOWNLOAD_DOCKER_IMAGES" == "true" ]; then
        if [[ -n "$REGISTRY_URL" ]]; then
            if [[ -n "${REGISTRY_USERNAME}" ]] && [[ -n "${REGISTRY_PASSWORD}" ]]; then
                docker login -u "$REGISTRY_USERNAME" -p "$REGISTRY_PASSWORD" "$REGISTRY_URL" || err "Docker login failed"
            fi
        fi

        export KEYCLOAK_REGISTRY_IMAGE_TAG
        export HUB_ENT_DB_MIGR_REGISTRY_IMAGE_TAG
        export HUB_ENT_REGISTRY_IMAGE_TAG

        docker_pull

        if [ "$installed_db" == "n" ]; then
            export POSTGRES_REGISTRY_IMAGE_TAG
            docker_pull_postgres
        fi

        if [ "$install_monitoring" == "y" ]; then
            export LOKI_REGISTRY_IMAGE_TAG
            export GRAFANA_REGISTRY_IMAGE_TAG
            export PROMETHEUS_REGISTRY_IMAGE_TAG
            export PUSHGATEWAY_REGISTRY_IMAGE_TAG
            docker_pull_monitoring
        fi
    elif [ "$DOWNLOAD_DOCKER_IMAGES" == "false" ]; then
        restore_images_with_vars
    else
        err "Illegal download images values."
    fi
}

# Add this to your check_export_vars function if it doesn't exist
check_export_vars() {
    local var
    for var in "$@"; do
        if [[ -z "${!var:-}" ]]; then
            err "Required variable $var is not set in config file"
        fi
    done
}
################################################################################
# Main Function
################################################################################

main() {
    print_banner

    # Detect docker compose command early
    detect_docker_compose

    check_prerequisites
    setup_config

    # Load existing config if available
    if [[ -f "$CONFIG_FILE" ]]; then
        process_existing_config
    else
        gather_new_config
    fi

    # Deploy services
    docker_up "$installed_db" "$install_monitoring"

    printf "${GREEN}Installation completed successfully! ٩(^‿^)۶${NC}\n"
}

# Start installation
main "$@" || exit 1

