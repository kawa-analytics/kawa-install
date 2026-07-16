#/bin/bash
#
# Applies the KAWA application configuration (features, SMTP, OIDC,
# workflow engine, admin password) from kawa.config, using the kywy
# python client. Shared by both installation modes:
#
#   - native: configuration in /etc/kawa, venv in /var/lib/kawa/kywy-venv
#   - docker: configuration in <package>/configuration, venv in <package>/kywy-venv
#
# Re-run it after any change to kawa.config (or use: sudo ./install.sh
# --mode=configure), then restart the KAWA server:
#   native: sudo systemctl restart kawa
#   docker: (cd docker && docker compose restart kawa-server)
#
# The autodetection can be overridden with the KAWA_CONFIG_DIR and
# KAWA_VENV_DIR environment variables.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PACKAGE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

# Detect the installation mode
if [ -z "$KAWA_CONFIG_DIR" ]; then
    if [ -f /etc/kawa/kawa.config ]; then
        # native mode
        KAWA_CONFIG_DIR=/etc/kawa
        KAWA_VENV_DIR=${KAWA_VENV_DIR:-/var/lib/kawa/kywy-venv}
    else
        # docker mode: the server reaches the workflow engine through the
        # compose network, and always listens on 8080 inside its container
        KAWA_CONFIG_DIR=$PACKAGE_DIR/configuration
        KAWA_VENV_DIR=${KAWA_VENV_DIR:-$PACKAGE_DIR/kywy-venv}
        export WORKFLOW_URL=${WORKFLOW_URL:-http://kawa-workflow:8088}
        export SERVER_INTERNAL_PORT=${SERVER_INTERNAL_PORT:-8080}
    fi
fi
KAWA_VENV_DIR=${KAWA_VENV_DIR:-/var/lib/kawa/kywy-venv}

set -a
. $KAWA_CONFIG_DIR/kawa.config
set +a
export ADMIN_PASSWORD_FILE=$KAWA_CONFIG_DIR/admin.pwd

SCHEME=http
if [ "$USE_HTTPS" = "true" ]; then
    SCHEME=https
fi

# Wait for the KAWA server to accept connections: the first start
# downloads the binaries and runs the database migrations.
echo "Waiting for the KAWA server on port $LISTEN_PORT (first start can take a few minutes)..."
for i in $(seq 1 120); do
    if curl -sk -o /dev/null $SCHEME://localhost:$LISTEN_PORT; then
        break
    fi
    sleep 5
done

$KAWA_VENV_DIR/bin/python $SCRIPT_DIR/configure_kawa.py
