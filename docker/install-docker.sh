#/bin/bash
set -e

# =====================================================================
# KAWA installation - DOCKER COMPOSE mode.
# Invoked by ../install.sh (or directly). Reads the shared
# configuration from ../configuration/kawa.config.
# =====================================================================

cd "$(dirname "$0")"
PACKAGE_DIR=$(cd .. && pwd)
CONFIG_DIR=$PACKAGE_DIR/configuration
VENV_DIR=$PACKAGE_DIR/kywy-venv
CREDENTIALS_FILE=$CONFIG_DIR/kawa-registry.credentials

interactive="true"
KAWA_BRANCH_NAME=""
SKIP_DOCKER_LOGIN="false"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --interactive=*) interactive="${1#*=}" ;;
        --version=*) KAWA_BRANCH_NAME="${1#*=}" ;;
        --skip-docker-login=*) SKIP_DOCKER_LOGIN="${1#*=}" ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# The generated .env contains this installation's secrets: never
# silently regenerate it, this would disconnect the databases.
if [ -f .env ]; then
    echo "A .env file already exists: this docker installation is already configured."
    echo "  - To change environment values (SMTP credentials, OIDC secret, HTTPS...): edit docker/.env then run: docker compose up -d"
    echo "  - To change the application configuration (features, SMTP server, OIDC...): edit configuration/kawa.config then run: sudo ./install.sh --mode=configure"
    exit 1
fi

# The shared configuration and secrets
. $CONFIG_DIR/kawa.config
. $CONFIG_DIR/kawa.secrets

# Docker image tag: --version flag, or KAWA_DOCKER_VERSION from kawa.config
if [[ -z "$KAWA_BRANCH_NAME" ]]; then
    KAWA_BRANCH_NAME=${KAWA_DOCKER_VERSION:-"1.35.x"}
fi

echo "Installing KAWA $KAWA_BRANCH_NAME (docker compose mode)"

if [[ "$SKIP_DOCKER_LOGIN" != "true" ]]; then
    DOCKER_TOKEN_USERNAME=$(head -1 "$CREDENTIALS_FILE")
    DOCKER_TOKEN_PASSWORD=$(tail -n -1 "$CREDENTIALS_FILE")
    echo "$DOCKER_TOKEN_PASSWORD" | docker login registry.gitlab.com -u "$DOCKER_TOKEN_USERNAME" --password-stdin
else
    echo "Skipping Docker login as --skip-docker-login=true is set."
fi

kawa_user=5000:5000

# This simple standalone install always uses the bundled
# clickhouse + postgres.
KAWA_WAREHOUSE_TYPE='CLICKHOUSE'

# SMTP credentials and OIDC secret come from the shared kawa.secrets
# (optional - only used with COMMUNICATION_PROVIDER_TYPE=SMTP / USE_OIDC=true)
KAWA_SMTP_USERNAME=${SMTP_USERNAME:-NA}
KAWA_SMTP_PASSWORD=${SMTP_PASSWORD:-NA}
KAWA_OAUTH2_CLIENT_SECRET=${OIDC_CLIENT_SECRET:-NA}

# Custom python package registry (optional). KW_PEX_USE_PIP_CONFIG must
# stay EMPTY to disable (any value, even "false", enables it).
# PIP_INDEX_URL comes from kawa.secrets.
KW_PEX_USE_PIP_CONFIG=""
if [ "$USE_CUSTOM_PYPI" == "true" ]; then
    KW_PEX_USE_PIP_CONFIG="true"
fi

KAWA_SERVICE_NAME="kawa-server"
KAWA_SERVER_HTTPS=false
KAWA_SERVER_URL=http://${KAWA_SERVICE_NAME}

# Generate key pair for workflow engine
WORKFLOW_PRIVATE_KEY=workflow-private-key.pem
WORKFLOW_PUBLIC_KEY=workflow-public-key.pem
if [ ! -f $WORKFLOW_PRIVATE_KEY ]; then
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out $WORKFLOW_PRIVATE_KEY
    openssl ec -in $WORKFLOW_PRIVATE_KEY -pubout -out $WORKFLOW_PUBLIC_KEY
fi
chown $kawa_user ./$WORKFLOW_PRIVATE_KEY
chmod 600 ./$WORKFLOW_PRIVATE_KEY

# HTTPS: TLS termination on the KAWA server, from the shared kawa.config
if [ "$USE_HTTPS" == "true" ]; then
    cp "$PATH_TO_SERVER_CERTIFICATE" ./server.crt
    cp "$PATH_TO_SERVER_PRIVATE_KEY" ./server.key
    chown $kawa_user ./server.crt ./server.key
    chmod 600 ./server.crt ./server.key
    KAWA_SERVER_HTTPS=true
    KAWA_SERVER_URL=https://${KAWA_SERVICE_NAME}
else
    touch ./server.crt ./server.key
fi

KAWA_SERVER_EXTERNAL_URL=$KAWA_EXTERNAL_URL
KAWA_SERVER_EXTERNAL_PORT=$LISTEN_PORT

