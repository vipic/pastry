#!/bin/bash
# 向剪贴板依次写入 Pastry 支持的所有类型
# 用法: scripts/populate_clipboard.sh
# Pastry 运行中会自动捕获每一项；运行前建议先在应用内"清空全部记录"
cd "$(dirname "$0")/.."

SLEEP=0.8
PBWRITE=".local/bin/pbwrite"

log()   { echo "→ $*"; }
err()   { echo "  ✗ $*"; }
ok()    { echo "  ✓"; }

echo "══════════════════════════════════════"
echo "  Pastry 剪贴板填充脚本"
echo "  将写入文本、链接、HTML、RTF、文件和图片样本"
echo "══════════════════════════════════════"
echo

# 编译 pbwrite（如需要）
if [[ ! -x "$PBWRITE" || scripts/pbwrite.swift -nt "$PBWRITE" ]]; then
    echo "→ 正在编译 pbwrite…"
    mkdir -p "$(dirname "$PBWRITE")"
    swiftc scripts/pbwrite.swift -o "$PBWRITE" || { echo "✗ 编译失败"; exit 1; }
fi

# 选择存在的样本文件。.zprofile 在不少环境里不存在，优先用常见 dotfile 兜底。
SAMPLE_FILES=()
for f in "$HOME/.zshrc" "$HOME/.gitconfig" "$HOME/.zprofile" "$HOME/.zshenv" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc"; do
    [[ -f "$f" ]] && SAMPLE_FILES+=("$f")
done
if (( ${#SAMPLE_FILES[@]} == 0 )); then
    echo "✗ 未找到可用的样本文件，跳过文件类条目"
fi

if ! pgrep -x Pastry >/dev/null 2>&1; then
    echo "⚠  Pastry 好像没在运行。按回车继续，Ctrl-C 退出。"
    read -r
fi

echo "3 秒后开始…"
sleep 3

# ── 1. 短文本 ──
log "text — 短文本"
echo "Hello, Pastry! 这是第一条剪贴板记录。" | pbcopy && ok || err "pbcopy 失败"
sleep "$SLEEP"

# ── 2. 长文本（多行）──
log "text — 长文本（多行）"
cat <<'EOF' | pbcopy
Pastry 是一款 macOS 剪贴板管理器，用来找回刚刚复制过的临时内容。

特性：
• 记录文本、链接、图片、文件、RTF 和 HTML
• 支持全文搜索、来源与时间筛选
• 支持收藏备注、多选、预览、拖拽和快捷粘贴
• 历史数据仅存本机，数据库使用 SQLite + FTS5

项目地址：https://github.com/vipic/pastry

这段多行内容用于检查长文本卡片的换行、截断、搜索和复制行为。
EOF
ok
sleep "$SLEEP"

# ── 2b. 纯 URL（整段为链接，Pastry 标记 isURL）──
log "text — 纯 URL（链接条目）"
"$PBWRITE" url "https://github.com/vipic/pastry" && ok || err "URL 写入失败"
sleep "$SLEEP"

# ── 3. HTML ──
log "html — HTML 片段"
"$PBWRITE" html "<h2>Pastry HTML 样本</h2><ul><li><b>搜索</b> — 查找历史内容</li><li><b>预览</b> — 查看链接与文件</li><li><b>存储</b> — SQLite 本地历史</li></ul><p style='color:#888'>用于检查富文本解析和展示</p>" && ok || err "HTML 写入失败"
sleep "$SLEEP"

# ── 4. RTF — 写临时文件再用 pbwrite 读取 ──
log "rtf — 富文本"
RTF_FILE=$(mktemp /tmp/pastry_rtf_XXXXXX.rtf)
cat > "$RTF_FILE" << 'RTFEOF'
{\rtf1\ansi\deff0
{\fonttbl{\f0 Helvetica;}{\f1 Helvetica-Oblique;}}
\f0\fs32\b Pastry\b0
\fs24 是 macOS 26+ 的原生剪贴板管理器。\par
\f1\i 支持：\i0 文本、RTF、HTML、图片、文件路径。\par
\f0 github.com/vipic/pastry
}
RTFEOF
"$PBWRITE" rtf "$RTF_FILE" && ok || err "RTF 写入失败"
rm -f "$RTF_FILE"
sleep "$SLEEP"

# ── 5. 单文件路径 ──
if (( ${#SAMPLE_FILES[@]} >= 1 )); then
    log "fileURL — 单个文件"
    "$PBWRITE" file "${SAMPLE_FILES[0]}" && ok || err "单文件写入失败"
    sleep "$SLEEP"
fi

# ── 6. 多文件路径（3 个文件合并为 1 条）──
if (( ${#SAMPLE_FILES[@]} >= 2 )); then
    count=${#SAMPLE_FILES[@]}
    (( count > 3 )) && count=3
    log "fileURL — 多个文件（${count} 个合并为 1 条）"
    "$PBWRITE" file "${SAMPLE_FILES[@]:0:$count}" && ok || err "多文件写入失败"
    sleep "$SLEEP"
fi

# ── 7. 图片 — 纯色 ──
log "image — 纯色 (200×120, 蓝色)"
IMG_FILE=$(mktemp /tmp/pastry_img_XXXXXX.png)
python3 -c "
from PIL import Image
img = Image.new('RGB', (200, 120), color=(30, 100, 220))
img.save('$IMG_FILE', 'PNG')
" && "$PBWRITE" image "$IMG_FILE" && ok || err "纯色图片写入失败"
rm -f "$IMG_FILE"
sleep "$SLEEP"

# ── 8. 图片 — 渐变 ──
log "image — 渐变 (300×180, 绿→紫)"
IMG_FILE=$(mktemp /tmp/pastry_img_XXXXXX.png)
python3 -c "
from PIL import Image
w, h = 300, 180
img = Image.new('RGB', (w, h))
for x in range(w):
    r = int(40 + (180 - 40) * x / w)
    g = int(200 - (200 - 30) * x / w)
    b = int(80 + (220 - 80) * x / w)
    for y in range(h):
        img.putpixel((x, y), (r, g, b))
img.save('$IMG_FILE', 'PNG')
" && "$PBWRITE" image "$IMG_FILE" && ok || err "渐变图片写入失败"
rm -f "$IMG_FILE"
sleep "$SLEEP"

# ── 9. 短文本 ──
log "text — 短文本（测试排序）"
echo "第二条文本 — 测试历史列表排序 @pastry" | pbcopy && ok || err "pbcopy 失败"
sleep "$SLEEP"

echo
echo "══════════════════════════════════════"
echo "  完成！打开 Pastry 面板 (⌘⇧V) 查看。"
echo "══════════════════════════════════════"
