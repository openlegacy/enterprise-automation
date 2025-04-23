#!/bin/bash

set -o nounset  # Exit on uninitialized variable
set -o errexit  # Exit on error
set -o pipefail # Exit on pipe failures

# set -x

######################################################################################
################################## CONSTANTS ##########################################
########################################################################################

# Colors for output
declare -r GREEN='\033[0;32m'
declare -r BLUE='\033[1;36m'
declare -r PURPLE='\033[0;35m'
declare -r YELLOW='\033[1;33m'
declare -r ORANGE='\033[38;5;208m'
declare -r NC='\033[0m'

# Banner styles
declare -r BANNER_STYLE="
    ███████                                  ████
  ███░░░░░███                               ░░███
 ███     ░░███ ████████   ██████  ████████   ░███   ██████   ███████  ██████    ██████  █████ ████
░███      ░███░░███░░███ ███░░███░░███░░███  ░███  ███░░███ ███░░███ ░░░░░███  ███░░███░░███ ░███
░███      ░███ ░███ ░███░███████  ░███ ░███  ░███ ░███████ ░███ ░███  ███████ ░███ ░░░  ░███ ░███
░░███     ███  ░███ ░███░███░░░   ░███ ░███  ░███ ░███░░░  ░███ ░███ ███░░███ ░███  ███ ░███ ░███
 ░░░███████░   ░███████ ░░██████  ████ █████ █████░░██████ ░░███████░░████████░░██████  ░░███████
   ░░░░░░░     ░███░░░   ░░░░░░  ░░░░ ░░░░░ ░░░░░  ░░░░░░   ░░░░░███ ░░░░░░░░  ░░░░░░    ░░░░░███
               ░███                                         ███ ░███                     ███ ░███
               █████                                       ░░██████                     ░░██████
              ░░░░░                                         ░░░░░░                       ░░░░░░

"
# Paths and defaults
declare -r BASE_PATH="$(pwd)/offline-installation"

declare -r HELM_CHARTS_ARCHIVE="${BASE_PATH}/hub-enterprise.tgz"
declare -r HELM_CHART_NAME="hub-enterprise"
declare -r HELM_VALUES_FILE_TEMPLATE="${BASE_PATH}/${HELM_CHART_NAME}/values-template.yaml"
declare -r HELM_VALUES_FILE="${BASE_PATH}/${HELM_CHART_NAME}/values.yaml"
declare -r KEYCLOAK_REALM="${BASE_PATH}/${HELM_CHART_NAME}/keycloak-realm.yaml"
declare -r CONFIG_FILE="${BASE_PATH}/installer-helm.conf"
version='_VERSION_'

# Add these to your variables initialization section
KEYCLOAK_IMAGE="${KEYCLOAK_IMAGE:-openlegacy/openlegacy-keycloak:26.1.2}"
HUB_ENT_DB_MIGR_IMAGE="${HUB_ENT_DB_MIGR_IMAGE:-openlegacy/hub-enterprise-db-migration:3.0.7}"
HUB_ENT_IMAGE="${HUB_ENT_IMAGE:-openlegacy/hub-enterprise:3.0.7}"
OL_HUB_URL="${OL_HUB_URL:-}"
OL_KEYCLOAK_URL="${OL_KEYCLOAK_URL:-}"
LOKI_IMAGE="${LOKI_IMAGE:-grafana/loki:2.7.1}"
GRAFANA_IMAGE="${GRAFANA_IMAGE:-grafana/grafana:9.3}"
PROMETHEUS_IMAGE="${PROMETHEUS_IMAGE:-prom/prometheus:v2.40.6}"
PUSHGATEWAY_IMAGE="${PUSHGATEWAY_IMAGE:-prom/pushgateway:v1.5.1}"
OL_SCREEN_PORT="${OL_SCREEN_PORT:-1512}"

