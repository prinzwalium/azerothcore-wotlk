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
variable "PLAYERBOTS_REF" {
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
