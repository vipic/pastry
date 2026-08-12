#!/usr/bin/env bash
# Single source of truth for repository shell syntax checks.
set -euo pipefail

cd "$(dirname "$0")/.."

scripts=(
    deploy.sh
    release.sh
    scripts/bench.sh
    scripts/check_shell.sh
    scripts/populate_clipboard.sh
    scripts/smoke.sh
    scripts/check_coverage.sh
    scripts/check_design_tokens.sh
    scripts/diagnostics.sh
    scripts/lib/command_log.sh
    scripts/next_version.sh
    scripts/verify_release.sh
    scripts/release_smoke.sh
    scripts/tasks/release.sh
    scripts/tasks/release-auto.sh
    scripts/tasks/publish.sh
)

for script in "${scripts[@]}"; do
    bash -n "$script"
done

echo "Shell syntax checks passed (${#scripts[@]} files)."
