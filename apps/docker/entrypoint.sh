#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="${CONF_DIR:-/azerothcore/env/dist/etc}"
LOGS_DIR="${LOGS_DIR:-/azerothcore/env/dist/logs}"

if ! touch "$CONF_DIR/.write-test" || ! touch "$LOGS_DIR/.write-test"; then
    cat <<EOF
===== WARNING =====
The current user doesn't have write permissions for
the configuration dir ($CONF_DIR) or logs dir ($LOGS_DIR).
It's likely that services will fail due to this.

This is usually caused by cloning the repository as root,
so the files are owned by root (uid 0).

To resolve this, you can set the ownership of the
configuration directory with the command on the host machine.
Note that if the files are owned as root, the ownership must
be changed as root (hence sudo).

$ sudo chown -R $(id -u):$(id -g) /path/to$CONF_DIR /path/to$LOGS_DIR

Alternatively, you can set the DOCKER_USER environment
variable (on the host machine) to "root", though this
isn't recommended.

$ DOCKER_USER=root docker-compose up -d
====================
EOF
fi

[[ -f "$CONF_DIR/.write-test" ]] && rm -f "$CONF_DIR/.write-test"
[[ -f "$LOGS_DIR/.write-test" ]] && rm -f "$LOGS_DIR/.write-test"

# Copy all default config files to env/dist/etc if they don't already exist
# -r == recursive
# -n == no clobber (don't overwrite)
# -v == be verbose
cp -rnv /azerothcore/env/ref/etc/* "$CONF_DIR"

CONF="$CONF_DIR/$ACORE_COMPONENT.conf"
CONF_DIST="$CONF_DIR/$ACORE_COMPONENT.conf.dist"

# Copy the "dist" file to the "conf" if the conf doesn't already exist
if [[ -f "$CONF_DIST" ]]; then
    cp -vn "$CONF_DIST" "$CONF"
else
    touch "$CONF"
fi

# Module configs are only read from "<name>.conf", never from "<name>.conf.dist",
# so every shipped module config gets materialized the same way as the component
# config above. Without this, playerbots.conf would never exist and every
# AiPlayerbot.* setting would silently fall back to its compiled-in default.
if [[ -d "$CONF_DIR/modules" ]]; then
    shopt -s nullglob
    for module_conf_dist in "$CONF_DIR"/modules/*.conf.dist; do
        cp -vn "$module_conf_dist" "${module_conf_dist%.dist}"
    done
    shopt -u nullglob
fi

# Everything below only runs in the db-import container, which runs to
# completion before the auth/world servers are started.
if [[ "$ACORE_COMPONENT" == "dbimport" ]]; then
    "$@"

    # shellcheck source=/dev/null
    source /azerothcore/apps/docker/scripts/bootstrap.sh

    # Neither step is worth failing the import (and with it the whole stack)
    # over: the databases are already in place at this point.
    ac_bootstrap_realmlist || echo "[bootstrap] Realmlist update failed, continuing." >&2
    ac_bootstrap_admin_account || echo "[bootstrap] Admin account creation failed, continuing." >&2

    exit 0
fi

echo "Starting $ACORE_COMPONENT..."

exec "$@"