# Default values
declare -A DEFAULTS=(
    ["OL_DB_HOST"]="hub-enterprise-postgres"
    ["OL_DB_NAME"]="postgres"
    ["OL_DB_PORT"]="5432"
    ["OL_DB_USER"]="postgres"
    ["k8s_namespace"]="hub-enterprise"
    ["MONITORING"]="false"
)

declare -A REQUIRED_VARS=(
    ["OL_HUB_URL"]="Hub URL (e.g. https://hub-enterprise)"
    ["OL_KEYCLOAK_URL"]="Keycloak URL (e.g. https://hub-enterprise-keycloak)"
    ["OL_DB_HOST"]="Database host"
    ["OL_DB_PORT"]="Database port"
    ["OL_DB_NAME"]="Database name"
    ["OL_DB_USER"]="Database username"
    ["OL_DB_PASSWORD"]="Database password"
    ["K8S_DISTRIBUTION"]="Kubernetes distribution (k8s or openshift)"
    ["k8s_namespace"]="Kubernetes namespace"
    ["KEYCLOAK_IMAGE"]="Keycloak image with tag"
    ["HUB_ENT_DB_MIGR_IMAGE"]="Hub Enterprise DB migration image with tag"
    ["HUB_ENT_IMAGE"]="Hub Enterprise image with tag"
    ["MONITORING"]="Enable monitoring (true/false)"
    ["OL_SCREEN_PORT"]="Screen emulator port (default: 1512)"
)

# Monitoring-specific required variables
declare -A MONITORING_VARS=(
    ["LOKI_IMAGE"]="Loki image with tag"
    ["GRAFANA_IMAGE"]="Grafana image with tag"
    ["PROMETHEUS_IMAGE"]="Prometheus image with tag"
    ["PUSHGATEWAY_IMAGE"]="Pushgateway image with tag"
)


########################################################################################
################################## BANNER FUNCTIONS ###################################
########################################################################################

display_banner() {

    local version=${1:-"1.0.0"}
    local show_info=${2:-false}

    # Clear screen
    clear
    printf "${ORANGE}%s${NC}" "$BANNER_STYLE"

    # Display additional information if requested
    if [[ "$show_info" == true ]]; then
        printf "\n${YELLOW}Version: %s${NC}\n" "$version"
        printf "${YELLOW}Date: %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf "${YELLOW}System: %s${NC}\n" "$(uname -s) $(uname -r)"
        printf "${YELLOW}User: %s${NC}\n" "$(whoami)"
        printf "\n${GREEN}Starting installation process...${NC}\n"
        printf "${GREEN}═══════════════════════════════════════════════════${NC}\n\n"
    fi
}

display_section_banner() {
    local title=$1
    local char="═"
    local width=70
    local padding=$(( (width - ${#title} - 2) / 2 ))

    printf "\n${BLUE}%${width}s${NC}\n" | tr " " "$char"
    printf "${BLUE}%*s %s %*s${NC}\n" $padding "" "$title" $padding ""
    printf "${BLUE}%${width}s${NC}\n" | tr " " "$char"
}

########################################################################################
################################## LOGGING ############################################
########################################################################################

log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "[%s] ${PURPLE}%s${NC}: %s\n" "$timestamp" "$level" "$message"
}


err() {
    log "ERROR" "$1" >&2
    exit 1
}

########################################################################################
################################## UTILITIES ##########################################
########################################################################################

verify_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "Required command '$1' not found. Please install it first."
    fi
}

verify_prerequisites() {
    log "INFO" "Verifying prerequisites..."
    local required_commands=("kubectl" "helm" "openssl")
    for cmd in "${required_commands[@]}"; do
        verify_command "$cmd"
    done
}

verify_context() {
    local current_context
    current_context=$(kubectl config current-context) || {
        err "Failed to get current kubernetes context"
    }
   
    printf "Current kubernetes context is ${BLUE}%s${NC}\nDo you want to proceed? (y/n) " "$current_context"
    read -r context_is_correct

    case $context_is_correct in
        y|Y)
            log "INFO" "Proceeding with installation..."
            return 0
            ;;
        n|N)
            read -e -rp "Enter the correct k8s cluster name: " cluster_name
            kubectl config use-context "$cluster_name"
            log "INFO" "Changed kubernetes context to $(kubectl config current-context)"
            ;;
        *)
            err "Invalid option. Please enter 'y' or 'n'"
            ;;
    esac
}

