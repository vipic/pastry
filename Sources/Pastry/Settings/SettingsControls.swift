import SwiftUI
import AppKit
import Carbon

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Settings {
        static let borderStrongOpacity: Double = 0.50
        static let switchHeight: CGFloat = 26
        static let switchShadowIdleOpacity: Double = 0.16
        static let switchShadowIdleRadius: CGFloat = 2
        static let switchShadowPressedOpacity: Double = 0.12
        static let switchShadowPressedRadius: CGFloat = 1
        static let switchShadowY: CGFloat = 1
        static let switchThumbInset: CGFloat = 3
        static let switchThumbSize: CGFloat = 20
        static let switchWidth: CGFloat = 46
    }
}

enum SettingsButtonKind {
    case primary
    case secondary
    case danger
}

struct SettingsPillButtonStyle: ButtonStyle {
    var kind: SettingsButtonKind = .secondary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: UIConstants.TypeSize.callout, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(minHeight: UIConstants.Control.iconButtonSize)
            .background(buttonBackground(isPressed: configuration.isPressed))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.instant), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary:
            return PastryPalette.warmInk
        case .danger:
            return .white
        case .secondary:
            return PastryPalette.ink
        }
    }

    @ViewBuilder
    private func buttonBackground(isPressed: Bool) -> some View {
        RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
            .fill(fillColor.opacity(isPressed ? UIConstants.Settings.pressedOpacity : 1))
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                    .stroke(borderColor, lineWidth: UIConstants.Stroke.hairline)
            )
    }

    private var fillColor: Color {
        switch kind {
        case .primary:
            return PastryPalette.warmAccent
        case .secondary:
            return Color.white.opacity(UIConstants.Settings.secondaryFillOpacity)
        case .danger:
            return PastryPalette.danger
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return PastryPalette.warmBorder.opacity(Local.Settings.borderStrongOpacity)
        case .secondary:
            return PastryPalette.ink.opacity(UIConstants.Settings.borderOpacity)
        case .danger:
            return PastryPalette.dangerBorder.opacity(Local.Settings.borderStrongOpacity)
        }
    }
}

extension View {
    /// 设置详情区固定为浅色表面；原生 menu Picker 也必须固定浅色外观，
    /// 否则系统深色模式下标题与箭头可能和自定义浅色背景失去对比度。
    func settingsMenuPickerChrome() -> some View {
        labelsHidden()
            .pickerStyle(.menu)
            .foregroundStyle(PastryPalette.ink)
            .tint(PastryPalette.ink)
            .environment(\.colorScheme, .light)
    }
}

struct SettingsSwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var switchAnimation: Animation? {
        reduceMotion ? nil : .spring(response: UIConstants.Motion.slow, dampingFraction: 0.74, blendDuration: 0.08)
    }

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(switchAnimation) {
                configuration.isOn.toggle()
            }
        } label: {
            EmptyView()
        }
        .buttonStyle(SettingsSwitchButtonStyle(isOn: configuration.isOn, animation: switchAnimation))
    }
}

struct SettingsSwitchButtonStyle: ButtonStyle {
    let isOn: Bool
    let animation: Animation?

    func makeBody(configuration: Configuration) -> some View {
        SettingsSwitchBody(
            isOn: isOn,
            isPressed: configuration.isPressed,
            animation: animation
        )
    }
}

