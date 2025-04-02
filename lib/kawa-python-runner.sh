#/bin/bash
CONFIG_DIR=/etc/kawa
LOG_DIR=/var/log/kawa

. $CONFIG_DIR/kawa.env

export KAWA_AUTOMATION_SERVER_AES_KEY=$KAWA_GLOBAL_RUNNER_AES_KEY
export PATH=$(python3 -m site --user-base)/bin:$PATH

pipx install pex
pipx install kawapythonserver

kawapythonserver > $LOG_DIR/kawapythonserver.log 2>&1
