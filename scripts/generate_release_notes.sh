#!/usr/bin/env bash
set -euo pipefail

base_tag="${1:-$(git describe --tags --abbrev=0 2>/dev/null || true)}"
head_ref="${2:-HEAD}"

if [[ -z "$base_tag" ]]; then
    echo "找不到用于生成更新日志的上一个版本标签。" >&2
    exit 1
fi
git rev-parse --verify --quiet "$base_tag^{commit}" >/dev/null || {
    echo "更新日志基准标签不存在：$base_tag" >&2
    exit 1
}
git rev-parse --verify --quiet "$head_ref^{commit}" >/dev/null || {
    echo "更新日志目标引用不存在：$head_ref" >&2
    exit 1
}

NOTES="$(git log "$base_tag..$head_ref" --no-merges --pretty=format:'- %s')"
if [[ -z "$NOTES" ]]; then
    echo "版本范围内没有可用于更新日志的提交：$base_tag..$head_ref" >&2
    exit 1
fi

printf '%s\n' "$NOTES"
