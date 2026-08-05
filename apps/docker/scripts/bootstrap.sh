#!/usr/bin/env bash
#
# First-run bootstrap helpers, sourced by apps/docker/entrypoint.sh in the
# db-import container after the databases have been imported.
#
# Both steps are opt-in (they do nothing unless the matching environment
# variables are set) and idempotent, so they can run on every start.

# Run the mysql client against the database described by an AzerothCore
# connection string ("host;port;user;password;database"). The password is passed
# through MYSQL_PWD so it never lands in the process list.
_ac_mysql() {
    local info="${1:-}"
    shift

    local host port user pass name
    IFS=';' read -r host port user pass name <<< "$info"

    if [[ -z "$host" || -z "$port" || -z "$user" || -z "$name" ]]; then
        return 1
    fi

    MYSQL_PWD="$pass" mysql \
        --host="$host" \
        --port="$port" \
        --user="$user" \
        --default-character-set=utf8mb4 \
        "$name" "$@"
}

_ac_mysql_auth() {
    _ac_mysql "${AC_LOGIN_DATABASE_INFO:-}" "$@"
}

_ac_mysql_characters() {
    _ac_mysql "${AC_CHARACTER_DATABASE_INFO:-}" "$@"
}

# Escape a value for use inside single quotes in a SQL literal.
_ac_sql_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    printf '%s' "${value//\'/\'\'}"
}

_ac_bootstrap_connect() {
    if [[ -z "${AC_LOGIN_DATABASE_INFO:-}" ]]; then
        echo "[bootstrap] AC_LOGIN_DATABASE_INFO is not set, skipping." >&2
        return 1
    fi

    if ! _ac_mysql_auth -N -B -e "SELECT 1;" > /dev/null 2>&1; then
        echo "[bootstrap] Could not reach the auth database, skipping." >&2
        return 1
    fi
}

_ac_bootstrap_connect_characters() {
    if [[ -z "${AC_CHARACTER_DATABASE_INFO:-}" ]]; then
        echo "[bootstrap] AC_CHARACTER_DATABASE_INFO is not set, skipping." >&2
        return 1
    fi

    if ! _ac_mysql_characters -N -B -e "SELECT 1;" > /dev/null 2>&1; then
        echo "[bootstrap] Could not reach the characters database, skipping." >&2
        return 1
    fi
}

# Create an account from a username/password pair, unless it already exists.
# Echoes nothing; callers look the account id up afterwards.
_ac_create_account() {
    local username="${1^^}"
    local password="$2"
    local gmlevel="${3:-0}"

    local existing
    existing="$(_ac_mysql_auth -N -B -e \
        "SELECT COUNT(*) FROM account WHERE username = '$(_ac_sql_escape "$username")';")"

    if [[ "$existing" != "0" ]]; then
        echo "[bootstrap] Account '$username' already exists, leaving it untouched."
        return 0
    fi

    echo "[bootstrap] Creating account '$username'"

    AC_ACCOUNT_USERNAME="$username" \
    AC_ACCOUNT_PASSWORD="$password" \
    AC_ACCOUNT_GMLEVEL="$gmlevel" \
    AC_ACCOUNT_REALM_ID="${ADMIN_REALM_ID:--1}" \
        python3 /azerothcore/apps/docker/scripts/srp6.py | _ac_mysql_auth
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

    if ! _ac_create_account "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "${ADMIN_GMLEVEL:-3}"; then
        echo "[bootstrap] Failed to create account '${ADMIN_USERNAME^^}'." >&2
        return 1
    fi
}

