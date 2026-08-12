#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
    cat >&2 <<'USAGE'
Usage:
  mise run release -- <version> [--allow-dirty] [--publish]

Examples:
  mise run release -- 1.4.17
  mise run release -- 1.4.17 --allow-dirty
  mise run release -- 1.4.17 --publish
USAGE
    exit 2
fi

exec ./release.sh "$@"
