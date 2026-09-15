#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="${CONF_DIR:-/azerothcore/env/dist/etc}"
LOGS_DIR="${LOGS_DIR:-/azerothcore/env/dist/logs}"
REF_DIR="${REF_DIR:-/azerothcore/env/ref/etc}"

# Appends to "$2" every "Key = Value" line of "$1" whose key is not already set
# there, and says how many it added.
#
# The configs live in a volume that outlives the image, and the copies below are
# deliberately no-clobber so local edits survive an update. That leaves nothing
# to introduce options a newer build added: the server logs a "Missing property"
# warning for each and falls back to its compiled-in default, which is not
# necessarily the default the config ships. Keys already present are left alone,
# commented-out ones count as absent (the parser does not see them either), so
# this only ever adds and is a no-op once the file is current.
ac_sync_new_options() {
    local dist="$1"
    local conf="$2"

    [[ -f "$dist" && -f "$conf" ]] || return 0

    local added
    added="$(awk '
        function keyof(line,   i, k) {
            if (line ~ /^[[:space:]]*#/)
                return ""
            i = index(line, "=")
            if (i == 0)
                return ""
            k = substr(line, 1, i - 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
            return k
        }
        NR == FNR { k = keyof($0); if (k != "") seen[k] = 1; next }
        { k = keyof($0); if (k != "" && !(k in seen)) print }
    ' "$conf" "$dist")"

    [[ -n "$added" ]] || return 0

    {
        echo ""
        echo "# Added by the container entrypoint on $(date -u +%Y-%m-%dT%H:%M:%SZ):"
        echo "# options that $(basename "$dist") has and this file did not. Edit them freely,"
        echo "# they are only ever added once."
        echo "$added"
    } >> "$conf"

    echo "$(printf '%s\n' "$added" | wc -l) new option(s) added to $conf"
}

# Materializes the configs in the shared volume. Called under a lock because the
# auth and world servers start concurrently and would otherwise both append the
# same new options to the module configs they share.
ac_prepare_configs() {
    # Copy all default config files to env/dist/etc if they don't already exist
    # -r == recursive
    # -n == no clobber (don't overwrite)
    # -v == be verbose
    cp -rnv "$REF_DIR"/* "$CONF_DIR"

    # The ".conf.dist" files are references rather than anything a user edits, so
    # unlike the copies above they always track the image. This is also what makes
    # the comparison below meaningful: against a stale dist there is by definition
    # nothing new to find.
    local dist rel
    while IFS= read -r -d '' dist; do
        rel="${dist#"$REF_DIR"/}"
        mkdir -p "$CONF_DIR/$(dirname "$rel")"
        cp -f "$dist" "$CONF_DIR/$rel"
    done < <(find "$REF_DIR" -name '*.conf.dist' -print0)

    local conf="$CONF_DIR/$ACORE_COMPONENT.conf"
    local conf_dist="$CONF_DIR/$ACORE_COMPONENT.conf.dist"

    # Copy the "dist" file to the "conf" if the conf doesn't already exist
    if [[ -f "$conf_dist" ]]; then
        cp -vn "$conf_dist" "$conf"
        ac_sync_new_options "$conf_dist" "$conf"
    else
        touch "$conf"
    fi

    # Module configs are only read from "<name>.conf", never from
    # "<name>.conf.dist", so every shipped module config gets materialized the
    # same way as the component config above. Without this, playerbots.conf would
    # never exist and every AiPlayerbot.* setting would silently fall back to its
    # compiled-in default.
    if [[ -d "$CONF_DIR/modules" ]]; then
        shopt -s nullglob
        local module_conf_dist
        for module_conf_dist in "$CONF_DIR"/modules/*.conf.dist; do
            cp -vn "$module_conf_dist" "${module_conf_dist%.dist}"
            ac_sync_new_options "$module_conf_dist" "${module_conf_dist%.dist}"
        done
        shopt -u nullglob
    fi
}

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

# The lock is what keeps the concurrently started auth and world servers from
# both appending the same new options to the module configs they share. Failing
# to take it is not worth refusing to start over -- a missing flock or an
# unwritable conf dir leaves the old, unsynchronized behaviour.
if command -v flock > /dev/null && exec {conf_lock}> "$CONF_DIR/.entrypoint.lock" 2> /dev/null; then
    flock "$conf_lock"
    ac_prepare_configs
    exec {conf_lock}>&-
else
    ac_prepare_configs
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
    ac_bootstrap_ahbot || echo "[bootstrap] Auction house bot setup failed, continuing." >&2

    exit 0
fi

echo "Starting $ACORE_COMPONENT..."

exec "$@"
