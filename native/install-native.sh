#/bin/bash

# =====================================================================
# KAWA installation - NATIVE mode (systemd services, no docker).
# Invoked by ../install.sh (or directly). Reads the shared
# configuration from ../configuration/kawa.config.
# =====================================================================

cd "$(dirname "$0")/.."

KAWA_USER=kawa-system
CONFIG_DIR=/etc/kawa
LOG_DIR=/var/log/kawa
VAR_DIR=/var/lib/kawa
BIN_DIR=/usr/local/bin
VENV_DIR=$VAR_DIR/kywy-venv

if [ "$USER" != "root" ]; then
    echo "Please run as root"
    exit
fi

# =====================================================================
# STEP 1: Download the binaries and configure the environment
# =====================================================================

# Create the kawa-system user and group
id -u $KAWA_USER >/dev/null 2>&1 || adduser --disabled-password --gecos "" $KAWA_USER

# Create kawa directories
mkdir -p --mode 700 $CONFIG_DIR $LOG_DIR $VAR_DIR/files $VAR_DIR/drivers
chown -R $KAWA_USER $CONFIG_DIR $LOG_DIR $VAR_DIR
chgrp -R $KAWA_USER $CONFIG_DIR $LOG_DIR $VAR_DIR

# Copy the files: Binaries
for f in kawa.sh kawa-python-runner.sh kawa-workflow.sh kawa-configure.sh configure_kawa.py; do
    cp lib/$f $BIN_DIR
    chown $KAWA_USER $BIN_DIR/$f
    chgrp $KAWA_USER $BIN_DIR/$f
    chmod 700 $BIN_DIR/$f
done

