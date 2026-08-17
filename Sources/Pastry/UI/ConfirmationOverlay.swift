import SwiftUI

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Confirmation {
        static let buttonHeight: CGFloat = 30
        static let buttonHorizontalPadding: CGFloat = 13
        static let cardWidth: CGFloat = 360
        static let contentPadding: CGFloat = 18
        static let cornerRadius: CGFloat = UIConstants.Radius.panel
        static let dangerGlowOpacity: Double = 0.34
        static let destructivePressedOpacity: Double = 0.82
        static let scrimOpacity: Double = 0.22
    }
}

struct ConfirmationOverlay: View {
    enum ButtonKind: Hashable {
        case secondary
        case destructive
    }

    let title: String
    let message: String
    let cancelTitle: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @FocusState private var focusedButton: ButtonKind?

    var body: some View {
        ZStack {
            Color.black.opacity(Local.Confirmation.scrimOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: UIConstants.TypeSize.title2, weight: .semibold))
                    .foregroundColor(.white.opacity(UIConstants.OnDark.textPrimary))

                Text(message)
                    .font(.system(size: UIConstants.TypeSize.body))
                    .foregroundColor(.white.opacity(UIConstants.OnDark.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: UIConstants.Card.footerBottomPadding) {
                    Spacer()

                    Button(cancelTitle, action: onCancel)
                        .buttonStyle(ConfirmationButtonStyle(kind: .secondary))
                        .focusable()
                        .focused($focusedButton, equals: .secondary)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.deleteCancelButton)
                        .onKeyPress(.return) {
                            onCancel()
                            return .handled
                        }

                    Button(confirmTitle, action: onConfirm)
                        .buttonStyle(ConfirmationButtonStyle(kind: .destructive))
                        .focusable()
                        .focused($focusedButton, equals: .destructive)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.deleteConfirmButton)
                        .onKeyPress(.return) {
                            onConfirm()
                            return .handled
                        }
                }
            }
            .padding(Local.Confirmation.contentPadding)
            .frame(width: Local.Confirmation.cardWidth)
            .background(confirmationCardChrome)
            .clipShape(RoundedRectangle(cornerRadius: Local.Confirmation.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Local.Confirmation.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(UIConstants.OnDark.stroke), lineWidth: UIConstants.Stroke.hairline)
            )
            .shadow(
                color: .black.opacity(UIConstants.Shadow.Floating.primaryOpacity),
                radius: UIConstants.Shadow.Floating.primaryRadius,
                x: 0,
                y: UIConstants.Shadow.Floating.primaryY
            )
            .shadow(
                color: .black.opacity(UIConstants.Shadow.Floating.secondaryOpacity),
                radius: UIConstants.Shadow.Floating.secondaryRadius,
                x: 0,
                y: UIConstants.Shadow.Floating.secondaryY
            )
        }
        .onAppear {
            focusedButton = .secondary
        }
    }

    /// 与托盘同系：hud 磨砂 + sidebar 着色。
    private var confirmationCardChrome: some View {
        ZStack {
            GlassBackground(cornerRadius: Local.Confirmation.cornerRadius)
            PastryPalette.sidebar.opacity(UIConstants.Overlay.overlaySurfaceTintOpacity)
        }
    }
}

private struct ConfirmationButtonStyle: ButtonStyle {
    let kind: ConfirmationOverlay.ButtonKind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, Local.Confirmation.buttonHorizontalPadding)
            .frame(height: Local.Confirmation.buttonHeight)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                    .stroke(borderColor, lineWidth: UIConstants.Stroke.hairline)
            )
    }

    private var foregroundColor: Color {
        switch kind {
        case .secondary:
            return .white.opacity(UIConstants.OnDark.textSecondary)
        case .destructive:
            return .white
        }
    }

    private var borderColor: Color {
        switch kind {
        case .secondary:
            return .white.opacity(UIConstants.OnDark.stroke)
        case .destructive:
            return PastryPalette.dangerGlow.opacity(Local.Confirmation.dangerGlowOpacity)
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .secondary:
            return Color.white.opacity(isPressed ? UIConstants.OnDark.fillHover : UIConstants.OnDark.fillSubtle)
        case .destructive:
            return PastryPalette.dangerStrong.opacity(isPressed ? Local.Confirmation.destructivePressedOpacity : 1.0)
        }
    }
}