########################################################################################
################################## CONFIGURATION #####################################
########################################################################################


prepare_keycloak_realm() {
    log "INFO" "Preparing Keycloak realm configuration"

    # Extract hostname from Hub URL (removes protocol and path)
    OL_HUB_URL_SHORT="$(echo "$OL_HUB_URL" | cut -d/ -f3)"
    export OL_HUB_URL_SHORT

    # Extract protocol (http/https) from Hub URL
    OL_HUB_URL_SSL="$(echo "$OL_HUB_URL" | cut -d: -f1)"

    # Replace localhost:8081 with actual Hub hostname
    search="localhost:8081"
    replace="$OL_HUB_URL_SHORT"
    sed -ie "s/$search/$replace/" "$BASE_PATH/hub-enterprise/keycloak-realm.yaml"

    # If using HTTPS, update protocol accordingly
    if [[ $OL_HUB_URL_SSL == "https" ]]; then
        search="http:"
        replace="$OL_HUB_URL_SSL:"
        sed -ie "s/$search/$replace/" "$BASE_PATH/hub-enterprise/keycloak-realm.yaml"
    fi

    # Extract hostname from Keycloak URL (removes protocol and path)
    OL_KEYCLOAK_URL_SHORT="$(echo "$OL_KEYCLOAK_URL" | cut -d/ -f3)"
    export OL_KEYCLOAK_URL_SHORT

    log "INFO" "Keycloak realm configuration updated successfully"
}

check_export_vars() {
    # Verify all required environment variables are exported
    local missing_vars=()
    local var=''

    for var in "${!REQUIRED_VARS[@]}"; do
        if [[ -v "$var" ]]; then
            # Variable exists
            echo "$var=${!var}"
            # Export the variable if it has a value
            export "$var=${!var}"
        else
            missing_vars+=("$var")
            log "WARNING" "Required variable $var (${REQUIRED_VARS[$var]}) is not set"
        fi
    done

    # sleep 1000
    if (( ${#missing_vars[@]} > 0 )); then
        err "The following required variables are not set: ${missing_vars[*]}"
    fi
}

check_k8s_namespace() {
  namespace_exists=$(kubectl get namespace "$k8s_namespace")
  if [[ -z "$namespace_exists" ]]; then
    err "Namespace doesn't exist. Create the namespace and run the script again."
  fi
}

clean_helm_values_openshift() {
  search="secretName: SECRET_NAME"; sed -ie "/$search/d" "$HELM_VALUES_FILE_TEMPLATE"
  # search="podSecurityContext:"; sed -ie "/$search/d" $helm_values_file_template
  search="fsGroup: 3000"; sed -ie "/$search/d" "$HELM_VALUES_FILE_TEMPLATE"
}

remove_registry_credentials() {
  search='username: $REGISTRY_USERNAME'; sed -ie "/$search/d" "$HELM_VALUES_FILE_TEMPLATE"
  search='password: $REGISTRY_PASSWORD'; sed -ie "/$search/d" "$HELM_VALUES_FILE_TEMPLATE"
}

handle_registry_credentials() {
    if [[ -n "${REGISTRY_USERNAME:-}" ]] && [[ -n "${REGISTRY_PASSWORD:-}" ]]; then
        export REGISTRY_USERNAME REGISTRY_PASSWORD
        add_registry_credentials
    else
        remove_registry_credentials
    fi
}

handle_k8s_distribution() {
    case "${K8S_DISTRIBUTION:-}" in
        openshift)
            INGRESS_TYPE=$K8S_DISTRIBUTION
            export INGRESS_TYPE
            clean_helm_values_openshift
            ;;
        k8s)
            export INGRESS_TYPE
            handle_k8s_certificates
            ;;
        *)
            err "Invalid K8S_DISTRIBUTION value"
            ;;
    esac
}

