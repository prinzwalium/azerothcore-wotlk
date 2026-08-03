#!/usr/bin/env bash
#
# First-run bootstrap helpers, sourced by apps/docker/entrypoint.sh in the
# db-import container after the databases have been imported.
#
# Both steps are opt-in (they do nothing unless the matching environment
# variables are set) and idempotent, so they can run on every start.

# Parse an AzerothCore connection string ("host;port;user;password;database")
# into the AC_DB_* variables used by _ac_mysql below.
_ac_parse_db_info() {
    local info="${1:-}"

    if [[ -z "$info" ]]; then
        return 1
    fi

    IFS=';' read -r AC_DB_HOST AC_DB_PORT AC_DB_USER AC_DB_PASS AC_DB_NAME <<< "$info"

    [[ -n "$AC_DB_HOST" && -n "$AC_DB_PORT" && -n "$AC_DB_USER" && -n "$AC_DB_NAME" ]]
}

# Run the mysql client against the auth database. The password is passed
# through MYSQL_PWD so it never lands in the process list.
_ac_mysql_auth() {
    MYSQL_PWD="$AC_DB_PASS" mysql \
        --host="$AC_DB_HOST" \
        --port="$AC_DB_PORT" \
        --user="$AC_DB_USER" \
        --default-character-set=utf8mb4 \
        "$AC_DB_NAME" "$@"
}

# Escape a value for use inside single quotes in a SQL literal.
_ac_sql_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    printf '%s' "${value//\'/\'\'}"
}

_ac_bootstrap_connect() {
    if ! _ac_parse_db_info "${AC_LOGIN_DATABASE_INFO:-}"; then
        echo "[bootstrap] AC_LOGIN_DATABASE_INFO is not set or malformed, skipping." >&2
        return 1
    fi

    if ! _ac_mysql_auth -N -B -e "SELECT 1;" > /dev/null 2>&1; then
        echo "[bootstrap] Could not reach the auth database, skipping." >&2
        return 1
    fi
}

# Point the realm at the address clients should connect to. Without this the
# realmlist keeps its default of 127.0.0.1 and remote clients get stuck at
# "Success!" after choosing the realm.
ac_bootstrap_realmlist() {
    local address="${REALM_ADDRESS:-}"

    if [[ -z "$address" ]]; then
        return 0
    fi

    _ac_bootstrap_connect || return 0

    local name="${REALM_NAME:-AzerothCore}"
    local port="${REALM_PORT:-8085}"
    local local_address="${REALM_LOCAL_ADDRESS:-$address}"

    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        echo "[bootstrap] REALM_PORT must be numeric, got '$port'. Skipping realmlist update." >&2
        return 0
    fi

    echo "[bootstrap] Setting realm 1 to '$name' at $address:$port"

    _ac_mysql_auth -e "UPDATE realmlist SET
        name = '$(_ac_sql_escape "$name")',
        address = '$(_ac_sql_escape "$address")',
        localAddress = '$(_ac_sql_escape "$local_address")',
        port = $port
        WHERE id = 1;"
}

# Create the first admin account so that no one has to attach to the
# worldserver console just to be able to log in.
ac_bootstrap_admin_account() {
    if [[ -z "${ADMIN_USERNAME:-}" || -z "${ADMIN_PASSWORD:-}" ]]; then
        return 0
    fi

    _ac_bootstrap_connect || return 0

    local username="${ADMIN_USERNAME^^}"
    local existing

    existing="$(_ac_mysql_auth -N -B -e \
        "SELECT COUNT(*) FROM account WHERE username = '$(_ac_sql_escape "$username")';")"

    if [[ "$existing" != "0" ]]; then
        echo "[bootstrap] Account '$username' already exists, leaving it untouched."
        return 0
    fi

    echo "[bootstrap] Creating account '$username'"

    if ! python3 /azerothcore/apps/docker/scripts/srp6.py | _ac_mysql_auth; then
        echo "[bootstrap] Failed to create account '$username'." >&2
        return 1
    fi

    echo "[bootstrap] Account '$username' created."
}
