#/bin/bash

CONFIG_DIR=/etc/kawa
LOG_DIR=/var/log/kawa
TOKEN_FILE=$CONFIG_DIR/deploy.token
TOKEN=`cat $TOKEN_FILE`
PACKAGE_URL="https://__token__:$TOKEN@gitlab.com/api/v4/projects/56094807/packages/pypi/simple"

. $CONFIG_DIR/kawa.env

export KAWA_AUTOMATION_SERVER_AES_KEY=$KAWA_GLOBAL_RUNNER_AES_KEY
export PATH=$(python3 -m site --user-base)/bin:$PATH

pipx install pex
pipx install kawapythonserver --index-url $PACKAGE_URL

kawapythonserver > $LOG_DIR/kawapythonserver.log 2>&1