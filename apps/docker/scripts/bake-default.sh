#!/usr/bin/env bash
#
# Prints the default value of a `variable` block in docker-bake.hcl:
#
#   $ apps/docker/scripts/bake-default.sh PLAYERBOTS_REF
#   b6696bdbd3740e575598d167d69f39f68cc0b907
#
# The build workflow uses this so that the module pins live in exactly one
# place. Keeping a second copy in the workflow is the sort of thing that stays
# right for a month and then quietly builds the wrong revision.
#
# `docker buildx bake --print` would resolve these properly, but the workflow
# needs the value before it sets buildx up, and the file is ours to keep simple.

set -euo pipefail

name="${1:?usage: bake-default.sh <VARIABLE_NAME>}"
file="${2:-docker-bake.hcl}"

if [[ ! -f "$file" ]]; then
    echo "bake-default: no such file: $file" >&2
    exit 1
fi

# A default of "" is legitimate (CACHE_FROM has one), so "found" is signalled by
# awk's exit status rather than by the output being non-empty.
if ! value="$(awk -v name="$name" '
    $0 ~ "^variable[[:space:]]+\"" name "\"[[:space:]]*\\{" { inside = 1; next }
    inside && /^\}/                                        { exit }
    inside && /^[[:space:]]*default[[:space:]]*=/ {
        if (match($0, /"[^"]*"/)) {
            print substr($0, RSTART + 1, RLENGTH - 2)
            found = 1
            exit
        }
    }
    END { if (!found) exit 1 }
' "$file")"; then
    echo "bake-default: no default found for variable \"$name\" in $file" >&2
    exit 1
fi

printf '%s\n' "$value"
