# Deploying AzerothCore with Playerbots

Prebuilt images, no compiler on the server. The whole install is: copy two
files, fill in a `.env`, `docker compose up -d`.

## Requirements

* Docker Engine with the Compose v2 plugin
* ~25 GB of disk (client data is ~15 GB, the databases grow with the bot count)
* 4 GB RAM for a small realm; a few hundred bots want 8 GB or more

## Install

```bash
mkdir -p /opt/azerothcore && cd /opt/azerothcore

curl -fsSLO https://raw.githubusercontent.com/prinzwalium/azerothcore-wotlk/Playerbot/deploy/docker-compose.yml
curl -fsSL  https://raw.githubusercontent.com/prinzwalium/azerothcore-wotlk/Playerbot/deploy/.env.example -o .env

# Set at least DB_ROOT_PASSWORD, REALM_ADDRESS and ADMIN_PASSWORD
$EDITOR .env

docker compose pull
docker compose up -d
```

The first start takes a while and needs no supervision:

1. `ac-client-data-init` downloads the extracted client data (maps, vmaps,
   mmaps, dbc). This is the long one — several GB.
2. `ac-db-import` creates `acore_auth`, `acore_world` and `acore_characters`,
   applies the world/character SQL that ships with mod-playerbots, points the
   realm at `REALM_ADDRESS`, creates the admin account, and creates the auction
   house bot characters named in `AHBOT_CHARACTER_NAMES`.
3. `ac-worldserver` creates and populates `acore_playerbots`, then generates the
   bot accounts and characters. Expect this to take several minutes; with the
   default of 100 bots it is a few thousand database inserts.

Follow along with:

```bash
docker compose logs -f ac-worldserver
```

Bots are up once the log settles and `.playerbots rndbot stats` in the
worldserver console reports online bots.

## Connecting

Point the client's `realmlist.wtf` at the machine's address:

```
set realmlist your.server.address
```

and log in with the `ADMIN_USERNAME` / `ADMIN_PASSWORD` from `.env`.

## Using the bots

Bots respond to chat commands from the worldserver console and in game. A few
to start with (whisper them to a bot, or use them in party chat):

| Command | What it does |
|---|---|
| `.playerbots rndbot stats` | how many random bots exist and how many are online (GM) |
| `.playerbots bot list` | bots available to you |
| `.playerbots bot add <name>` | take control of a specific bot |
| `.playerbots bot addclass <class>` | summon a fresh bot of that class into your group |
| `.playerbots bot remove <name>` | dismiss a bot |
| `.playerbots bot self` | let your own character be driven by the bot AI |

