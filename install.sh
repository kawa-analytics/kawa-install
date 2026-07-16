#/bin/bash

# =====================================================================
# KAWA installer. Two installation modes are available:
#
#   sudo ./install.sh --mode=native   Runs directly on the machine (systemd)
#   sudo ./install.sh --mode=docker   Runs with docker compose
#
# And one maintenance command:
#
#   sudo ./install.sh --mode=configure
#       Re-applies the application configuration after a change
#       to the kawa.config file (features, SMTP, OIDC, ...)
#
# Both modes share the same configuration pieces:
#   - configuration/kawa-registry.credentials  (registry access)
#   - configuration/kawa.config                (the KAWA configuration)
#   - configuration/kawa.secrets               (ALL the secrets)
#   - the kywy-based configuration step (lib/kawa-configure.sh)
#
# Without --mode, the installer runs interactively.
# Automation: --mode=<m> --interactive=false [--version=<v>]
# Any other flag is passed through to the mode-specific installer.
# =====================================================================

cd "$(dirname "$0")"

CONFIG_DIR=configuration
CREDENTIALS_FILE=$CONFIG_DIR/kawa-registry.credentials

# ---------------------------------------------------------------------
# Cosmetics
# ---------------------------------------------------------------------
if [ -t 1 ]; then
    BOLD=$(tput bold); CYAN=$(tput setaf 6); GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3); RESET=$(tput sgr0)
else
    BOLD=""; CYAN=""; GREEN=""; YELLOW=""; RESET=""
fi

step() {
    echo ""
    echo "${BOLD}${CYAN}==> $1${RESET}"
}

ask() { # ask "question" "default" -> $REPLY
    read -r -p "    $1 [$2]: " REPLY
    REPLY=${REPLY:-$2}
}

set_config() { # set_config KEY value - persists a value into kawa.config
    sed -i "s|^$1=.*|$1=\"$2\"|" $CONFIG_DIR/kawa.config
}

# ---------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------
MODE=""
interactive="true"
ARGS=()
for arg in "$@"; do
    case $arg in
        --mode=*) MODE="${arg#*=}" ;;
        --interactive=*) interactive="${arg#*=}"; ARGS+=("$arg") ;;
        *) ARGS+=("$arg") ;;
    esac
done
[ -t 0 ] || interactive="false"

# ---------------------------------------------------------------------
# Maintenance command: re-apply the application configuration
# ---------------------------------------------------------------------
if [ "$MODE" == "configure" ]; then
    bash lib/kawa-configure.sh
    echo ""
    echo "Restart the KAWA server to take the new configuration into account:"
    if [ -f /etc/kawa/kawa.config ]; then
        echo "  sudo systemctl restart kawa"
    else
        echo "  (cd docker && docker compose restart kawa-server)"
    fi
    exit 0
fi

echo "${CYAN}${BOLD}"
echo "  =============================================="
echo "        K A W A   -   I N S T A L L E R"
echo "  =============================================="
echo "${RESET}"

# ---------------------------------------------------------------------
# 1. Installation mode
# ---------------------------------------------------------------------
if [ -z "$MODE" ]; then
    if [ "$interactive" != "true" ]; then
        echo "Please specify a mode: --mode=native or --mode=docker"
        exit 1
    fi
    step "Installation mode"
    echo "    1) native - directly on this machine, as systemd services"
    echo "    2) docker - as docker compose services (recommended)"
    read -r -p "    Please choose [1/2]: " choice
    case $choice in
        1) MODE=native ;;
        2) MODE=docker ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi

if [ "$MODE" != "native" ] && [ "$MODE" != "docker" ]; then
    echo "Unknown mode: $MODE (expected native, docker or configure)"
    exit 1
fi
echo "    Mode: ${GREEN}$MODE${RESET}"

# ---------------------------------------------------------------------
# 2. Registry access (GitLab deploy token)
# ---------------------------------------------------------------------
step "Registry access"
CURRENT_TOKEN_NAME=$(head -1 "$CREDENTIALS_FILE" 2>/dev/null)
if [ -z "$CURRENT_TOKEN_NAME" ] || [ "$CURRENT_TOKEN_NAME" == "token-name" ]; then
    if [ "$interactive" != "true" ]; then
        echo "Please input your registry credentials in $CREDENTIALS_FILE"
        echo "(first line: token name, second line: token value)"
        exit 1
    fi
    echo "    Your GitLab registry credentials were provided by the KAWA support team."
    read -r -p "    Token name: " TOKEN_NAME
    read -r -s -p "    Token value (gldt-...): " TOKEN_VALUE
    echo ""
    printf '%s\n%s\n' "$TOKEN_NAME" "$TOKEN_VALUE" > "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
    echo "    Credentials saved in $CREDENTIALS_FILE"
else
    echo "    Using the existing credentials '$CURRENT_TOKEN_NAME' (from $CREDENTIALS_FILE)"
fi

# ---------------------------------------------------------------------
# 3. Version
# ---------------------------------------------------------------------
. $CONFIG_DIR/kawa.config
if [ "$interactive" == "true" ]; then
    step "Version"
    if [ "$MODE" == "native" ]; then
        ask "KAWA version - exact JAR version (eg. 1.35.1)" "$KAWA_JAR_VERSION"
        set_config KAWA_JAR_VERSION "$REPLY"
    else
        ask "KAWA version - docker image tag (eg. 1.35.x)" "$KAWA_DOCKER_VERSION"
        set_config KAWA_DOCKER_VERSION "$REPLY"
    fi
    echo "    Version: ${GREEN}$REPLY${RESET}"
fi

# ---------------------------------------------------------------------
# 4. Admin account
# ---------------------------------------------------------------------
if [ ! -f $CONFIG_DIR/admin.pwd ] && [ ! -f /etc/kawa/admin.pwd ] && [ "$interactive" == "true" ]; then
    step "Admin account (setup-admin@kawa.io)"
    while true; do
        read -r -s -p "    Choose the admin password: " ADMIN_PASSWORD_1
        echo ""
        read -r -s -p "    Confirm the admin password: " ADMIN_PASSWORD_2
        echo ""
        if [ -z "$ADMIN_PASSWORD_1" ]; then
            echo "    ${YELLOW}The password cannot be empty.${RESET}"
        elif [ "$ADMIN_PASSWORD_1" != "$ADMIN_PASSWORD_2" ]; then
            echo "    ${YELLOW}The passwords do not match, please try again.${RESET}"
        else
            break
        fi
    done
    printf '%s' "$ADMIN_PASSWORD_1" > $CONFIG_DIR/admin.pwd
    chmod 600 $CONFIG_DIR/admin.pwd
fi

# ---------------------------------------------------------------------
# 5. Hand over to the mode-specific installer
# ---------------------------------------------------------------------
step "Installing KAWA ($MODE mode)"
case $MODE in
    native)
        bash native/install-native.sh "${ARGS[@]}"
        ;;
    docker)
        bash docker/install-docker.sh "${ARGS[@]}"
        ;;
esac
