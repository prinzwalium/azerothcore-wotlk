# Docker

Full documentation is [on our wiki](https://www.azerothcore.org/wiki/install-with-docker#installation)

> Deploying a server? You probably want [`deploy/`](../../deploy/README.md)
> instead: prebuilt images, no compiling. This page is about building them.

## Playerbots

This is the mod-playerbots fork of AzerothCore, and the images built here
include the [mod-playerbots](https://github.com/mod-playerbots/mod-playerbots)
module. The core carries the playerbots patches, but the bot AI itself lives in
the module, and the core only compiles its playerbots support when the module is
present at CMake configure time — so `Dockerfile` clones it into
`modules/mod-playerbots` in a dedicated stage rather than relying on whoever
runs the build to have checked it out first.

Which revision is baked in is controlled by two build args:

```console
$ PLAYERBOTS_REF=master docker compose build
$ PLAYERBOTS_REF=<sha> docker buildx bake -f docker-bake.hcl
```

`PLAYERBOTS_REF` takes a branch, tag or commit sha; `PLAYERBOTS_REPO` points at
a different fork of the module. The worldserver image records what it was built
from in `/azerothcore/modules/mod-playerbots.rev`.

Note that the playerbots database (`acore_playerbots`) is created and migrated
by the module on worldserver startup, not by the db-import container, which is
why the worldserver image also ships the module's `data/sql/playerbots` tree.

## Building

### Prerequisites

Ensure that you have docker, docker compose (v2), and the docker buildx command
installed.

It's all bundled with [Docker Desktop](https://docs.docker.com/get-docker/),
though if you're using Linux you can install them through your distribution's
package manage or by using the [documentation from docker](https://docs.docker.com/engine/install/)

### Running the Build

1. Build containers with command

```console
$ docker compose build
```

    1. Note that the initial build will take a long time, though subsequent builds should be faster

2. Start containers with command

```console
$ docker compose up -d
# Skip the build step
$ docker compose up -d --build
```

    1. Note that this command may take a while the first time, for the database import

3. (on first install) You'll need to attach to the worldserver and create an Admin account

```console
$ docker compose attach ac-worldserver
AC> account create admin password 3 -1
```

    1. Or skip it: set `ADMIN_USERNAME` and `ADMIN_PASSWORD` (and `REALM_ADDRESS`,
       if clients connect from another machine) in a `.env` file next to
       `docker-compose.yml`, and the db-import container creates the account and
       fixes up the realmlist on first start. See
       [`apps/docker/scripts/bootstrap.sh`](scripts/bootstrap.sh).