########################################################################################
################################## INTERACTIVE CONFIG ###############################
########################################################################################


gather_registry_info() {
    display_section_banner "Registry Configuration"

    # Ask for registry URL
    read -e -rp "Enter registry URL (example: openlegacy): " -i "openlegacy" REGISTRY_URL

    if [[ -z "$REGISTRY_URL" ]]; then
        err "Registry URL cannot be empty"
    fi

    # Ask if credentials are needed
    read -e -rp "Does this registry require authentication? (y/n): " needs_auth

    if [[ "${needs_auth,,}" == "y" ]]; then
        read -e -rp "Enter registry username: " REGISTRY_USERNAME
        read -e -rsp "Enter registry password: " REGISTRY_PASSWORD
        echo "" # New line after password input

        # Validate credentials
        if [[ -z "$REGISTRY_USERNAME" ]] || [[ -z "$REGISTRY_PASSWORD" ]]; then
            err "Registry credentials cannot be empty"
        fi

        export REGISTRY_USERNAME REGISTRY_PASSWORD
        log "INFO" "Registry credentials configured"
    else
        # Clear any existing credentials
        REGISTRY_USERNAME=""
        REGISTRY_PASSWORD=""
        log "INFO" "Registry configured without authentication"
    fi

    # Ask for images section
    display_section_banner "Images Configuration"

    # Core Images
    read -e -rp "Enter name and tag of the Keycloak image: " -i "openlegacy/openlegacy-keycloak:26.1.2" KEYCLOAK_IMAGE
    read -e -rp "Enter name and tag of the Hub Enterprise DB migration image: " -i "openlegacy/hub-enterprise-db-migration:3.0.7" HUB_ENT_DB_MIGR_IMAGE
    read -e -rp "Enter name and tag of the Hub Enterprise image: " -i "openlegacy/hub-enterprise:3.0.7" HUB_ENT_IMAGE

    # URLs Configuration
    display_section_banner "URLs Configuration"
    read -e -rp "Enter URL which will be used to access the OpenLegacy Hub Web UI (e.g. https://hub-enterprise): " OL_HUB_URL
    read -e -rp "Enter URL which will be used to access the Keycloak Web UI (e.g. https://hub-enterprise-keycloak): " OL_KEYCLOAK_URL

    export REGISTRY_URL KEYCLOAK_IMAGE HUB_ENT_DB_MIGR_IMAGE HUB_ENT_IMAGE OL_HUB_URL OL_KEYCLOAK_URL
    log "INFO" "Registry and images configuration completed"
}

gather_monitoring_info() {
    display_section_banner "Monitoring Configuration"

    echo "Do you need to install monitoring? (y/n)"
    read -r install_monitoring

    if [ "$install_monitoring" != "y" ] && [ "$install_monitoring" != "n" ]; then
        err "Illegal option."
    fi

    if [ "$install_monitoring" == "y" ]; then
        MONITORING="true"
        read -e -rp "Enter name and tag of the LOKI image: " -i "grafana/loki:2.7.1" LOKI_IMAGE
        read -e -rp "Enter name and tag of the GRAFANA image: " -i "grafana/grafana:9.3" GRAFANA_IMAGE
        read -e -rp "Enter name and tag of the PROMETHEUS image: " -i "prom/prometheus:v2.40.6" PROMETHEUS_IMAGE
        read -e -rp "Enter name and tag of the PUSHGATEWAY image: " -i "prom/pushgateway:v1.5.1" PUSHGATEWAY_IMAGE

        export LOKI_IMAGE GRAFANA_IMAGE PROMETHEUS_IMAGE PUSHGATEWAY_IMAGE
    else
        MONITORING="false"
    fi

    # Emulator screen configuration
    echo "Do you need to install Emulator screen? (y/n)"
    read -r install_screen

    if [ "$install_screen" == "y" ]; then
        read -e -rp "Enter Emulator screen port: " -i "1512" OL_SCREEN_PORT
        export OL_SCREEN_PORT
    fi

    export MONITORING
}


