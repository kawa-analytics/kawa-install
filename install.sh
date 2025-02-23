#/bin/bash

KAWA_USER=kawa-system
CONFIG_DIR=/etc/kawa
LOG_DIR=/var/log/kawa
VAR_DIR=/var/lib/kawa
BIN_DIR=/usr/local/bin

if [ "$USER" != "root" ]; then
    echo "Please run as root"
    exit
fi

# Create the kawa-system user and group
id -u $KAWA_USER >/dev/null 2>&1 || adduser --disabled-password --gecos "" $KAWA_USER

# Create kawa directories
mkdir -p --mode 700 $CONFIG_DIR $LOG_DIR $VAR_DIR/files $VAR_DIR/drivers
chown -R $KAWA_USER $CONFIG_DIR $LOG_DIR $VAR_DIR
chgrp -R $KAWA_USER $CONFIG_DIR $LOG_DIR $VAR_DIR

# Copy the files: Binary
cp lib/kawa.sh $BIN_DIR
cp lib/kawa-python-runner.sh $BIN_DIR

chown $KAWA_USER $BIN_DIR/kawa.sh $BIN_DIR/kawa-python-runner.sh
chgrp $KAWA_USER $BIN_DIR/kawa.sh $BIN_DIR/kawa-python-runner.sh
chmod 700 $BIN_DIR/kawa.sh $BIN_DIR/kawa-python-runner.sh


# Copy the files: Configuration
cp configuration/*.* $CONFIG_DIR
if [ ! -f $CONFIG_DIR/kawa.pwd ]; then
    sudo sh -c 'tr -dc A-Za-z0-9 </dev/urandom | head -c 20  > /etc/kawa/kawa.pwd'
fi
chown $KAWA_USER $CONFIG_DIR/*.*
chgrp $KAWA_USER $CONFIG_DIR/*.*
chmod 600 $CONFIG_DIR/*.*
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

# Configure Postgres: Add the kawa user and grant them the rquired permissions
echo "Creating KAWA user in Postgres"
sudo -u postgres createuser kawa
sudo -u postgres createdb kawa
sudo -u postgres psql  -c "ALTER USER kawa WITH ENCRYPTED PASSWORD '$(cat $CONFIG_DIR/kawa.pwd)'"
sudo -u postgres psql  -c "GRANT ALL PRIVILEGES ON DATABASE kawa TO kawa"

# Configure Clickhouse
echo "Creating KAWA user in Clickhouse"
sudo service clickhouse-server start
sudo sed -i '/access_management/ s/<!--//' /etc/clickhouse-server/users.xml
sudo sed -i '/access_management/ s/-->//' /etc/clickhouse-server/users.xml
clickhouse-client --password --multiquery -q "CREATE USER kawa IDENTIFIED WITH sha256_password BY '$(cat $CONFIG_DIR/kawa.pwd)'; CREATE DATABASE kawa; GRANT ALL ON kawa TO kawa; GRANT ALL ON kawa.* TO kawa;"

# Create the linux services
# The KAWA server
cp lib/kawa.service /etc/systemd/system
systemctl start kawa
systemctl enable kawa

# The script runner
cp lib/kawa-python-runner.service /etc/systemd/system
systemctl start kawa-python-runner
systemctl enable kawa-python-runner


