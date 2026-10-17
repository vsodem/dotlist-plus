import SwiftUI

extension View {
    public func appTheme(_ theme: AppTheme) -> some View {
        environment(\.appTheme, theme)
            .tint(theme.colors.accent)
            .font(theme.typography.body)
            .preferredColorScheme(theme.preferredColorScheme)
    }

    func themeScreen() -> some View { modifier(ThemeScreen()) }
    func themeCard() -> some View { modifier(ThemeCard()) }
    func themeGlow(active: Bool = true) -> some View {
        modifier(ThemeGlow(active: active))
    }
    func themeButton(prominent: Bool = false) -> some View {
        modifier(ThemeButton(prominent: prominent))
    }
    func themeChange<Value: Equatable>(_ value: Value) -> some View {
        modifier(ThemeChange(value: value))
    }
}

private struct ThemeScreen: ViewModifier {
    @Environment(\.appTheme) private var theme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(theme.colors.canvas == nil ? .automatic : .hidden)
            .background {
                if let canvas = theme.colors.canvas { canvas.ignoresSafeArea() }
            }
    }
}

private struct ThemeCard: ViewModifier {
    @Environment(\.appTheme) private var theme
    func body(content: Content) -> some View {
        content
            .padding(theme.layout.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: theme.layout.cardRadius)
                    .fill(theme.colors.surface)
                    .overlay {
                        if theme.effects.illuminated {
                            ThemeGrid().clipShape(RoundedRectangle(cornerRadius: theme.layout.cardRadius))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: theme.layout.cardRadius)
                    .stroke(theme.colors.edge, lineWidth: theme.effects.lineWidth)
                    .themeGlow()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

private struct ThemeGrid: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for x in stride(from: CGFloat.zero, through: size.width, by: theme.effects.gridSpacing) {
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat.zero, through: size.height, by: theme.effects.gridSpacing) {
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(theme.colors.accent.opacity(theme.effects.gridOpacity)), lineWidth: theme.effects.lineWidth)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ThemeGlow: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast
    let active: Bool
    func body(content: Content) -> some View {
        content.shadow(
            color: theme.effects.illuminated && active && contrast != .increased
                ? theme.colors.accent.opacity(theme.effects.glowOpacity) : .clear,
            radius: theme.effects.glowRadius
        )
    }
}

private struct ThemeButton: ViewModifier {
    @Environment(\.appTheme) private var theme
    let prominent: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if theme.effects.illuminated {
            content.buttonStyle(IlluminatedButtonStyle(prominent: prominent))
        } else if prominent {
            content.buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            content.buttonStyle(.bordered).controlSize(.large)
        }
    }
}

private struct IlluminatedButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let color = configuration.role == .destructive ? theme.colors.danger : theme.colors.accent
        configuration.label
            .font(theme.typography.headline)
            .padding(.horizontal, theme.layout.groupGap)
            .padding(.vertical, theme.layout.rowGap)
            .frame(minHeight: theme.layout.hitTarget)
            .foregroundStyle(prominent ? theme.colors.onAccent : color)
            .background(prominent ? color : color.opacity(theme.colors.bannerOpacity),
                        in: RoundedRectangle(cornerRadius: theme.layout.buttonRadius))
            .overlay {
                RoundedRectangle(cornerRadius: theme.layout.buttonRadius)
                    .stroke(color, lineWidth: theme.effects.lineWidth)
            }
            .themeGlow(active: enabled && prominent)
            .opacity(enabled ? 1 : theme.effects.disabledOpacity)
            .scaleEffect(configuration.isPressed ? theme.motion.pressedScale(reduceMotion: reduceMotion) : 1)
            .animation(theme.motion.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

private struct ThemeChange<Value: Equatable>: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value
    func body(content: Content) -> some View {
        content
            .contentTransition(.opacity)
            .animation(theme.motion.animation(reduceMotion: reduceMotion), value: value)
    }
}
