import SwiftUI

extension AppTheme {
    /// Apple typography, semantic colors, native controls and system appearance.
    public static let `default` = AppTheme(name: "Default", colors: ThemeColors())

    /// TRON: Legacy — dark glass, cyan light and restrained amber highlights.
    public static let tron = AppTheme(
        name: "TRON",
        colors: ThemeColors(
            accent: Color(red: 0.32, green: 0.90, blue: 1.00),
            highlight: Color(red: 1.00, green: 0.73, blue: 0.31),
            text: Color(red: 0.88, green: 0.96, blue: 0.98),
            secondaryText: Color(red: 0.61, green: 0.73, blue: 0.78),
            danger: Color(red: 1.00, green: 0.43, blue: 0.39),
            notice: Color(red: 1.00, green: 0.73, blue: 0.31),
            canvas: Color(red: 0.025, green: 0.045, blue: 0.065),
            surface: AnyShapeStyle(Color(red: 0.045, green: 0.085, blue: 0.11)),
            edge: AnyShapeStyle(Color(red: 0.32, green: 0.90, blue: 1.00).opacity(0.48)),
            onAccent: Color(red: 0.015, green: 0.04, blue: 0.055)
        ),
        typography: ThemeTypography(design: .monospaced),
        layout: ThemeLayout(cardRadius: 12, buttonRadius: 8),
        effects: ThemeEffects(illuminated: true),
        motion: ThemeMotion(duration: 0.22, pressScale: 0.98),
        preferredColorScheme: .dark
    )
}

public enum ThemeConfiguration {
    /// Change this one value to ship a different theme.
    public static let defaultTheme: AppTheme = .default

    /// In Xcode: Scheme → Run → Arguments → Environment Variables.
    /// DOTLIST_THEME=tron previews TRON without editing the shipped default.
    public static var active: AppTheme { resolve(environment: ProcessInfo.processInfo.environment) }

    static func resolve(environment: [String: String], fallback: AppTheme = defaultTheme) -> AppTheme {
        switch environment["DOTLIST_THEME"] {
        case "default": return .default
        case "tron": return .tron
        default: return fallback
        }
    }
}
