#!/usr/bin/env bash
set -euo pipefail

VERSION=""
if [[ "$#" -gt 0 && "$1" != --* ]]; then
    VERSION="$1"
    shift
else
    echo "正式发布必须显式传入版本号：mise run publish -- <x.y.z>" >&2
    exit 2
fi

echo "Publishing version: $VERSION"
exec ./release.sh "$VERSION" --publish "$@"
