#!/bin/bash

CONFIG_DIR=/etc/kawa
LOG_DIR=/var/log/kawa

. $CONFIG_DIR/kawa.env

export KAWA_AUTOMATION_SERVER_AES_KEY=$KAWA_GLOBAL_RUNNER_AES_KEY
export PATH=$(python3 -m site --user-base)/bin:$PATH

# The URL this runner uses to reach the KAWA server
SCHEME=http
if [ "$USE_HTTPS" = "true" ]; then
    SCHEME=https
fi
export KAWA_URL=${KAWA_URL:-$SCHEME://localhost:$LISTEN_PORT}

# Custom python package registry (optional, from kawa.config/kawa.secrets).
# KW_PEX_USE_PIP_CONFIG makes pex honor the pip configuration when
# packaging the dependencies of user scripts. It must be left UNSET to
# disable (any value, even "false", enables it).
if [ "$USE_CUSTOM_PYPI" = "true" ]; then
    export KW_PEX_USE_PIP_CONFIG=true
    export PIP_INDEX_URL
fi

# The runner and pex MUST use python 3.12: user scripts pin package
# versions that only ship prebuilt wheels up to 3.12. The interpreter
# comes from the distribution, or from uv (installed by install.sh).
RUNNER_PYTHON=$(command -v python3.12 || uv python find 3.12 2>/dev/null || command -v python3)
echo "Using python interpreter: $RUNNER_PYTHON"

# Both packages are on the public PyPI (or your custom registry):
# https://pypi.org/project/kawapythonserver/
pipx install --python "$RUNNER_PYTHON" pex
pipx install --python "$RUNNER_PYTHON" kawapythonserver

kawapythonserver > $LOG_DIR/kawapythonserver.log 2>&1