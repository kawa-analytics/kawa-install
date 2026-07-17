#!/bin/bash

CONFIG_DIR=/etc/kawa
TOKEN_FILE=$CONFIG_DIR/deploy.token
TOKEN=`cat $TOKEN_FILE`
REGISTRY_URL=https://gitlab.com/api/v4/projects/26911065/packages/generic/kawa
PATH_TO_JAR=/var/lib/kawa/kawa.jar

. $CONFIG_DIR/kawa.env

# Exact JAR version (eg. 1.35.1), from kawa.config
VERSION=${KAWA_JAR_VERSION:-"1.35.1"}


if [[ ! -f "$PATH_TO_JAR" || $(stat -c%s "$PATH_TO_JAR") -lt 1048576 ]]; then
   JAR_URL=$REGISTRY_URL/$VERSION/kawa-server-$VERSION.jar
   echo "Downloading JAR: $JAR_URL"
   curl --header DEPLOY-TOKEN:$TOKEN  $JAR_URL --output $PATH_TO_JAR
fi

chmod 600 $PATH_TO_JAR

java --add-opens=java.base/java.nio=ALL-UNNAMED \
  -Xmx8g \
  -XX:-OmitStackTraceInFastThrow \
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:+UseZGC \
  -Dlog4j2.configurationFile="file://${CONFIG_DIR}/log4j2.xml" -jar $PATH_TO_JAR