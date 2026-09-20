import SwiftUI

enum UIConstants {
    enum Badge {
        /// 设置页状态方块（版本 / 辅助功能 / Security 行高）
        static let statusSize: CGFloat = 42
    }

    enum Card {
        static let contentVerticalPadding: CGFloat = 6
        static let footerBottomPadding: CGFloat = 8
        /// 卡片边长（快照测试与 overlay 空态高度同源）
        static let size: CGFloat = 240
    }

    enum Control {
        static let iconButtonSize: CGFloat = 28
        static let microIconSize: CGFloat = 12
        static let progressTrackHeight: CGFloat = 6
    }

    /// 5 档动效时长：0.10 / 0.15 / 0.22 / 0.28 / 0.50，spring damping 统一 0.85（paste 例外）
    enum Motion {
        static let instant = 0.10
        static let fast = 0.15
        static let medium = 0.22
        static let slow = 0.28
        static let paste = 0.50

        static let damping = 0.85
        static let pasteDamping = 0.6
    }

    enum OnDark {
        static let fillHover: Double = 0.14
        static let fillSubtle: Double = 0.08
        static let stroke: Double = 0.12
        static let textFaint: Double = 0.36
        static let textIdle: Double = 0.62
        static let textPrimary: Double = 0.92
        static let textSecondary: Double = 0.72
        static let textTertiary: Double = 0.52
    }

    enum OnLight {
        static let fillSoft: Double = 0.08
        static let fillZebra: Double = 0.02
        static let stroke: Double = 0.12
        static let textFaint: Double = 0.40
        static let textMuted: Double = 0.60
        static let textSecondary: Double = 0.72
        static let textStrong: Double = 0.82
        static let textTertiary: Double = 0.50
    }

    enum Onboarding {
        static let windowWidth: CGFloat = 640
    }

    enum Overlay {
        static let accentFillOpacity: Double = 0.12
        static let accentSoftOpacity: Double = 0.35
        static let cardSpacing: CGFloat = 10
        static let compactRowHeight: CGFloat = 84
        static let overlaySurfaceTintOpacity: Double = 0.55
    }

    /// 6 档圆角阶梯：4 / 6 / 8 / 10 / 12 / 24
    enum Radius {
        static let sm: CGFloat = 4
        static let control: CGFloat = 6
        static let button: CGFloat = 8
        static let card: CGFloat = 10
        static let panel: CGFloat = 12
        static let tray: CGFloat = 24
    }

    enum Settings {
        static let borderOpacity: Double = 0.16
        static let cardPadding: CGFloat = 16
        static let hairlineOpacity: Double = 0.10
        /// 按下态 / 键帽填充共用
        static let pressedOpacity: Double = 0.88
        /// 行左右 inset；原 compact card padding 并入
        static let rowHorizontalPadding: CGFloat = 14
        /// 设置行 / 快捷键键帽行同高
        static let rowMinHeight: CGFloat = 48
        static let secondaryFillOpacity: Double = 0.72
        /// Security / danger 浅色 wash（原 0.045–0.06 并档）
        static let washOpacity: Double = 0.05
    }

    /// 仅保留跨文件阴影预设；组件私有阴影下沉到各文件 `Local`
    enum Shadow {
        /// 浮层双层阴影（overlay 托盘 / 确认弹窗共用）
        enum Floating {
            static let primaryOpacity: Double = 0.24
            static let primaryRadius: CGFloat = 16
            static let primaryY: CGFloat = 10
            static let secondaryOpacity: Double = 0.10
            static let secondaryRadius: CGFloat = 4
            static let secondaryY: CGFloat = 2
        }

        enum Icon {
            static let opacity: Double = 0.18
            static let radius: CGFloat = 4
            static let softOpacity: Double = 0.14
            static let softRadius: CGFloat = 6
            static let softY: CGFloat = 3
            static let y: CGFloat = 2
        }
    }

    enum Stroke {
        static let emphasis: CGFloat = 1.5
        static let hairline: CGFloat = 0.5
    }

    /// 9 档字号阶梯：9 / 10 / 11 / 12 / 13 / 15 / 17 / 20 / 24
    enum TypeSize {
        static let body: CGFloat = 13
        static let callout: CGFloat = 12
        static let caption: CGFloat = 10
        static let caption2: CGFloat = 9
        static let display: CGFloat = 24
        static let headline: CGFloat = 20
        static let label: CGFloat = 11
        static let title: CGFloat = 15
        static let title2: CGFloat = 17
    }
}