# Copy the files: Configuration
# (never overwrite an existing secrets file: it holds this
# installation's keys and connection strings)
for f in configuration/*.*; do
    if [ "$(basename $f)" = "kawa.secrets" ] && [ -f $CONFIG_DIR/kawa.secrets ]; then
        continue
    fi
    cp $f $CONFIG_DIR
done
if [ ! -f $CONFIG_DIR/kawa.pwd ]; then
    sudo sh -c 'tr -dc A-Za-z0-9 </dev/urandom | head -c 20  > /etc/kawa/kawa.pwd'
fi

# The launcher scripts download the JARs with the registry token
# (second line of the credentials file)
tail -n -1 configuration/kawa-registry.credentials > $CONFIG_DIR/deploy.token

# Generate the key pair used by KAWA to authenticate to the workflow engine
if [ ! -f $CONFIG_DIR/workflow-private-key.pem ]; then
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out $CONFIG_DIR/workflow-private-key.pem
    openssl ec -in $CONFIG_DIR/workflow-private-key.pem -pubout -out $CONFIG_DIR/workflow-public-key.pem
fi

# Append the generated secrets to the secrets file: database password
# based JDBC urls, token signing and encryption keys, runner AES key.
if ! grep -q KAWA_POSTGRES_JDBC_URL $CONFIG_DIR/kawa.secrets; then
    KAWA_DB_PASSWORD=$(cat $CONFIG_DIR/kawa.pwd)
    RUNNER_AES_KEY=$(head -c 32 /dev/urandom | xxd -p | tr -d '\n')
    cat >> $CONFIG_DIR/kawa.secrets <<EOF

# ---- Generated at installation time (do not edit) ----
KAWA_POSTGRES_JDBC_URL="jdbc:postgresql://localhost:5432/kawa?user=kawa&password=$KAWA_DB_PASSWORD&currentSchema=kawa"
KAWA_CLICKHOUSE_JDBC_URL="jdbc:clickhouse://localhost:8123/kawa?user=kawa&password=$KAWA_DB_PASSWORD"
KAWA_WORKFLOW_JDBC_URL="jdbc:postgresql://localhost:5432/workflow?currentSchema=workflow&user=kawa&password=$KAWA_DB_PASSWORD"
KAWA_ACCESS_TOKEN_SECRET=$(head -c 64 /dev/urandom | xxd -p | tr -d '\n')
KAWA_REFRESH_TOKEN_SECRET=$(head -c 64 /dev/urandom | xxd -p | tr -d '\n')
KAWA_ENCRYPTION_KEY=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)
KAWA_ENCRYPTION_IV=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
KAWA_GLOBAL_RUNNER_AES_KEY=$RUNNER_AES_KEY
KAWA_DEFAULT_RUNNER_AES_KEY=$RUNNER_AES_KEY
EOF
fi

# Choose the admin password. It is applied on the server in step 3.
if [ ! -f $CONFIG_DIR/admin.pwd ]; then
    read -r -s -p "Choose the password for the KAWA admin account (setup-admin@kawa.io): " ADMIN_PASSWORD
    echo
    printf '%s' "$ADMIN_PASSWORD" > $CONFIG_DIR/admin.pwd
fi

chown $KAWA_USER $CONFIG_DIR/*.*
chgrp $KAWA_USER $CONFIG_DIR/*.*
chmod 600 $CONFIG_DIR/*.*

# Install dependencies
sudo apt-get install -y apt-transport-https ca-certificates dirmngr
curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | sudo gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg

ARCH=$(dpkg --print-architecture)
echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg arch=${ARCH}] https://packages.clickhouse.com/deb stable main" | sudo tee /etc/apt/sources.list.d/clickhouse.list
sudo apt-get update
sudo apt-get install -yqq \
    postgresql-16 \
    clickhouse-server \
    clickhouse-client \
    openjdk-21-jre-headless \
    python3.12 \
    python3-pip \
    python3.12-venv \
    pipx

# Configure Postgres: Add the kawa user and grant them the required permissions
echo "Creating KAWA user in Postgres"
sudo -u postgres createuser kawa
sudo -u postgres createdb kawa
sudo -u postgres psql  -c "ALTER USER kawa WITH ENCRYPTED PASSWORD '$(cat $CONFIG_DIR/kawa.pwd)'"
sudo -u postgres psql  -c "GRANT ALL PRIVILEGES ON DATABASE kawa TO kawa"

# Configure Postgres: the database used by the workflow engine
echo "Creating workflow engine database in Postgres"
sudo -u postgres createdb workflow
sudo -u postgres psql  -c "GRANT ALL PRIVILEGES ON DATABASE workflow TO kawa"
sudo -u postgres psql  -d workflow -c "CREATE SCHEMA IF NOT EXISTS workflow AUTHORIZATION kawa"

# Configure Clickhouse
echo "Creating KAWA user in Clickhouse"
sudo service clickhouse-server start
sudo sed -i '/access_management/ s/<!--//' /etc/clickhouse-server/users.xml
sudo sed -i '/access_management/ s/-->//' /etc/clickhouse-server/users.xml
clickhouse-client --password --multiquery -q "CREATE USER kawa IDENTIFIED WITH sha256_password BY '$(cat $CONFIG_DIR/kawa.pwd)'; CREATE DATABASE kawa; GRANT ALL ON kawa TO kawa; GRANT ALL ON kawa.* TO kawa;"

# =====================================================================
# STEP 2: Start all the services
# =====================================================================

# The KAWA server
cp lib/kawa.service /etc/systemd/system
systemctl start kawa
systemctl enable kawa

# The script runner
cp lib/kawa-python-runner.service /etc/systemd/system
systemctl start kawa-python-runner
systemctl enable kawa-python-runner

# The workflow engine
cp lib/kawa-workflow.service /etc/systemd/system
systemctl start kawa-workflow
systemctl enable kawa-workflow

# =====================================================================
# STEP 3: Install kywy and apply the KAWA configuration
# =====================================================================

echo "Installing the kywy python client"
PYTHON=$(command -v python3.12 || command -v python3)
$PYTHON -m venv $VENV_DIR
$VENV_DIR/bin/pip install --quiet --upgrade pip kywy

bash $BIN_DIR/kawa-configure.sh

# =====================================================================
# STEP 4: Restart the server to take the configuration into account
# =====================================================================

systemctl restart kawa

echo ""
echo "Installation complete."
echo "Login with setup-admin@kawa.io and the password you chose (port 8080 by default)."
echo "To change the configuration later: edit /etc/kawa/kawa.config then run:"
echo "  sudo kawa-configure.sh && sudo systemctl restart kawa"
