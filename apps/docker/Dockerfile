ARG UBUNTU_VERSION=24.04 # lts

# This target lays out the general directory skeleton for AzerothCore,
# This target isn't intended to be directly used
FROM ubuntu:$UBUNTU_VERSION AS skeleton

# Note: ARG instructions defined after FROM are available in this build stage.
# Placing ARG TZ here (after FROM) ensures it is accessible for configuring the timezone below.
ARG TZ=Etc/UTC
ARG DOCKER=1
ARG DEBIAN_FRONTEND=noninteractive

ENV AC_FORCE_CREATE_DB=1

RUN mkdir -pv \
        /azerothcore/bin                   \
        /azerothcore/data                  \
        /azerothcore/deps                  \
        /azerothcore/env/dist/bin          \
        /azerothcore/env/dist/data/Cameras \
        /azerothcore/env/dist/data/dbc     \
        /azerothcore/env/dist/data/maps    \
        /azerothcore/env/dist/data/mmaps   \
        /azerothcore/env/dist/data/vmaps   \
        /azerothcore/env/dist/logs         \
        /azerothcore/env/dist/temp         \
        /azerothcore/env/dist/etc          \
        /azerothcore/modules               \
        /azerothcore/src                   \
        /azerothcore/build

# Configure Timezone
RUN apt-get update                                                       \
    && apt-get install -y --no-install-recommends tzdata ca-certificates \
    && ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime                  \
    && echo "$TZ" > /etc/timezone                                          \
    && dpkg-reconfigure --frontend noninteractive tzdata                 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /azerothcore

##################
# Playerbots src #
##################

# This core is the mod-playerbots fork of AzerothCore: the playerbots patches
# live in the core, but the actual bot AI lives in the mod-playerbots module.
# Without the module in `modules/` at CMake configure time:
#
#   * `MOD_PLAYERBOTS` is never defined, so the playerbots database support in
#     the core is compiled out,
#   * no bot AI, no `.playerbots` commands, no `playerbots.conf` and no bots.
#
# So the module is vendored into the image here instead of expecting whoever
# builds the image to clone it into `modules/` first.
FROM ubuntu:$UBUNTU_VERSION AS playerbots-src

ARG DEBIAN_FRONTEND=noninteractive
ARG PLAYERBOTS_REPO="https://github.com/mod-playerbots/mod-playerbots.git"
# Branch, tag or full commit sha. CI resolves the branch to a commit sha so
# that the build cache stays keyed on the exact module revision.
ARG PLAYERBOTS_REF="master"

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /playerbots-src/mod-playerbots

# `git fetch <ref>` accepts branches, tags and commit shas alike, while
# `git clone --branch` would reject a raw sha.
RUN git init --quiet . \
    && git remote add origin "$PLAYERBOTS_REPO" \
    && git fetch --quiet --depth 1 origin "$PLAYERBOTS_REF" \
    && git checkout --quiet --detach FETCH_HEAD \
    && git rev-parse HEAD > /playerbots-src/mod-playerbots.rev \
    && rm -rf .git

##########################
# Auction house bot src  #
##########################

# mod-ah-bot-plus keeps the auction house stocked, which otherwise stays empty
# on a realm whose only other population is playerbots. It is vendored the same
# way as mod-playerbots above so that the image never depends on whoever builds
# it having cloned anything into `modules/`.
#
# The module ships no SQL and needs no CMakeLists of its own: AzerothCore's
# module system collects `modules/<name>/src` and installs
# `modules/<name>/conf/*.conf.dist` automatically (see modules/CMakeLists.txt).
FROM ubuntu:$UBUNTU_VERSION AS ahbot-src

ARG DEBIAN_FRONTEND=noninteractive
ARG AHBOT_REPO="https://github.com/NathanHandley/mod-ah-bot-plus.git"
# Branch, tag or full commit sha, resolved to a sha by CI for the same
# build-cache reasons as PLAYERBOTS_REF.
ARG AHBOT_REF="master"

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ahbot-src/mod-ah-bot-plus