The full command reference lives in the
[mod-playerbots wiki](https://github.com/mod-playerbots/mod-playerbots/wiki).

## The auction house bot

[mod-ah-bot-plus](https://github.com/NathanHandley/mod-ah-bot-plus) is built
into the images and keeps the auction house stocked, which otherwise stays empty
on a realm whose only other population is bots. It both sells (lists items) and
buys (bids on what players list).

It posts auctions as real characters rather than as the server, so it needs at
least one to exist. That is the only part of the setup that would normally be
manual — create a character in the client, find its GUID in the database, paste
it into the config — so the first start does it instead: `ac-db-import` creates
a dedicated `AHBOT_ACCOUNT_USERNAME` account, creates each character in
`AHBOT_CHARACTER_NAMES` on it, and writes their GUIDs into
`AuctionHouseBot.GUIDs` in the shared config volume before the worldserver
starts.

The characters it creates are placeholders: they own auctions and receive the
gold, and are not meant to be logged into. Playerbot characters deliberately are
not used — the module warns that driving one as an auction bot will likely crash
the server.

Expect a few hours before the auction house looks full; only
`AHBOT_ITEMS_PER_CYCLE` items are added per cycle.

| Command | What it does |
|---|---|
| `.ahbot update` | list a batch immediately instead of waiting for the next cycle |
| `.ahbot reload` | re-read `mod_ahbot.conf` after editing it |
| `.ahbot empty` | remove every bot auction (player auctions are untouched) |

To add more seller names later, append to `AHBOT_CHARACTER_NAMES` and
`docker compose up -d ac-db-import` — existing characters are reused, new ones
are created, and the GUID list is rewritten.

## Configuration

Most day-to-day settings can be set in `.env` without touching any config file.
The worldserver reads every `worldserver.conf` and `playerbots.conf` option from
the environment as well, using an upper-snake-case name prefixed with `AC_`:

| Config option | Environment variable |
|---|---|
| `AiPlayerbot.MaxRandomBots` | `AC_AI_PLAYERBOT_MAX_RANDOM_BOTS` |
| `AiPlayerbot.RandomBotAutologin` | `AC_AI_PLAYERBOT_RANDOM_BOT_AUTOLOGIN` |
| `AuctionHouseBot.EnableSeller` | `AC_AUCTION_HOUSE_BOT_ENABLE_SELLER` |
| `Rate.XP.Kill` | `AC_RATE_XP_KILL` |
| `MaxPlayerLevel` | `AC_MAX_PLAYER_LEVEL` |
| `Motd` | `AC_MOTD` |

Add them to the `environment:` block of `ac-worldserver` in
`docker-compose.yml` (or to a `docker-compose.override.yml`) and restart.

For the settings that are easier to edit as a file, the configs live in the
`ac-etc` volume:

```bash
docker compose cp ac-worldserver:/azerothcore/env/dist/etc/modules/playerbots.conf .
$EDITOR playerbots.conf
docker compose cp playerbots.conf ac-worldserver:/azerothcore/env/dist/etc/modules/playerbots.conf
docker compose restart ac-worldserver
```

Environment variables win over the config file, so unset the corresponding
`AC_*` variable if you want the file to take effect. This is also why
`AC_AUCTION_HOUSE_BOT_GUIDS` must stay unset: it would override the GUIDs the
first-run bootstrap discovered.

## Day-to-day operations

```bash
# worldserver console (Ctrl-P Ctrl-Q to detach without stopping it)
docker compose attach ac-worldserver

# create another account by hand
docker compose attach ac-worldserver
AC> account create myname mypassword

# update to a newer image build
docker compose pull && docker compose up -d

# stop everything, keeping the databases
docker compose down

# stop everything and throw the world away
docker compose down -v
```

## Updating

`AC_IMAGE_TAG=latest` follows the newest successful build of the `Playerbot`
branch. `docker compose pull && docker compose up -d` picks it up; `ac-db-import`
re-runs on every start and applies any new SQL, and the worldserver migrates the
playerbots database itself.

To pin a specific build instead, set `AC_IMAGE_TAG` to a commit sha — every
build is tagged with the sha it was built from.

## Where the images come from

`.github/workflows/docker-build.yml` builds them from this repository (the
mod-playerbots fork of the core) with `mod-playerbots` vendored in at a pinned
revision, and pushes them to GHCR. To build them yourself:

```bash
REGISTRY=my.registry/azerothcore PLAYERBOTS_REF=master \
  docker buildx bake -f docker-bake.hcl --push
```

or, from a checkout of this repository, `docker compose build` using the
top-level `docker-compose.yml`.

## Troubleshooting

**No bots appear.** Check that the module is actually in the image:

```bash
docker compose exec ac-worldserver cat /azerothcore/modules/mod-playerbots.rev
```

If that file is missing you are running an image built without the module —
the core alone has the playerbots patches but none of the bot AI. Then check
that the playerbots database exists and is populated:

```bash
docker compose exec ac-database \
  mysql -uroot -p"$DB_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM acore_playerbots.playerbots_random_bots;"
```

**The auction house stays empty.** Check the module is in the image, the same
way as for playerbots:

```bash
docker compose exec ac-worldserver cat /azerothcore/modules/mod-ah-bot-plus.rev
```

Then check that the seller has characters to post as:

```bash
docker compose exec ac-worldserver \
  grep AuctionHouseBot.GUIDs /azerothcore/env/dist/etc/modules/mod_ahbot.conf
```

`= 0` means the bootstrap never ran (empty `AHBOT_CHARACTER_NAMES`) or failed —
`docker compose logs ac-db-import | grep bootstrap` says which. Otherwise it is
usually just time; `.ahbot update` in the worldserver console forces a batch.

**Client gets stuck after choosing the realm.** `REALM_ADDRESS` was empty or
wrong, so the realmlist still points somewhere the client cannot reach:

```bash
docker compose exec ac-database \
  mysql -uroot -p"$DB_ROOT_PASSWORD" -e "SELECT id, name, address, port FROM acore_auth.realmlist;"
```

Fix `REALM_ADDRESS` in `.env` and `docker compose up -d ac-db-import` to rewrite
it.

**Worldserver exits right after start.** Almost always the client data: it must
finish downloading before the worldserver starts, and a half-downloaded
`ac-client-data` volume looks like missing maps. `docker compose logs
ac-client-data-init` shows whether it completed.