struct SettingsSwitchBody: View {
    let isOn: Bool
    let isPressed: Bool
    let animation: Animation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(trackFill)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(trackStroke, lineWidth: UIConstants.Stroke.hairline)
                )

            Circle()
                .fill(Color.white)
                .shadow(
                    color: .black.opacity(isPressed ? Local.Settings.switchShadowPressedOpacity : Local.Settings.switchShadowIdleOpacity),
                    radius: isPressed ? Local.Settings.switchShadowPressedRadius : Local.Settings.switchShadowIdleRadius,
                    x: 0,
                    y: Local.Settings.switchShadowY
                )
                .frame(width: Local.Settings.switchThumbSize, height: Local.Settings.switchThumbSize)
                .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.92 : 1))
                .padding(Local.Settings.switchThumbInset)
        }
        .frame(width: Local.Settings.switchWidth, height: Local.Settings.switchHeight)
        .contentShape(Capsule(style: .continuous))
        .animation(animation, value: isOn)
        .animation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.fast), value: isPressed)
    }

    private var trackFill: Color {
        isOn
            ? PastryPalette.warmAccent
            : PastryPalette.switchOff
    }

    private var trackStroke: Color {
        isOn
            ? PastryPalette.warmBorder.opacity(Local.Settings.borderStrongOpacity)
            : PastryPalette.ink.opacity(UIConstants.Settings.borderOpacity)
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onPreview: (Int?, Int) -> Void
    var onChange: () -> Void
    var onStartRecording: () -> Void
    var onCancelRecording: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ShortcutCaptureField {
        let field = ShortcutCaptureField()
        field.coordinator = context.coordinator
        return field
    }

    func updateNSView(_ nsView: ShortcutCaptureField, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        if isRecording {
            nsView.beginRecordingIfNeeded()
        } else {
            nsView.endRecordingIfNeeded()
        }
    }

    final class Coordinator: NSObject {
        var parent: ShortcutCaptureView

        init(parent: ShortcutCaptureView) {
            self.parent = parent
            super.init()
        }

        func preview(keyCode: Int?, modifiers: Int) {
            parent.onPreview(keyCode, modifiers)
        }

        func startRecording() {
            parent.onStartRecording()
        }

        func cancelRecording() {
            parent.isRecording = false
            parent.onCancelRecording()
        }

        func commit(keyCode: Int, modifiers: Int) {
            parent.keyCode = keyCode
            parent.modifiers = modifiers
            parent.onPreview(keyCode, modifiers)
            parent.onChange()
            parent.isRecording = false
        }
    }
}

final class ShortcutCaptureField: NSControl {
    weak var coordinator: ShortcutCaptureView.Coordinator?
    private var recording = false

    override var acceptsFirstResponder: Bool { true }

    func beginRecordingIfNeeded() {
        guard !recording else { return }
        recording = true
        coordinator?.startRecording()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    func endRecordingIfNeeded() {
        guard recording else { return }
        recording = false
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }

        let code = Int(event.keyCode)
        if code == 53 {
            cancelRecording()
            return
        }

        let nseventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard nseventMods.contains(.command) || nseventMods.contains(.option)
            || nseventMods.contains(.control) || nseventMods.contains(.shift)
        else {
            SoundFeedback.invalidAction()
            return
        }

        let carbonMods = Int(nseventModifiersToCarbon(nseventMods))
        coordinator?.preview(keyCode: code, modifiers: carbonMods)
        recording = false
        coordinator?.commit(keyCode: code, modifiers: carbonMods)
        window?.makeFirstResponder(nil)
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else {
            super.flagsChanged(with: event)
            return
        }

        let nseventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbonMods = Int(nseventModifiersToCarbon(nseventMods))
        coordinator?.preview(keyCode: nil, modifiers: carbonMods)
    }

    override func resignFirstResponder() -> Bool {
        if recording {
            cancelRecording()
        }
        return super.resignFirstResponder()
    }

    private func cancelRecording() {
        recording = false
        coordinator?.cancelRecording()
        window?.makeFirstResponder(nil)
    }
}

struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        configureWhenReady(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configureWhenReady(from: view)
    }

    private func configureWhenReady(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                configureWhenReady(from: view)
                return
            }

            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }
            if window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
            if window.toolbar != nil {
                window.toolbar?.isVisible = false
                window.toolbar = nil
            }
            if window.minSize != minSize {
                window.minSize = minSize
            }
        }
    }
}
