import XCTest
@testable import Pastry
import Cocoa

// MARK: - AppIconProvider 测试套件
// 测试主题色提取、哈希确定性、默认值、缓存

final class AppIconProviderTests: XCTestCase {

    var provider: AppIconProvider!

    override func setUp() {
        super.setUp()
        provider = AppIconProvider(forTesting: ())
    }

    override func tearDown() {
        provider = nil
        super.tearDown()
    }

    // MARK: - themeColor: nil / 空

    func testThemeColorNilReturnsAccentColor() {
        let color = provider.themeColor(for: nil)
        XCTAssertEqual(color, NSColor.controlAccentColor)
    }

    func testThemeColorEmptyReturnsAccentColor() {
        let color = provider.themeColor(for: "")
        XCTAssertEqual(color, NSColor.controlAccentColor)
    }

    // MARK: - themeColor: 未知应用哈希色（确定性）

    func testThemeColorUnknownAppDeterministic() {
        let color1 = provider.themeColor(for: "MyCustomApp")
        let color2 = provider.themeColor(for: "MyCustomApp")
        XCTAssertEqual(color1, color2, "相同应用名应返回相同颜色")
    }

    func testHeaderForegroundUsesDarkInkOnLightColors() {
        XCTAssertTrue(AppIconProvider.prefersDarkForeground(on: .white))
        XCTAssertTrue(AppIconProvider.prefersDarkForeground(on: NSColor(srgbRed: 0.72, green: 0.90, blue: 0.98, alpha: 1)))
    }

    func testHeaderForegroundUsesWhiteOnDarkColors() {
        XCTAssertFalse(AppIconProvider.prefersDarkForeground(on: .black))
        XCTAssertFalse(AppIconProvider.prefersDarkForeground(on: NSColor(srgbRed: 0.08, green: 0.16, blue: 0.30, alpha: 1)))
    }

    // MARK: - icon: nil / 空

    func testIconNilReturnsDefault() {
        let icon = provider.icon(for: nil)
        XCTAssertFalse(icon.size.width == 0, "应返回有效图标")
    }

    func testIconEmptyReturnsDefault() {
        let icon = provider.icon(for: "")
        XCTAssertFalse(icon.size.width == 0, "应返回有效图标")
    }

    // MARK: - cachedIcon（筛选气泡首帧）

    func testCachedIconMissReturnsNil() {
        XCTAssertNil(
            provider.cachedIcon(for: "AppThatWasNeverLoaded-\(UUID().uuidString)"),
            "未加载过的应用名不应假装命中缓存"
        )
    }

    func testCachedIconHitAfterIconLoad() {
        let name = "PastryCacheHit-\(UUID().uuidString)"
        _ = provider.icon(for: name)
        let cached = provider.cachedIcon(for: name)
        XCTAssertNotNil(cached, "icon(for:) 之后 cachedIcon 应命中")
    }

    func testCachedIconNilAndEmpty() {
        XCTAssertNil(provider.cachedIcon(for: nil))
        XCTAssertNil(provider.cachedIcon(for: ""))
    }

    // MARK: - cachedThemeColor（卡片入场首帧）

    func testCachedThemeColorMissReturnsNil() {
        XCTAssertNil(
            provider.cachedThemeColor(for: "AppThemeNeverLoaded-\(UUID().uuidString)"),
            "未加载过的应用名不应假装命中主题色缓存"
        )
    }

    func testCachedThemeColorHitAfterThemeColorLoad() {
        let name = "PastryThemeCacheHit-\(UUID().uuidString)"
        _ = provider.themeColor(for: name)
        XCTAssertNotNil(provider.cachedThemeColor(for: name), "themeColor(for:) 之后 cachedThemeColor 应命中")
    }

    func testCachedThemeColorNilAndEmpty() {
        XCTAssertNil(provider.cachedThemeColor(for: nil))
        XCTAssertNil(provider.cachedThemeColor(for: ""))
    }

    /// 卡片首帧模式：只读 cached*，未命中时用 accent，且不得触发扫盘/抽色。
    func testFirstFrameThemeColorPatternLeavesCachesCold() {
        let name = "Safari"
        let display = provider.cachedThemeColor(for: name) ?? NSColor.controlAccentColor
        XCTAssertEqual(display, NSColor.controlAccentColor)
        XCTAssertNil(provider.cachedIcon(for: name), "cachedThemeColor miss 不应副作用写入 icon 缓存")
        XCTAssertNil(provider.cachedThemeColor(for: name), "cachedThemeColor miss 不应副作用写入 color 缓存")
    }

    func testIconUnknownAppReturnsDefault() {
        let icon = provider.icon(for: "DefinitelyNotARealApp")
        // 未知应用不应有高清表示，返回的是默认占位图标
        let highResCount = icon.representations.filter { rep in
            rep.pixelsWide >= 256 || rep.pixelsHigh >= 256
        }.count
        XCTAssertEqual(highResCount, 0, "未知应用的图标不应包含高清表示")
    }

    // MARK: - 缓存

    func testThemeColorCaching() {
        let color1 = provider.themeColor(for: "Safari")
        let color2 = provider.themeColor(for: "Safari")
        // 缓存应返回同一对象（指针相等）
        XCTAssertTrue(color1 === color2)
    }

    func testIconCaching() {
        let icon1 = provider.icon(for: "Safari")
        let icon2 = provider.icon(for: "Safari")
        // 缓存应返回同一对象
        XCTAssertTrue(icon1 === icon2)
    }

}
