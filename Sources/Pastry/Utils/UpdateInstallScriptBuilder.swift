import Foundation

enum UpdateInstallScriptBuilder {
    /// 把任意字符串转成 bash 单引号安全字面量：用 `'…'` 包裹，内部 `'` 转成 `'\''`。
    /// 防止 expectedVersion（来自 GitHub tag_name）等外部输入注入 shell 命令。
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 校验版本号只含数字和点，拒绝任何 shell 元字符。
    static func isValidVersionString(_ version: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789.")
        return !version.isEmpty && version.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// `updateDirectory` 是 App 自己的数据目录，helper 的日志与错误文件都写在这里。
    /// 不要退回 `/tmp`：那是固定且世界可写的路径，本机其他账户可以伪造「更新失败」文本，
    /// 而 App 下次启动会把它原样展示在真实窗口里。
    static func script(
        stableDMGPath: String,
        targetPath: String,
        expectedVersion: String,
        updateDirectory: String
    ) -> String {
        // 版本号严格校验：只允许数字和点，杜绝 shell 注入面
        let safeVersion = Self.isValidVersionString(expectedVersion) ? expectedVersion : "0.0.0"
        let dmg = Self.shellQuote(stableDMGPath)
        let target = Self.shellQuote(targetPath)
        let directory = Self.shellQuote(updateDirectory)

        return """
        #!/bin/bash
        set -e

        DMG=\(dmg)
        TARGET=\(target)
        UPDATE_DIR=\(directory)
        EXPECTED_VERSION="\(safeVersion)"
        LOG="$UPDATE_DIR/update.log"
        ERROR_FILE="$UPDATE_DIR/update_error.txt"
        mkdir -p "$UPDATE_DIR"
        rm -f "$LOG"
        exec >> "$LOG" 2>&1
        sleep 1
        echo "Pastry update started at $(date)"
        echo "Target: $TARGET"
        echo "Expected version: $EXPECTED_VERSION"
        TARGET_PARENT=$(dirname "$TARGET")
        TARGET_NAME=$(basename "$TARGET")
        BACKUP="$TARGET_PARENT/.${TARGET_NAME}.update-backup-$(date +%s)"
        rm -f "$ERROR_FILE"

        fail_update() {
            echo "❌ $1" >&2
            printf "%s\\n" "$1" > "$ERROR_FILE"
            if [ -n "${VOLUME:-}" ] && [ -d "$VOLUME" ]; then
                hdiutil detach "$VOLUME" -quiet || true
            fi
            open "$TARGET"
            exit 1
        }

        # 挂载 DMG
        MOUNT_OUTPUT=$(hdiutil attach -noverify -noautoopen -nobrowse "$DMG" 2>&1)
        VOLUME=$(echo "$MOUNT_OUTPUT" | grep '/Volumes/' | tail -1 | awk -F'\\t' '{print $NF}')

        if [ ! -d "$VOLUME/Pastry.app" ]; then
            fail_update "DMG 挂载失败或缺少 Pastry.app"
        fi

        CANDIDATE="$VOLUME/Pastry.app"
        CANDIDATE_BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CANDIDATE/Contents/Info.plist" 2>/dev/null || true)
        CANDIDATE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CANDIDATE/Contents/Info.plist" 2>/dev/null || true)
        if [ "$CANDIDATE_BUNDLE" != "com.nekutai.pastry" ]; then
            fail_update "更新包 Bundle ID 不匹配: $CANDIDATE_BUNDLE"
        fi
        if [ "$CANDIDATE_VERSION" != "$EXPECTED_VERSION" ]; then
            fail_update "更新包版本不匹配: $CANDIDATE_VERSION，期望 $EXPECTED_VERSION"
        fi

        if ! /usr/bin/codesign --verify --deep --strict "$CANDIDATE" 2>/dev/null; then
            fail_update "更新包签名校验失败"
        fi
        CANDIDATE_SIGNATURE=$(/usr/bin/codesign -dv "$CANDIDATE" 2>&1 || true)
        if echo "$CANDIDATE_SIGNATURE" | grep -q "Signature=adhoc"; then
            fail_update "更新包使用 ad-hoc 签名，拒绝自动更新"
        fi

        # 签名身份连续性校验：读取不到当前 App 的 designated requirement 时必须拒绝，
        # 否则 --verify --strict 只证明签名有效，不证明签名者身份（SWIFT-006）。
        CURRENT_REQ=$(/usr/bin/codesign -dr - "$TARGET" 2>&1 | sed -n 's/^.*designated => //p')
        if [ -z "$CURRENT_REQ" ]; then
            fail_update "无法读取当前 App 的签名要求，拒绝自动更新"
        fi
        CANDIDATE_REQ=$(/usr/bin/codesign -dr - "$CANDIDATE" 2>&1 | sed -n 's/^.*designated => //p')
        if [ "$CANDIDATE_REQ" != "$CURRENT_REQ" ]; then
            fail_update "更新包签名身份与当前 App 不匹配，拒绝自动更新"
        fi

        # 替换整个 .app；先备份，复制失败时恢复旧版本
        mv "$TARGET" "$BACKUP"
        if ! cp -R "$CANDIDATE" "$TARGET"; then
            rm -rf "$TARGET"
            mv "$BACKUP" "$TARGET"
            fail_update "更新包复制失败，已恢复旧版本"
        fi
        INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET/Contents/Info.plist" 2>/dev/null || true)
        if [ "$INSTALLED_VERSION" != "$EXPECTED_VERSION" ]; then
            rm -rf "$TARGET"
            mv "$BACKUP" "$TARGET"
            fail_update "安装后版本仍为 $INSTALLED_VERSION，期望 $EXPECTED_VERSION，已恢复旧版本"
        fi
        rm -rf "$BACKUP"

        # 卸载 DMG：卷被 Finder/Spotlight 占用时 detach 会失败，不能让它中断后面的重启（set -e）
        hdiutil detach "$VOLUME" -quiet || true

        # 清理
        rm -f "$DMG" "$0"

        open "$TARGET"
        """
    }
}