# Update the clickhouse user override file, it accepts the sha256 of the password
KAWA_DB_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
kawa_hashed_db_password=$(echo -n "$KAWA_DB_PASSWORD" | sha256sum | cut -d ' ' -f 1)
sed -i "s/.*password_sha256.*/<password_sha256_hex>$kawa_hashed_db_password<\/password_sha256_hex>/g" ./assets/users.d/kawa.xml

master_key=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
kawa_clickhouse_db_name="default"

KAWA_DB_USER="kawa"
KAWA_SERVER_DB_NAME=kawa
KAWA_SERVER_SCHEMA_NAME=kawa
KAWA_WORKFLOW_DB_NAME=workflow
KAWA_WORKFLOW_SCHEMA_NAME=workflow
KAWA_RUNNER_AES_KEY=$(head /dev/urandom | sha256sum | cut -d ' ' -f 1)
KAWA_ENCRYPTION_KEY=$(echo -n "${master_key}-key" | sha256sum | awk '{print substr($1, 1, 24)}')
KAWA_ENCRYPTION_IV=$(echo -n "${master_key}-iv" | sha256sum | awk '{print substr($1, 1, 16)}')
KAWA_ACCESS_TOKEN_SECRET=$(head -c 64 /dev/urandom | xxd -p | tr -d '\n')
KAWA_REFRESH_TOKEN_SECRET=$(head -c 64 /dev/urandom | xxd -p | tr -d '\n')
KAWA_POSTGRES_JDBC_URL="jdbc:postgresql://postgres:5432/${KAWA_SERVER_DB_NAME}?currentSchema=${KAWA_SERVER_SCHEMA_NAME}&user=${KAWA_DB_USER}&password=${KAWA_DB_PASSWORD}"
KAWA_WORKFLOW_JDBC_URL="jdbc:postgresql://postgres:5432/${KAWA_WORKFLOW_DB_NAME}?currentSchema=${KAWA_WORKFLOW_SCHEMA_NAME}&user=${KAWA_DB_USER}&password=${KAWA_DB_PASSWORD}"
KAWA_WORKFLOW_KAWA_PUBLIC_KEY=$(sed -e '/-----BEGIN PUBLIC KEY-----/d' -e '/-----END PUBLIC KEY-----/d' $WORKFLOW_PUBLIC_KEY  | tr -d '\n')
KAWA_CLICKHOUSE_JDBC_URL="jdbc:clickhouse://clickhouse:8123/${kawa_clickhouse_db_name}?user=${KAWA_DB_USER}&password=${KAWA_DB_PASSWORD}"
KAWA_CLICKHOUSE_INTERNAL_DATABASE=$kawa_clickhouse_db_name
KAWA_DOCKER_COMPOSE_NETWORK_NAME=kawa-network-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)

# Configure the data directory, that will serve as mount point for all
# the docker compose volumes
MOUNT_DIRECTORY="./data"
if [ "$interactive" == "true" ]; then
  read -r -p "Please specify the directory where you want to persist your data (will be created if it does not exist): " MOUNT_DIRECTORY
fi
mkdir -p "$MOUNT_DIRECTORY/pgdata" "$MOUNT_DIRECTORY/clickhousedata" "$MOUNT_DIRECTORY/kawadata"

# If the environment variable is set, use it; otherwise, use the default from .env.defaults
> .env
while IFS='=' read -r var_name default_value || [[ -n "$var_name" ]]; do
  var_name="$(echo "$var_name" | xargs)"
  if [[ "$var_name" =~ ^#.*$ || -z "$var_name" ]]; then
    continue
  fi
  value="${!var_name:-$default_value}"
  echo "$var_name=$value" >> .env
done < .env.defaults

# =====================================================================
# STEP 2: Start all the services
# =====================================================================

docker compose --profile clickhouse up -d

# =====================================================================
# STEP 3: Install kywy and apply the KAWA configuration
# =====================================================================

# Choose the admin password
if [ ! -f $CONFIG_DIR/admin.pwd ]; then
    read -r -s -p "Choose the password for the KAWA admin account (setup-admin@kawa.io): " ADMIN_PASSWORD
    echo
    printf '%s' "$ADMIN_PASSWORD" > $CONFIG_DIR/admin.pwd
    chmod 600 $CONFIG_DIR/admin.pwd
fi

echo "Installing the kywy python client"
PYTHON=$(command -v python3.12 || command -v python3)
$PYTHON -m venv $VENV_DIR
$VENV_DIR/bin/pip install --quiet --upgrade pip kywy

# In docker mode: the config stays in the package directory, the server
# reaches the workflow engine through the compose network, and the
# server always listens on 8080 INSIDE its container.
KAWA_CONFIG_DIR=$CONFIG_DIR \
KAWA_VENV_DIR=$VENV_DIR \
WORKFLOW_URL=http://kawa-workflow:8088 \
SERVER_INTERNAL_PORT=8080 \
bash $PACKAGE_DIR/lib/kawa-configure.sh

# =====================================================================
# STEP 4: Restart the server to take the configuration into account
# =====================================================================

docker compose restart kawa-server

echo ""
echo "Installation complete."
echo "Login with setup-admin@kawa.io and the password you chose (port $LISTEN_PORT)."
echo "To change the application configuration later: edit configuration/kawa.config then run:"
echo "  sudo ./install.sh --mode=configure"
