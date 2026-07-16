#!/bin/bash

CONFIG_DIR=/etc/kawa
LOG_DIR=/var/log/kawa
TOKEN_FILE=$CONFIG_DIR/deploy.token
TOKEN=`cat $TOKEN_FILE`
REGISTRY_URL=https://gitlab.com/api/v4/projects/26911065/packages/generic/kawa
PATH_TO_JAR=/var/lib/kawa/workflow.jar

. $CONFIG_DIR/kawa.config
. $CONFIG_DIR/workflow.env

# Exact JAR version (eg. 1.35.1), from kawa.config
VERSION=${KAWA_JAR_VERSION:-"1.35.1"}


if [[ ! -f "$PATH_TO_JAR" || $(stat -c%s "$PATH_TO_JAR") -lt 1048576 ]]; then
   JAR_URL=$REGISTRY_URL/$VERSION/kawa-workflow-$VERSION.jar
   echo "Downloading JAR: $JAR_URL"
   curl --header DEPLOY-TOKEN:$TOKEN  $JAR_URL --output $PATH_TO_JAR
fi

chmod 600 $PATH_TO_JAR

# The KAWA server authenticates to the engine with the private key
# (KAWA_PRIVATE_KEY_PATH in kawa.env). The engine verifies with the public key.
export APP_AUTH_CLIENTS_KAWA=$(sed -e '/-----BEGIN PUBLIC KEY-----/d' -e '/-----END PUBLIC KEY-----/d' $CONFIG_DIR/workflow-public-key.pem | tr -d '\n')
export TZ=UTC

java --add-opens=java.base/java.nio=ALL-UNNAMED \
  -Xmx4g \
  -XX:-OmitStackTraceInFastThrow \
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:+UseZGC \
  -jar $PATH_TO_JAR > $LOG_DIR/kawa-workflow.log 2>&1
