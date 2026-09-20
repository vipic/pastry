#!/bin/bash
# Inspect Pastry runtime and local workflow logs.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMMAND_LOG_ROOT="$PROJECT_DIR/.local/logs"

usage() {
    cat <<'USAGE'
Usage:
  scripts/diagnostics.sh summary
  scripts/diagnostics.sh app [Pastry|Pastry Dev] [line-count]
  scripts/diagnostics.sh command <deploy|release|publish> [--full]

Examples:
  scripts/diagnostics.sh summary
  scripts/diagnostics.sh app Pastry 80
  scripts/diagnostics.sh app "Pastry Dev" 80
  scripts/diagnostics.sh command publish
  scripts/diagnostics.sh command publish --full
USAGE
}

show_summary() {
    echo "═══ 应用日志 ═══"
    for app_name in "Pastry" "Pastry Dev"; do
        local dir="$HOME/Library/Logs/$app_name"
        if [[ -d "$dir" ]]; then
            echo "  $app_name: $dir"
            while IFS= read -r -d '' file; do
                printf '    %6s  %s\n' "$(du -h "$file" | awk '{print $1}')" "$(basename "$file")"
            done < <(find "$dir" -maxdepth 1 -type f -print0 2>/dev/null)
        fi
    done

    echo ""
    echo "═══ 本地命令日志 ═══"
    local workflow latest finish
    for workflow in deploy release publish; do
        latest="$COMMAND_LOG_ROOT/$workflow/latest.log"
        if [[ -f "$latest" ]]; then
            finish="$(grep 'event=workflow.finish' "$latest" | tail -1 || true)"
            echo "  $workflow: $latest"
            [[ -n "$finish" ]] && echo "    $finish"
        fi
    done
}

show_app_log() {
    local app_name="${1:-Pastry}"
    local line_count="${2:-50}"
    local dir="$HOME/Library/Logs/$app_name"
    local file="$dir/runtime.jsonl"
    if [[ ! -f "$file" ]]; then
        echo "没有找到运行日志: $file" >&2
        echo "请在设置 → Security → Privacy 打开“开发诊断记录”，然后重新操作应用。" >&2
        exit 1
    fi

    runtime_log_stream() {
        local candidate
        for candidate in "$dir/runtime.3.jsonl" "$dir/runtime.2.jsonl" "$dir/runtime.1.jsonl" "$file"; do
            [[ -f "$candidate" ]] && cat "$candidate"
        done
    }

    if ! command -v python3 >/dev/null 2>&1; then
        echo "未找到 python3，以下显示原始 JSONL：" >&2
        runtime_log_stream | tail -n "$line_count"
        return
    fi

    runtime_log_stream | tail -n "$line_count" | python3 -c '
import json, sys
for raw in sys.stdin:
    try:
        row = json.loads(raw)
    except json.JSONDecodeError:
        continue
    duration = row.get("duration_ms")
    duration_text = f" {duration}ms" if duration is not None else ""
    metadata = row.get("metadata") or {}
    metadata_text = " ".join(f"{k}={v}" for k, v in sorted(metadata.items()))
    timestamp = row.get("timestamp", "-")
    level = row.get("level", "?").upper()
    context = row.get("context", "unclassified")
    category = row.get("category", "-")
    event = row.get("event", "-")
    message = row.get("message", "-")
    print(f"{timestamp} {level:8} {category}/{event}{duration_text} "
          f"{message} context={context} {metadata_text}".rstrip())
'
}

show_command_log() {
    local workflow="${1:-}"
    local mode="${2:-}"
    [[ -n "$workflow" ]] || { usage; exit 2; }
    local file="$COMMAND_LOG_ROOT/$workflow/latest.log"
    [[ -f "$file" ]] || { echo "没有找到命令日志: $file" >&2; exit 1; }

    echo "日志: $file"
    if [[ "$mode" == "--full" ]]; then
        cat "$file"
    else
        grep -E 'event=(workflow|stage|command)\.(start|finish)|event=artifact' "$file"
    fi
}

case "${1:-summary}" in
    summary)
        show_summary
        ;;
    app)
        shift
        show_app_log "${1:-Pastry}" "${2:-50}"
        ;;
    command)
        shift
        show_command_log "${1:-}" "${2:-}"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        exit 2
        ;;
esac