RUN git init --quiet . \
    && git remote add origin "$AHBOT_REPO" \
    && git fetch --quiet --depth 1 origin "$AHBOT_REF" \
    && git checkout --quiet --detach FETCH_HEAD \
    && git rev-parse HEAD > /ahbot-src/mod-ah-bot-plus.rev \
    && rm -rf .git

# This target builds the docker image
# This target can be useful to inspect the explicit outputs from the build,
FROM skeleton AS build

ARG CTOOLS_BUILD="all"
ARG CTYPE="RelWithDebInfo"
ARG CCACHE_CPP2="true"
ARG CSCRIPTPCH="OFF"
ARG CSCRIPTS="static"
ARG CMODULES="static"
ARG CSCRIPTS_DEFAULT_LINKAGE="static"
ARG CWITH_WARNINGS="ON"
ARG CMAKE_EXTRA_OPTIONS=""
ARG GIT_DISCOVERY_ACROSS_FILESYSTEM=1

ARG CCACHE_DIR="/ccache"
ARG CCACHE_MAXSIZE="1000MB"
ARG CCACHE_SLOPPINESS="pch_defines,time_macros,include_file_mtime"
ARG CCACHE_COMPRESS=""
ARG CCACHE_COMPRESSLEVEL="9"
ARG CCACHE_COMPILERCHECK="content"
ARG CCACHE_LOGFILE=""

