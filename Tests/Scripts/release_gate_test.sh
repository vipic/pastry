#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/repo/scripts/lib" "$TEST_ROOT/repo/Sources/Pastry/Generated" "$TEST_ROOT/bin"
cp "$ROOT/release.sh" "$TEST_ROOT/repo/release.sh"
cp "$ROOT/scripts/lib/command_log.sh" "$TEST_ROOT/repo/scripts/lib/command_log.sh"

make_stub() {
    local name="$1"
    shift
    printf '#!/bin/bash\n%s\n' "$*" > "$TEST_ROOT/bin/$name"
    chmod +x "$TEST_ROOT/bin/$name"
}

make_stub git 'printf "git %s\n" "$*" >> "$COMMAND_LOG"; case "$1 $2" in "rev-list --count") echo 1;; "status --porcelain") :;; "tag --points-at") :;; "branch --show-current") echo main;; "remote get-url") :;; "rev-parse --verify") exit 1;; "ls-remote origin") :;; esac'
make_stub gh 'printf "gh %s\n" "$*" >> "$COMMAND_LOG"; if [ "$1 $2" = "repo view" ]; then echo owner/repo; elif [ "$1 $2" = "release view" ]; then exit 1; fi'
make_stub security 'echo "  1) ABC \"Nekutai\""'
make_stub mise 'printf "mise %s\n" "$*" >> "$COMMAND_LOG"; exit 42'

export COMMAND_LOG="$TEST_ROOT/commands.log"
if PATH="$TEST_ROOT/bin:$PATH" "$TEST_ROOT/repo/release.sh" 9.9.9 --publish >/dev/null 2>&1; then
    echo "release unexpectedly succeeded after failed validation" >&2
    exit 1
fi
grep -q '^mise run check$' "$COMMAND_LOG"
if grep -q '^git push' "$COMMAND_LOG" || grep -q '^gh release create' "$COMMAND_LOG"; then
    echo "publishing command ran after failed validation" >&2
    exit 1
fi
echo "release gate behavior test passed"
