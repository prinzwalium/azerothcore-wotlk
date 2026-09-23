# Build definition for the published AzerothCore + mod-playerbots images.
#
# All four images share the same expensive `build` stage, and bake resolves it
# once for the whole group instead of once per image:
#
#   docker buildx bake -f docker-bake.hcl
#
# Used by .github/workflows/docker-build.yml, but it works locally too.

variable "REGISTRY" {
  default = "ghcr.io/prinzwalium/azerothcore-wotlk"
}

# Primary tag, e.g. "latest".
variable "TAG" {
  default = "latest"
}

# Secondary tag, normally the commit sha the images were built from.
variable "EXTRA_TAG" {
  default = "dev"
}

variable "PLAYERBOTS_REPO" {
  default = "https://github.com/mod-playerbots/mod-playerbots.git"
}

# Branch, tag or commit sha of mod-playerbots to bake into the images.
#
# Pinned, not "master". The module is vendored with a patch over four
# registration points (apps/docker/playerbots/), and upstream moves them often
# enough that tracking a branch turned every build into a coin toss: twice
# already a build broke on `git apply` for an upstream change unrelated to
# anything here, and a new module release silently added config options that a
# running deployment then logged as missing. Updating is now a deliberate act:
# bump this, regenerate the patch if `git apply` says to, rebuild.
#
# This is the single source of truth -- the workflow reads the default from
# here rather than keeping its own copy.
variable "PLAYERBOTS_REF" {
  default = "b6696bdbd3740e575598d167d69f39f68cc0b907"
}

variable "AHBOT_REPO" {
  default = "https://github.com/NathanHandley/mod-ah-bot-plus.git"
}

# Branch, tag or commit sha of mod-ah-bot-plus to bake into the images.
variable "AHBOT_REF" {
  default = "master"
}

# Build cache, empty by default so that local builds don't try to talk to a
# cache backend that only exists inside GitHub Actions. CI sets these to
# "type=gha,scope=..." / "type=gha,mode=max,scope=...".
variable "CACHE_FROM" {
  default = ""
}

variable "CACHE_TO" {
  default = ""
}

# Published images are built as Release: the debug info of a RelWithDebInfo
# build of the core plus mod-playerbots adds gigabytes to both the image and the
# disk the build itself needs. Override when you want symbols in crash dumps.
variable "BUILD_TYPE" {
  default = "Release"
}

# None of the published images ship the map extractors, so only the dbimport
# tool is built. Use "all" if you also want to build the `tools` image.
variable "TOOLS_BUILD" {
  default = "db-only"
}

group "default" {
  targets = ["worldserver", "authserver", "db-import", "client-data"]
}

target "_common" {
  context    = "."
  dockerfile = "apps/docker/Dockerfile"
  args = {
    PLAYERBOTS_REPO = PLAYERBOTS_REPO
    PLAYERBOTS_REF  = PLAYERBOTS_REF
    AHBOT_REPO      = AHBOT_REPO
    AHBOT_REF       = AHBOT_REF
    CTYPE           = BUILD_TYPE
    CTOOLS_BUILD    = TOOLS_BUILD
  }
  cache-from = CACHE_FROM == "" ? [] : [CACHE_FROM]
  cache-to   = CACHE_TO == "" ? [] : [CACHE_TO]
}

function "tags" {
  params = [component]
  result = [
    "${REGISTRY}/${component}:${TAG}",
    "${REGISTRY}/${component}:${EXTRA_TAG}",
  ]
}

target "worldserver" {
  inherits = ["_common"]
  target   = "worldserver"
  tags     = tags("worldserver")
}

target "authserver" {
  inherits = ["_common"]
  target   = "authserver"
  tags     = tags("authserver")
}

target "db-import" {
  inherits = ["_common"]
  target   = "db-import"
  tags     = tags("db-import")
}

target "client-data" {
  inherits = ["_common"]
  target   = "client-data"
  tags     = tags("client-data")
}
