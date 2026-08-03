#!/usr/bin/env python3
"""Emit the SQL that registers an AzerothCore account.

AzerothCore stores accounts as SRP6 (salt, verifier) pairs, so an account
cannot be created with plain SQL alone. This reimplements
``Acore::Crypto::SRP6::MakeRegistrationData`` (see
``src/common/Cryptography/Authentication/SRP6.cpp``) so that a container can
create the first admin account without a human attaching to the worldserver
console.

Username, password and GM level are read from the environment so that the
password never shows up in the process list. The generated SQL is written to
stdout, ready to be piped into the mysql client.
"""

import hashlib
import os
import secrets
import sys

# Algorithm parameters, byte-for-byte the ones in SRP6.cpp.
N = int("894B645E89E1535BBDAD5B8B290650530801B18EBFBF5E8FAB3C82872A3E9BB7", 16)
G = 7
SALT_LENGTH = 32
VERIFIER_LENGTH = 32

MAX_ACCOUNT_LENGTH = 16
MAX_PASS_LENGTH = 16


def make_registration_data(username: str, password: str) -> "tuple[bytes, bytes]":
    """Return the (salt, verifier) pair for an account, both little endian."""
    salt = secrets.token_bytes(SALT_LENGTH)
    # v = g ^ H(s || H(u || ':' || p)) mod N
    inner = hashlib.sha1(f"{username}:{password}".encode("utf-8")).digest()
    x = int.from_bytes(hashlib.sha1(salt + inner).digest(), "little")
    verifier = pow(G, x, N).to_bytes(VERIFIER_LENGTH, "little")
    return salt, verifier


def main() -> int:
    # The core uppercases both before hashing (AccountMgr::CreateAccount), which
    # is what makes WoW logins case insensitive.
    username = os.environ.get("ADMIN_USERNAME", "").strip().upper()
    password = os.environ.get("ADMIN_PASSWORD", "").upper()
    gmlevel = os.environ.get("ADMIN_GMLEVEL", "3").strip()
    realm_id = os.environ.get("ADMIN_REALM_ID", "-1").strip()

    if not username or not password:
        print("ADMIN_USERNAME and ADMIN_PASSWORD must both be set", file=sys.stderr)
        return 1

    if len(username) > MAX_ACCOUNT_LENGTH:
        print(f"username must be at most {MAX_ACCOUNT_LENGTH} characters", file=sys.stderr)
        return 1

    if len(password) > MAX_PASS_LENGTH:
        print(f"password must be at most {MAX_PASS_LENGTH} characters", file=sys.stderr)
        return 1

    if not username.replace("_", "").replace("-", "").isalnum():
        print("username may only contain letters, digits, '-' and '_'", file=sys.stderr)
        return 1

    try:
        gmlevel_value = int(gmlevel)
        realm_id_value = int(realm_id)
    except ValueError:
        print("ADMIN_GMLEVEL and ADMIN_REALM_ID must be integers", file=sys.stderr)
        return 1

    if not 0 <= gmlevel_value <= 3:
        print("ADMIN_GMLEVEL must be between 0 and 3", file=sys.stderr)
        return 1

    salt, verifier = make_registration_data(username, password)

    # The username is validated above, so it is safe to inline here.
    print(
        "INSERT INTO account (username, salt, verifier, expansion, reg_mail, email, joindate) "
        f"VALUES ('{username}', 0x{salt.hex().upper()}, 0x{verifier.hex().upper()}, 2, '', '', NOW());"
    )
    print(
        "INSERT INTO realmcharacters (realmid, acctid, numchars) "
        "SELECT realmlist.id, account.id, 0 FROM realmlist, account "
        "LEFT JOIN realmcharacters ON acctid = account.id WHERE acctid IS NULL;"
    )

    if gmlevel_value > 0:
        print(
            "INSERT INTO account_access (id, gmlevel, RealmID, comment) "
            f"SELECT id, {gmlevel_value}, {realm_id_value}, 'created by docker bootstrap' "
            f"FROM account WHERE username = '{username}' "
            "ON DUPLICATE KEY UPDATE gmlevel = VALUES(gmlevel);"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