RUN apt-get update                                                     \
    && apt-get install -y --no-install-recommends                         \
        build-essential ccache libtool cmake-data ninja-build cmake clang    \
        git lsb-base curl unzip default-mysql-client openssl                  \
        default-libmysqlclient-dev libboost-all-dev libssl-dev libmysql++-dev \
        libreadline-dev zlib1g-dev libbz2-dev libncurses5-dev liblzma-dev  \
    && rm -rf /var/lib/apt/lists/*

COPY CMakeLists.txt /azerothcore/CMakeLists.txt
COPY conf /azerothcore/conf
COPY deps /azerothcore/deps
COPY src /azerothcore/src
COPY modules /azerothcore/modules

# mod-playerbots is added after the rest of `modules/` so that a locally
# checked out copy never shadows the pinned revision built into the image.
COPY --from=playerbots-src /playerbots-src/mod-playerbots /azerothcore/modules/mod-playerbots
COPY --from=ahbot-src /ahbot-src/mod-ah-bot-plus /azerothcore/modules/mod-ah-bot-plus

ARG CACHEBUST=1

WORKDIR /azerothcore/build

RUN --mount=type=cache,target=/ccache,sharing=locked \
    # This may seem silly (and it is), but AzerothCore wants the git repo at
    # build time. The git repo is _huge_ and it's not something that really
    # makes sense to mount into the container, but this way we can let the build
    # have the information it needs without including the hundreds of megabytes
    # of git repo into the container.
    --mount=type=bind,target=/azerothcore/.git,source=.git \
    git config --global --add safe.directory /azerothcore \
    && cmake /azerothcore \
       -G Ninja \
       -DCMAKE_INSTALL_PREFIX="/azerothcore/env/dist"  \
       -DAPPS_BUILD="all"                              \
       -DTOOLS_BUILD="$CTOOLS_BUILD"                   \
       -DSCRIPTS="$CSCRIPTS"                           \
       -DMODULES="$CMODULES"                           \
       -DWITH_WARNINGS="$CWITH_WARNINGS"               \
       -DCMAKE_BUILD_TYPE="$CTYPE"                     \
       -DCMAKE_CXX_COMPILER="clang++"                  \
       -DCMAKE_C_COMPILER="clang"                      \
       -DCMAKE_CXX_COMPILER_LAUNCHER="ccache"          \
       -DCMAKE_C_COMPILER_LAUNCHER="ccache"            \
       -DBoost_USE_STATIC_LIBS="ON"                    \
    && cmake --build . --config "$CTYPE" -j $(($(nproc) + 1)) \
    && cmake --install . --config "$CTYPE"

#############################
# Base runtime for services #
#############################

FROM skeleton AS runtime

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG DOCKER_USER=acore

ENV ACORE_COMPONENT=undefined

# Install base dependencies for azerothcore
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      libmysqlclient21 libreadline8 libicu74 libncurses5-dev \
      gettext-base default-mysql-client \
      adduser \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /azerothcore/env/dist/etc/ /azerothcore/env/ref/etc

VOLUME /azerothcore/env/dist/etc

ENV PATH="/azerothcore/env/dist/bin:$PATH"

# To use GID/UID 1000 in ubuntu > 23.04 the existing user must be deleted
# See https://bugs.launchpad.net/cloud-images/+bug/2005129
RUN userdel --remove ubuntu \
  && addgroup --gid "$GROUP_ID" "$DOCKER_USER" \
  && adduser --disabled-password --gecos '' --uid "$USER_ID" --gid "$GROUP_ID" "$DOCKER_USER" \
  && passwd -d "$DOCKER_USER" \
  && chown -R "$DOCKER_USER:$DOCKER_USER" /azerothcore

COPY --chown=$USER_ID:$GROUP_ID \
     --chmod=755 \
     apps/docker/entrypoint.sh /azerothcore/entrypoint.sh

COPY --chown=$USER_ID:$GROUP_ID \
     --chmod=755 \
     apps/docker/scripts/ /azerothcore/apps/docker/scripts/

USER $DOCKER_USER

ENTRYPOINT ["/usr/bin/env", "bash", "/azerothcore/entrypoint.sh"]

###############
# Auth Server #
###############

FROM runtime AS authserver
LABEL description="AzerothCore Auth Server"

# ARG values are scoped per build stage, so DOCKER_USER has to be redeclared
# here for the COPY --chown flags below to resolve to anything.
ARG DOCKER_USER=acore

ENV ACORE_COMPONENT=authserver
# Don't run database migrations. We can leave that up to the db-import container
ENV AC_UPDATES_ENABLE_DATABASES=0
# This disables user prompts. The console is still active, however
ENV AC_DISABLE_INTERACTIVE=1
ENV AC_CLOSE_IDLE_CONNECTIONS=0

COPY --chown=$DOCKER_USER:$DOCKER_USER \
     --from=build \
     /azerothcore/env/dist/bin/authserver /azerothcore/env/dist/bin/authserver


CMD ["authserver"]

################
# World Server #
################

FROM runtime AS worldserver

LABEL description="AzerothCore World Server"

# ARG values are scoped per build stage, so DOCKER_USER has to be redeclared
# here for the COPY --chown flags below to resolve to anything.
ARG DOCKER_USER=acore

ENV ACORE_COMPONENT=worldserver
# Don't run database migrations. We can leave that up to the db-import container
ENV AC_UPDATES_ENABLE_DATABASES=0
# This disables user prompts. The console is still active, however
ENV AC_DISABLE_INTERACTIVE=1
ENV AC_CLOSE_IDLE_CONNECTIONS=0

COPY --chown=$DOCKER_USER:$DOCKER_USER \
     --from=build \
     /azerothcore/env/dist/bin/worldserver /azerothcore/env/dist/bin/worldserver

# The playerbots database is created and populated by the module itself
# (mod-playerbots registers its own DatabaseScript), not by the db-import
# container, so the worldserver needs the playerbots SQL tree on disk at the
# path that was baked in as the CMake source directory.
COPY --chown=$DOCKER_USER:$DOCKER_USER \
     --from=playerbots-src \
     /playerbots-src/mod-playerbots/data/sql/playerbots \
     /azerothcore/modules/mod-playerbots/data/sql/playerbots

COPY --chown=$DOCKER_USER:$DOCKER_USER \
     --from=playerbots-src \
     /playerbots-src/mod-playerbots.rev /azerothcore/modules/mod-playerbots.rev

# mod-ah-bot-plus ships no SQL, so only the revision marker is carried into the
# runtime image; it is what `docker compose exec` checks against to tell whether
# a running image was built with the module.
COPY --chown=$DOCKER_USER:$DOCKER_USER \
     --from=ahbot-src \
     /ahbot-src/mod-ah-bot-plus.rev /azerothcore/modules/mod-ah-bot-plus.rev

VOLUME /azerothcore/env/dist/etc

CMD ["worldserver"]

#############
# DB Import #
#############

FROM runtime AS db-import

LABEL description="AzerothCore Database Import tool"

# ARG values are scoped per build stage, so they have to be redeclared here to
# be usable in the COPY --chown flags below.
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG DOCKER_USER=acore
ARG DEBIAN_FRONTEND=noninteractive

# python3 is used by the first-run bootstrap in the entrypoint to compute the
# SRP6 salt/verifier for the accounts it creates.
#
# This must be `python3`, not `python3-minimal`: the minimal package ships only
# a subset of the standard library, without `secrets` among others, so the
# bootstrap failed with ModuleNotFoundError and every account creation silently
# came to nothing. srp6.py no longer imports `secrets` either, but the full
# interpreter is what keeps the next stdlib import from being a surprise.
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

USER $DOCKER_USER

ENV ACORE_COMPONENT=dbimport

COPY --chown=$DOCKER_USER:$DOCKER_USER \
    data data

COPY --chown=$DOCKER_USER:$DOCKER_USER \
    modules modules

# dbimport applies the world/characters SQL shipped by every module listed in
# AC_MODULES_LIST, so mod-playerbots has to be present here as well.
COPY --chown=$DOCKER_USER:$DOCKER_USER \
     --from=playerbots-src \
     /playerbots-src/mod-playerbots /azerothcore/modules/mod-playerbots

COPY --chown=$DOCKER_USER:$DOCKER_USER\
     --from=build \
     /azerothcore/env/dist/bin/dbimport /azerothcore/env/dist/bin/dbimport

CMD [ "/azerothcore/env/dist/bin/dbimport" ]

###############
# Client Data #
###############

FROM skeleton AS client-data

LABEL description="AzerothCore client-data"

ENV DATAPATH=/azerothcore/env/dist/data

RUN apt-get update && \
    apt-get install -y curl unzip adduser && \
    rm -rf /var/lib/apt/lists/*

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG DOCKER_USER=acore

# To use GID/UID 1000 in ubuntu > 23.04 the existing user must be deleted
# See https://bugs.launchpad.net/cloud-images/+bug/2005129
RUN userdel --remove ubuntu \
  && addgroup --gid "$GROUP_ID" "$DOCKER_USER" \
  && adduser --disabled-password --gecos '' --uid "$USER_ID" --gid "$GROUP_ID" "$DOCKER_USER" \
  && passwd -d "$DOCKER_USER" \
  && chown -R "$DOCKER_USER:$DOCKER_USER" /azerothcore

COPY --chown=$DOCKER_USER:$DOCKER_USER apps apps

VOLUME /azerothcore/env/dist/data

USER $DOCKER_USER

CMD ["bash",  "-c", "source /azerothcore/apps/installer/includes/functions.sh && inst_download_client_data" ]

##################
# Map Extractors #
##################

FROM runtime AS tools

LABEL description="AzerothCore Tools"

# ARG values are scoped per build stage, so DOCKER_USER has to be redeclared
# here for the COPY --chown flags below to resolve to anything.
ARG DOCKER_USER=acore

WORKDIR /azerothcore/env/dist/

RUN mkdir -pv /azerothcore/env/dist/Cameras \
              /azerothcore/env/dist/dbc     \
              /azerothcore/env/dist/maps    \
              /azerothcore/env/dist/mmaps   \
              /azerothcore/env/dist/vmaps

COPY --chown=$DOCKER_USER:$DOCKER_USER --from=build \
  /azerothcore/env/dist/bin/map_extractor /azerothcore/env/dist/bin/map_extractor

COPY --chown=$DOCKER_USER:$DOCKER_USER --from=build \
  /azerothcore/env/dist/bin/mmaps_generator /azerothcore/env/dist/bin/mmaps_generator

COPY --chown=$DOCKER_USER:$DOCKER_USER --from=build \
  /azerothcore/env/dist/bin/vmap4_assembler /azerothcore/env/dist/bin/vmap4_assembler

COPY --chown=$DOCKER_USER:$DOCKER_USER --from=build \
  /azerothcore/env/dist/bin/vmap4_extractor /azerothcore/env/dist/bin/vmap4_extractor
