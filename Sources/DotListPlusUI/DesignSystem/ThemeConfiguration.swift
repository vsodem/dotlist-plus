import Foundation

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
