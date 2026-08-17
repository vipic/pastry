import Cocoa
import OSLog

// MARK: - 应用图标与主题色提取
// 缓存已查询的应用图标和颜色，避免重复 I/O
final class AppIconProvider {

    nonisolated(unsafe) static let shared = AppIconProvider()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "appicon")

    private let iconCache = NSCache<NSString, NSImage>()
    private let colorCache = NSCache<NSString, NSColor>()
    private let lock = NSLock()

    private init() {}

    /// 测试专用
    init(forTesting: Void) {}

    // MARK: - 公开接口

    /// 获取应用图标（SF Symbol fallback）
    func icon(for appName: String?) -> NSImage {
        guard let name = appName, !name.isEmpty else {
            return defaultIcon
        }

        let nsName = name as NSString
        lock.lock()
        if let cached = iconCache.object(forKey: nsName) { lock.unlock(); return cached }
        lock.unlock()

        let icon = findAppIcon(named: name)

        lock.lock()
        iconCache.setObject(icon, forKey: nsName)
        lock.unlock()

        return icon
    }

    /// 仅读缓存，未命中返回 nil（筛选气泡首帧避免同步 I/O）
    func cachedIcon(for appName: String?) -> NSImage? {
        guard let name = appName, !name.isEmpty else { return nil }
        lock.lock()
        let icon = iconCache.object(forKey: name as NSString)
        lock.unlock()
        return icon
    }

    /// 仅读主题色缓存，未命中返回 nil（卡片入场首帧避免同步 I/O）
    func cachedThemeColor(for appName: String?) -> NSColor? {
        guard let name = appName, !name.isEmpty else { return nil }
        lock.lock()
        let color = colorCache.object(forKey: name as NSString)
        lock.unlock()
        return color
    }

    /// 获取主题色
    func themeColor(for appName: String?) -> NSColor {
        guard let name = appName, !name.isEmpty else {
            return NSColor.controlAccentColor
        }

        let nsName = name as NSString
        lock.lock()
        if let cached = colorCache.object(forKey: nsName) { lock.unlock(); return cached }
        lock.unlock()

        // 1. 从应用图标提取主色
        let appIcon = self.icon(for: appName)
        if let extracted = extractDominantColor(from: appIcon) {
            lock.lock()
            colorCache.setObject(extracted, forKey: nsName)
            lock.unlock()
            return extracted
        }

        // 2. 基于名称哈希生成稳定色
        let hash = name.hash
        let hue = abs(CGFloat(hash % 360)) / 360.0
        let color = NSColor(hue: hue, saturation: 0.6, brightness: 0.7, alpha: 1)
        lock.lock()
        colorCache.setObject(color, forKey: nsName)
        lock.unlock()
        return color
    }

    /// 为任意应用主题色选择对比度更高的标题前景色。
    static func prefersDarkForeground(on color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linearized(rgb.redComponent)
            + 0.7152 * linearized(rgb.greenComponent)
            + 0.0722 * linearized(rgb.blueComponent)
        let whiteContrast = 1.05 / (luminance + 0.05)
        let darkContrast = (luminance + 0.05) / 0.05
        return darkContrast >= whiteContrast
    }

    // MARK: - 内部方法

    private var defaultIcon: NSImage {
        if let path = Bundle.main.path(forResource: "placeholder-icon", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            ?? NSImage()
    }

    /// 通过应用名查找实际图标（优先读取 bundle 原始图标，避免系统为替身/快捷方式叠加角标）
    private func findAppIcon(named name: String) -> NSImage {
        // 1. 已知系统路径 — 先确认 .app 存在再取图标，避免 NSWorkspace 返回 GenericApplicationIcon
        let paths = [
            "/Applications/\(name).app",
            "/Applications/Utilities/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app",
            "/System/Library/CoreServices/\(name).app",
            "/System/Library/CoreServices/Applications/\(name).app",
            NSHomeDirectory() + "/Applications/\(name).app",
        ]
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if let icon = bundleIcon(at: URL(fileURLWithPath: path)) {
                return icon
            }
            let icon = NSWorkspace.shared.icon(forFile: path)
            return icon
        }

        // 2. 运行中的应用（不依赖文件系统）
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == name
        }) {
            if let bundleURL = runningApp.bundleURL,
               let icon = bundleIcon(at: bundleURL) {
                return icon
            }
            if let icon = runningApp.icon {
                return icon
            }
        }

        return defaultIcon
    }

    /// 读取 .app bundle 自己声明的原始 .icns，绕开 NSWorkspace 对 alias / shortcut 的装饰图标。
    private func bundleIcon(at appURL: URL) -> NSImage? {
        guard let bundle = Bundle(url: appURL),
              let resourcesURL = bundle.resourceURL,
              let rawIconName = bundle.infoDictionary?["CFBundleIconFile"] as? String,
              !rawIconName.isEmpty
        else {
            return nil
        }

        let iconNames: [String]
        if (rawIconName as NSString).pathExtension.isEmpty {
            iconNames = [rawIconName + ".icns", rawIconName]
        } else {
            iconNames = [rawIconName]
        }

        for iconName in iconNames {
            let iconURL = resourcesURL.appendingPathComponent(iconName)
            guard FileManager.default.fileExists(atPath: iconURL.path),
                  let icon = NSImage(contentsOf: iconURL)
            else {
                continue
            }
            return icon
        }

        return nil
    }

    /// 从应用图标提取主色
    private func extractDominantColor(from image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = min(cgImage.width, 32)
        let height = min(cgImage.height, 32)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, count: CGFloat = 0

        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let pr = CGFloat(pixels[i]) / 255
            let pg = CGFloat(pixels[i + 1]) / 255
            let pb = CGFloat(pixels[i + 2]) / 255
            let pa = CGFloat(pixels[i + 3]) / 255

            // 跳过透明像素和接近白色的像素
            if pa < 0.5 || (pr > 0.9 && pg > 0.9 && pb > 0.9) { continue }

            r += pr
            g += pg
            b += pb
            count += 1
        }

        guard count > 0 else { return nil }

        return NSColor(
            red: r / count,
            green: g / count,
            blue: b / count,
            alpha: 1
        )
    }

}

// MARK: - NSString convenience
extension String {
    func localizedCaseInsensitiveContains(_ other: String) -> Bool {
        range(of: other, options: [.caseInsensitive]) != nil
    }
}