gather_kubernetes_info() {
    display_section_banner "Kubernetes Configuration"

    # Get K8s distribution
    printf "Select Kubernetes distribution:\n"
    printf "1) Kubernetes\n"
    printf "2) OpenShift\n"
    read -e -rp "Enter choice [1-2]: " k8s_choice

    case $k8s_choice in
        1)
            K8S_DISTRIBUTION="k8s"
            gather_k8s_certificates
            ;;
        2)
            K8S_DISTRIBUTION="openshift"
            ;;
        *)
            err "Invalid selection. Please choose 1 or 2"
            ;;
    esac

    # Get namespace
    read -e -rp "Enter namespace (default: ${DEFAULTS["k8s_namespace"]}): " k8s_namespace
    k8s_namespace=${k8s_namespace:-${DEFAULTS["k8s_namespace"]}}

    export K8S_DISTRIBUTION k8s_namespace
}

gather_k8s_certificates() {
    read -e -rp "Do you want to use custom TLS certificates? (y/n): " use_custom_certs

    if [[ "${use_custom_certs,,}" == "y" ]]; then
        read -e -rp "Enter TLS secret name: " SECRET_NAME
        export SECRET_NAME
    fi
}

gather_database_info() {
    display_section_banner "Database Configuration"

    # Database host
    read -e -rp "Enter database host (default: ${DEFAULTS["OL_DB_HOST"]}): " OL_DB_HOST
    OL_DB_HOST=${OL_DB_HOST:-${DEFAULTS["OL_DB_HOST"]}}

    # Database port
    read -e -rp "Enter database port (default: ${DEFAULTS["OL_DB_PORT"]}): " OL_DB_PORT
    OL_DB_PORT=${OL_DB_PORT:-${DEFAULTS["OL_DB_PORT"]}}

    # Database name
    read -e -rp "Enter database name (default: ${DEFAULTS["OL_DB_NAME"]}): " OL_DB_NAME
    OL_DB_NAME=${OL_DB_NAME:-${DEFAULTS["OL_DB_NAME"]}}

    # Database user
    read -e -rp "Enter database user (default: ${DEFAULTS["OL_DB_USER"]}): " OL_DB_USER
    OL_DB_USER=${OL_DB_USER:-${DEFAULTS["OL_DB_USER"]}}

    # Database password
    read -e -rsp "Enter database password: " OL_DB_PASSWORD
    echo "" # New line after password input

    if [[ -z "$OL_DB_PASSWORD" ]]; then
        err "Database password cannot be empty"
    fi

    export OL_DB_HOST OL_DB_PORT OL_DB_NAME OL_DB_USER OL_DB_PASSWORD
}