# Create the account and characters that mod-ah-bot-plus posts auctions as, and
# write their GUIDs into the module config.
#
# The module needs one or more rows in `characters` whose GUIDs are listed in
# AuctionHouseBot.GUIDs; it only ever reads `guid` and `account` from them
# (AuctionHouseBot.cpp calls Player::Initialize, which is just
# Object::_Create -- the character is never loaded from the database), so a
# minimal row is enough and nothing here has to reproduce character creation.
#
# Playerbot characters must not be used for this: the module's README warns it
# will likely crash the server, hence the dedicated account.
ac_bootstrap_ahbot() {
    local names="${AHBOT_CHARACTER_NAMES:-}"

    if [[ -z "$names" ]]; then
        return 0
    fi

    local conf="${CONF_DIR:-/azerothcore/env/dist/etc}/modules/mod_ahbot.conf"

    if [[ ! -f "$conf" ]]; then
        echo "[bootstrap] $conf does not exist, so this image was built without" >&2
        echo "[bootstrap] mod-ah-bot-plus. Skipping auction house bot setup." >&2
        return 0
    fi

    _ac_bootstrap_connect || return 0
    _ac_bootstrap_connect_characters || return 0

    local account="${AHBOT_ACCOUNT_USERNAME:-AHBOT}"
    account="${account^^}"

    # The account exists only to own the auction characters; nobody ever logs
    # into it, so the password is random and deliberately not reported.
    local password
    password="$(python3 -c 'import secrets, string; print("".join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(16)))')"

    _ac_create_account "$account" "$password" 0 || {
        echo "[bootstrap] Failed to create the auction house bot account." >&2
        return 1
    }

    local account_id
    account_id="$(_ac_mysql_auth -N -B -e \
        "SELECT id FROM account WHERE username = '$(_ac_sql_escape "$account")';")"

    if [[ -z "$account_id" ]]; then
        echo "[bootstrap] Could not look up the '$account' account id." >&2
        return 1
    fi

    local guids=""
    local name

    while IFS= read -r name; do
        name="${name//[[:space:]]/}"

        if [[ -z "$name" ]]; then
            continue
        fi

        # WoW character names: letters only, 2-12 characters, first letter
        # capitalised. Anything else would be rejected at character creation and
        # would look broken in the auction house.
        if [[ ! "$name" =~ ^[A-Za-z]{2,12}$ ]]; then
            echo "[bootstrap] Skipping invalid auction bot character name '$name'." >&2
            continue
        fi

        name="${name,,}"
        name="${name^}"

        local guid
        guid="$(_ac_mysql_characters -N -B -e \
            "SELECT guid FROM characters WHERE name = '$(_ac_sql_escape "$name")';")"

        if [[ -z "$guid" ]]; then
            # `taximask` and `innTriggerId` are the only other NOT NULL columns
            # without a default; everything else the character would normally
            # carry is irrelevant to the module.
            _ac_mysql_characters -e "INSERT INTO characters
                (guid, account, name, race, class, gender, level, taximask, innTriggerId)
                SELECT IFNULL(MAX(guid), 0) + 1, $account_id,
                       '$(_ac_sql_escape "$name")', 1, 1, 0, 1, '', 0
                FROM characters;"

            guid="$(_ac_mysql_characters -N -B -e \
                "SELECT guid FROM characters WHERE name = '$(_ac_sql_escape "$name")';")"

            if [[ -z "$guid" ]]; then
                echo "[bootstrap] Failed to create auction bot character '$name'." >&2
                continue
            fi

            echo "[bootstrap] Created auction house bot character '$name' (guid $guid)"
        fi

        guids="${guids:+$guids,}$guid"
    done <<< "${names//,/$'\n'}"

    if [[ -z "$guids" ]]; then
        echo "[bootstrap] No usable auction house bot characters, leaving $conf alone." >&2
        return 1
    fi

    # AuctionHouseBot.GUIDs is the one setting that cannot come from the
    # environment: the GUIDs are only known once the characters exist. The
    # worldserver reads this same file from the shared etc volume, and it starts
    # only after this container has exited.
    if grep -qE '^[[:space:]]*AuctionHouseBot\.GUIDs[[:space:]]*=' "$conf"; then
        sed -i -E "s|^[[:space:]]*AuctionHouseBot\.GUIDs[[:space:]]*=.*|AuctionHouseBot.GUIDs = $guids|" "$conf"
    else
        printf '\nAuctionHouseBot.GUIDs = %s\n' "$guids" >> "$conf"
    fi

    echo "[bootstrap] AuctionHouseBot.GUIDs = $guids"
}
