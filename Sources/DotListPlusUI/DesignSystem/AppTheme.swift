import SwiftUI

/// Visual values only. Themes never read or change list state.
public struct AppTheme {
    public let name: String
    var colors: ThemeColors
    var typography = ThemeTypography()
    var layout = ThemeLayout()
    var icons = ThemeIcons()
    var effects = ThemeEffects()
    var motion = ThemeMotion()
    var preferredColorScheme: ColorScheme?
}

struct ThemeColors {
    var accent: Color = .accentColor
    var highlight: Color = .accentColor
    var text: Color = .primary
    var secondaryText: Color = .secondary
    var danger: Color = .red
    var notice: Color = .orange
    // Nil keeps the native List/Form/sidebar background.
    var canvas: Color?
    var surface = AnyShapeStyle(.background)
    var edge = AnyShapeStyle(.quaternary)
    var onAccent: Color = .white
    var bannerOpacity: Double = 0.12
}

struct ThemeTypography {
    var design: Font.Design = .default
    var body: Font { .system(.body, design: design) }
    var hero: Font { .system(.largeTitle, design: design, weight: .bold) }
    var title: Font { .system(.title, design: design, weight: .bold) }
    var title2: Font { .system(.title2, design: design, weight: .bold) }
    var title3: Font { .system(.title3, design: design) }
    var headline: Font { .system(.headline, design: design) }
    var subheadline: Font { .system(.subheadline, design: design) }
    var callout: Font { .system(.callout, design: design) }
    var caption: Font { .system(.caption, design: design) }
    var eyebrow: Font { .system(.caption, design: design, weight: .semibold) }
    var footnote: Font { .system(.footnote, design: design) }
}

struct ThemeMotion {
    var duration: Double = 0
    var pressScale: CGFloat = 1

    func animation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion, duration > 0 else { return nil }
        return .easeOut(duration: duration)
    }

    func pressedScale(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : pressScale
    }
}

struct ThemeEffects {
    var illuminated = false
    var glowRadius: CGFloat = 8
    var glowOpacity: Double = 0.3
    var gridSpacing: CGFloat = 48
    var gridOpacity: Double = 0.055
    var lineWidth: CGFloat = 1
    var disabledOpacity: Double = 0.45
}

private struct AppThemeKey: EnvironmentKey {
    static var defaultValue: AppTheme { .default }
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
