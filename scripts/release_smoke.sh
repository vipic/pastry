#!/usr/bin/env bash
set -euo pipefail

dmg="${1:-}"
expected_version="${2:-}"
if [[ -z "$dmg" || -z "$expected_version" ]]; then
  echo "用法：scripts/release_smoke.sh <Pastry.dmg> <x.y.z>" >&2
  exit 2
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
identity="${CODESIGN_IDENTITY:-Nekutai}"
runner="$project_dir/.build/debug/PastryReleaseSmoke"
state_dir="$(mktemp -d /tmp/pastry-release-smoke.XXXXXX)"
mount_dir="$state_dir/mount"
copy_dir="$state_dir/copy"
app_dir="$copy_dir/Pastry.app"
app_executable=""
app_pid=""
mounted=0

cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then kill "$app_pid" 2>/dev/null || true; fi
  if [[ "$mounted" -eq 1 ]]; then hdiutil detach "$mount_dir" -force >/dev/null 2>&1 || true; fi
  case "$state_dir" in
    /tmp/pastry-release-smoke.*) rm -R "$state_dir" ;;
    *) echo "拒绝清理非发布验收目录：$state_dir" >&2; return 1 ;;
  esac
}
trap cleanup EXIT

[[ -f "$dmg" ]] || { echo "找不到 DMG：$dmg" >&2; exit 1; }
[[ "$identity" != "-" ]] || { echo "正式验收不能使用 ad-hoc 签名。" >&2; exit 1; }
security find-identity -v -p codesigning | grep -Fq "\"$identity\"" || {
  echo "找不到稳定代码签名身份：$identity" >&2
  exit 1
}

mkdir -p "$mount_dir" "$copy_dir"
hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$mount_dir" >/dev/null
mounted=1
[[ -L "$mount_dir/Applications" && "$(readlink "$mount_dir/Applications")" == "/Applications" ]] || {
  echo "DMG 缺少指向 /Applications 的拖放入口。" >&2
  exit 1
}
ditto "$mount_dir/Pastry.app" "$app_dir"
app_executable="$(realpath "$app_dir/Contents/MacOS/Pastry")"
hdiutil detach "$mount_dir" >/dev/null
mounted=0

"$project_dir/scripts/verify_release.sh" "$app_dir" "$expected_version"
swift build --package-path "$project_dir" --product PastryReleaseSmoke >/dev/null
codesign --force --sign "$identity" --identifier com.nekutai.pastry.release-smoke "$runner"

open -n -F "$app_dir"
for _ in {1..100}; do
  app_pid="$(pgrep -f "^$app_executable$" | head -1 || true)"
  [[ -n "$app_pid" ]] && break
  sleep 0.1
done
[[ -n "$app_pid" ]] || { echo "无法定位从 DMG 启动的正式应用进程。" >&2; exit 1; }
"$runner" --bundle-id com.nekutai.pastry --pid "$app_pid"