save_configuration() {
    log "INFO" "Saving configuration to ${CONFIG_FILE}"

    # Create config file
    {
        echo "# OpenLegacy Hub Configuration"
        echo "# Generated on $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "# Images Configuration"
        echo "KEYCLOAK_IMAGE='${KEYCLOAK_IMAGE}'"
        echo "HUB_ENT_DB_MIGR_IMAGE='${HUB_ENT_DB_MIGR_IMAGE}'"
        echo "HUB_ENT_IMAGE='${HUB_ENT_IMAGE}'"
        echo ""
        echo "# Registry Configuration"
        [[ -n "${REGISTRY_URL}" ]] && echo "REGISTRY_URL='${REGISTRY_URL}'"
        [[ -n "${REGISTRY_USERNAME}" ]] && echo "REGISTRY_USERNAME='${REGISTRY_USERNAME}'"
        [[ -n "${REGISTRY_PASSWORD}" ]] && echo "REGISTRY_PASSWORD='${REGISTRY_PASSWORD}'"
        echo ""
        echo "# URLs Configuration"
        echo "OL_HUB_URL='${OL_HUB_URL}'"
        echo "OL_KEYCLOAK_URL='${OL_KEYCLOAK_URL}'"
        echo ""
        echo "# Kubernetes Configuration"
        echo "K8S_DISTRIBUTION='${K8S_DISTRIBUTION}'"
        echo "k8s_namespace='${k8s_namespace}'"
        [[ -n "${SECRET_NAME:-}" ]] && echo "SECRET_NAME='${SECRET_NAME}'"
        echo ""
        echo "# Database Configuration"
        echo "OL_DB_HOST='${OL_DB_HOST}'"
        echo "OL_DB_PORT='${OL_DB_PORT}'"
        echo "OL_DB_NAME='${OL_DB_NAME}'"
        echo "OL_DB_USER='${OL_DB_USER}'"
        echo "OL_DB_PASSWORD='${OL_DB_PASSWORD}'"
        echo ""
        echo "# Monitoring Configuration"
        echo "MONITORING='${MONITORING}'"
        if [ "${MONITORING}" == "true" ]; then
            echo "LOKI_IMAGE='${LOKI_IMAGE}'"
            echo "GRAFANA_IMAGE='${GRAFANA_IMAGE}'"
            echo "PROMETHEUS_IMAGE='${PROMETHEUS_IMAGE}'"
            echo "PUSHGATEWAY_IMAGE='${PUSHGATEWAY_IMAGE}'"
        fi
        [[ -n "${OL_SCREEN_PORT:-}" ]] && echo "OL_SCREEN_PORT='${OL_SCREEN_PORT}'"
    } > "$CONFIG_FILE"

    # Secure the config file
    chmod 600 "$CONFIG_FILE"

    log "INFO" "Configuration saved successfully"
}


gather_new_configuration() {
    log "INFO" "Starting interactive configuration..."

    gather_registry_info
    gather_kubernetes_info
    gather_database_info
    gather_monitoring_info

    # Save configuration
    save_configuration
}

########################################################################################
################################## INSTALLATION #####################################
########################################################################################
generate_certificates() {
    log "INFO" "Generating certificates"

    # Create OpenSSL config file
    touch "$BASE_PATH/config.cnf"
    cat << EOF > "$BASE_PATH/config.cnf"
[req]
distinguished_name = OL_HUB
prompt = no

[OL_HUB]
commonName = OpenLegacy Hub
organizationName = OpenLegacy
EOF

    # Generate certificate
    openssl req -newkey rsa:2048 -new -nodes -x509 -days 3650 \
        -keyout "$BASE_PATH/hub-ent.pem" \
        -batch -config "$BASE_PATH/config.cnf" -noout

    # Process the certificate for API key signing
    OL_HUB_PK_API_KEY_SIGN=$(awk '{printf "%s\\n", $0}' "$BASE_PATH/hub-ent.pem")
    export OL_HUB_PK_API_KEY_SIGN

    log "INFO" "Certificates generated successfully"
}

generate_secrets() {
    log "INFO" "Generating secrets"

    # Generate encryption secret
    local plain_string
    plain_string=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
    OL_HUB_ENCRYPT_SECRET="$plain_string"
    export OL_HUB_ENCRYPT_SECRET

    log "INFO" "Secrets generated successfully"
}



prepare_installation() {
    log "INFO" "Preparing installation files..."

    # Extract Helm charts
    tar -xf "$HELM_CHARTS_ARCHIVE" --strip-components=3 -C "$BASE_PATH"

    # Generate certificates and secrets
    generate_certificates
    generate_secrets

    # Generate values.yaml
    envsubst < "$HELM_VALUES_FILE_TEMPLATE" > "$HELM_VALUES_FILE"
}

