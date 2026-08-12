#!/usr/bin/env bash
set -euo pipefail

app_dir="${1:-}"
expected_version="${2:-}"
if [[ -z "$app_dir" || -z "$expected_version" ]]; then
  echo "用法：scripts/verify_release.sh <Pastry.app> <x.y.z>" >&2
  exit 2
fi

plist="$app_dir/Contents/Info.plist"
executable="$app_dir/Contents/MacOS/Pastry"
icon="$app_dir/Contents/Resources/AppIcon.icns"
resources="$app_dir/Contents/Resources/Pastry_Pastry.bundle"
test -f "$plist"
test -x "$executable"
test -s "$icon"
test -d "$resources"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$expected_version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == "com.nekutai.pastry" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" == "26.0" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$plist")" == "true" ]]
codesign --verify --deep --strict "$app_dir"
if codesign -dv "$app_dir" 2>&1 | grep -Fq 'Signature=adhoc'; then
  echo "发布应用不能使用 ad-hoc 签名。" >&2
  exit 1
fi
echo "发布应用验收通过：$app_dir ($expected_version)"