install_hub_enterprise() {
    log "INFO" "Starting Hub Enterprise installation..."

    local install_args=(
        "$HELM_CHART_NAME"
        "$BASE_PATH/$HELM_CHART_NAME"
        --atomic
        --timeout 10m
        --namespace="$k8s_namespace"
        --values "$HELM_VALUES_FILE"
        --values "$KEYCLOAK_REALM"
    )

    # Add monitoring if enabled
    if [[ "${MONITORING:-false}" == "true" ]]; then
        install_args+=(--set "monitoring.deploy=true")
    fi

    # Dry run first
    log "INFO" "Performing dry run..."
    if ! helm upgrade --install "${install_args[@]}" --dry-run; then
        err "Dry run failed"
    fi

    # Actual installation
    log "INFO" "Performing actual installation..."
    if helm upgrade --install "${install_args[@]}"; then
        log "SUCCESS" "Installation completed successfully! ٩(^‿^)۶"
    else
        err "Installation failed"
    fi
}

validate_configuration() {
    local missing_vars=()
    local interactive_mode=false

    log "INFO" "Validating configuration..."

    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "WARNING" "Configuration file not found at $CONFIG_FILE"
        return 1
    fi

    # Source the config file
    source "$CONFIG_FILE"

    echo "${REQUIRED_VARS[@]}"

    declare -a missing_vars=()

    # Validate each required variable
    for var in "${!REQUIRED_VARS[@]}"; do
        value=${!var:-}
        if [[ -z "$value" ]]; then
            missing_vars+=("$var")
            log "WARNING" "Missing required variable: $var (${REQUIRED_VARS[$var]})"
        fi
    done

    # Validate MONITORING value if present
    if [[ -n "$MONITORING" ]]; then
        if [[ "$MONITORING" != "true" && "$MONITORING" != "false" ]]; then
            log "ERROR" "Invalid MONITORING value. Must be 'true' or 'false'"
            missing_vars+=("MONITORING")
        elif [[ "$MONITORING" == "true" ]]; then
            # Check monitoring-specific variables
            for var in "${!MONITORING_VARS[@]}"; do
                if [[ -z "${!var}" ]]; then
                    missing_vars+=("$var")
                    log "WARNING" "Missing monitoring variable: $var (${MONITORING_VARS[$var]})"
                fi
            done
        fi
    else
        missing_vars+=("MONITORING")
        log "WARNING" "Missing MONITORING configuration"
    fi

    # Validate OL_SCREEN_PORT if present
    if [[ -n "$OL_SCREEN_PORT" ]]; then
        if ! [[ "$OL_SCREEN_PORT" =~ ^[0-9]+$ ]] || \
           (( OL_SCREEN_PORT < 1 || OL_SCREEN_PORT > 65535 )); then
            log "ERROR" "Invalid OL_SCREEN_PORT value. Must be a number between 1 and 65535"
            missing_vars+=("OL_SCREEN_PORT")
        fi
    else
        missing_vars+=("OL_SCREEN_PORT")
        log "WARNING" "Missing OL_SCREEN_PORT configuration"
    fi

    # Additional validation for specific variables
    if [[ -n "$K8S_DISTRIBUTION" ]]; then
        if [[ "$K8S_DISTRIBUTION" != "k8s" && "$K8S_DISTRIBUTION" != "openshift" ]]; then
            log "ERROR" "Invalid K8S_DISTRIBUTION value. Must be 'k8s' or 'openshift'"
            missing_vars+=("K8S_DISTRIBUTION")
        fi
    fi

    # URL format validation
    if [[ -n "$OL_HUB_URL" ]]; then
        if [[ ! "$OL_HUB_URL" =~ ^https?:// ]]; then
            log "ERROR" "Invalid OL_HUB_URL format. Must start with http:// or https://"
            missing_vars+=("OL_HUB_URL")
        fi
    fi

    if [[ -n "$OL_KEYCLOAK_URL" ]]; then
        if [[ ! "$OL_KEYCLOAK_URL" =~ ^https?:// ]]; then
            log "ERROR" "Invalid OL_KEYCLOAK_URL format. Must start with http:// or https://"
            missing_vars+=("OL_KEYCLOAK_URL")
        fi
    fi

    # Check if any variables are missing
    if (( ${#missing_vars[@]} > 0 )); then
        log "WARNING" "Missing or invalid configuration values:"
        printf '%s\n' "${missing_vars[@]}" | sed 's/^/- /'
        return 1
    fi

    log "INFO" "Configuration validation successful"
    return 0
}

handle_missing_configuration() {
    local var="$1"
    local description="${REQUIRED_VARS[$var]:-${MONITORING_VARS[$var]}}"
    local default_value="${DEFAULTS[$var]:-}"
    local prompt="Enter $description"

    # Special handling for MONITORING
    if [[ "$var" == "MONITORING" ]]; then
        while true; do
            read -e -rp "Do you want to enable monitoring? (y/n): " yn
            case $yn in
                [Yy]* )
                    value="true"
                    break
                    ;;
                [Nn]* )
                    value="false"
                    break
                    ;;
                * )
                    echo "Please answer y or n."
                    ;;
            esac
        done
    # Special handling for OL_SCREEN_PORT
    elif [[ "$var" == "OL_SCREEN_PORT" ]]; then
        while true; do
            read -e -rp "Enter screen port (1-65535) [default: 1512]: " value
            value=${value:-1512}
            if [[ "$value" =~ ^[0-9]+$ ]] && \
               [[ "$value" -ge 1 ]] && \
               [[ "$value" -le 65535 ]]; then
                break
            else
                echo "Invalid port number. Please enter a number between 1 and 65535."
            fi
        done
    else
        if [[ -n "$default_value" ]]; then
            prompt+=" (default: $default_value)"
        fi
        prompt+=": "

        read -e -rp "$prompt" value
        value=${value:-$default_value}
    fi

    if [[ -z "$value" ]]; then
        err "Value for $var cannot be empty"
    fi

    # Export the variable
    export "$var=$value"

    # Add to config file
    echo "$var='$value'" >> "$CONFIG_FILE"

    # If monitoring is enabled, gather monitoring-specific variables
    if [[ "$var" == "MONITORING" ]] && [[ "$value" == "true" ]]; then
        for monitoring_var in "${!MONITORING_VARS[@]}"; do
            handle_missing_configuration "$monitoring_var"
        done
    fi
}

handle_existing_config() {

    check_export_vars
    handle_registry_credentials
    handle_k8s_distribution
    # handle_monitoring_config
    check_k8s_namespace
    prepare_keycloak_realm
}

########################################################################################
##################################### MAIN ############################################
########################################################################################
main() {
    # Display main banner with version and info
    display_banner "$version"

    # Verify prerequisites first
    display_section_banner "Checking Prerequisites"
    verify_prerequisites

    display_section_banner "Verifying Kubernetes Context"
    verify_context || return 1

    # Configuration handling
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        handle_existing_config
    else
        gather_new_configuration
    fi

   # Validate and handle missing configuration
    if ! validate_configuration; then
        echo "Configuration validation failed. Attempting to fix..."
        if ! handle_missing_configuration; then
            echo "Failed to gather all required configuration. Exiting."
            exit 1
        fi
    fi

    display_section_banner "Preparing Installation"
    prepare_installation
    generate_certificates
    generate_secrets
    prepare_keycloak_realm

    display_section_banner "Installing Hub Enterprise"
    install_hub_enterprise
}

# Start installation with error handling
if ! main "$@"; then
    log "ERROR" "Installation failed"
    exit 1
fi

exit 0
