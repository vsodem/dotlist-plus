# Editing themes

All app-owned visual values live in `Sources/DotListPlusUI/DesignSystem/`. Edit these Swift files by hand or point Claude Code at this guide. No dependency installation or project regeneration is needed when adding a file inside that package folder.

## Choose a theme

The shipped theme is `ThemeConfiguration.defaultTheme` in `DesignSystem/ThemeConfiguration.swift`:

```swift
public static var defaultTheme: AppTheme { .default } // or .tron
```

For a temporary preview, open **Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables** in Xcode. Add `DOTLIST_THEME` with value `tron` or `default`, then run on iPhone Simulator or My Mac. Remove the variable to return to the developer default. An unknown value also uses that default. The override takes priority over the source default.

You can also pass a theme directly to `RootView(theme: .tron)` in a preview or host app. The existing `RootView()` uses the configuration above. Appearance is not saved in user preferences, lists, backups or iCloud. There is no user-facing theme picker.

Swift Package Manager compiles each theme file into `DotListPlusUI` automatically. `ThemeConfiguration` selects an `AppTheme`; `RootView` injects it into the SwiftUI environment for screens and sheets. Adding a theme does not require changes to individual screens.

## Where to edit

| File | Owns |
|---|---|
| `DesignSystem/Themes/DefaultTheme.swift` | Default theme definition, using native Apple values |
| `DesignSystem/Themes/TRONTheme.swift` | TRON palette, typography, shapes, effects and motion |
| `DesignSystem/ThemeConfiguration.swift` | Shipped default and launch-override selection |
| `DesignSystem/AppTheme.swift` | Shared value types; semantic colors, typography, glow/grid settings and Reduce Motion policy |
| `DesignSystem/ThemeLayout.swift` | Spacing, card/button radii, widths, sheet/window sizes and SF Symbols |
| `DesignSystem/ThemeStyles.swift` | Native/custom primary buttons, card borders, grid, glow, screen backgrounds and content transitions |

Screens read `@Environment(\.appTheme)` and use semantic values such as `theme.colors.secondaryText`, `theme.typography.hero` and `theme.layout.cardInset`. Layout composition, control roles, labels, navigation and work commands remain in screen files. Zero spacing, infinite flexible widths, alignment and native form/row styles are structural choices, not palette values.

Native tabs, toolbars, menus, toggles, fields, forms, alerts and file pickers keep Apple behavior. Their tint and appearance inherit the theme where the operating system supports it. System-owned dialogs and controls are not redrawn to imitate TRON. Default uses adaptive semantic colors and native light/dark appearance. TRON requests dark appearance, with near-black canvas, cyan accents and amber next-action highlights.

The app's `AccentColor` asset intentionally has no custom color, allowing Default to use Apple's system accent. Define custom theme colors in that theme’s file under `DesignSystem/Themes/`, rather than putting a second palette in the asset catalog. The launcher icon remains a platform asset, shared across themes.

Apply `colors.text` directly to custom content such as Focus titles and work-row labels. Leave native form labels, footers, controls and navigation text on their system semantic colors. Do not put `foregroundStyle` above buttons or an entire screen: it overrides native tint and destructive-role colors.

Theme definitions and defaults are read-only computed properties. Each access constructs a fresh `AppTheme`, avoiding shared non-`Sendable` values under complete concurrency checking. Keep this pattern when adding themes; do not use stored static theme constants or unsafe concurrency suppressions.

## Add a theme

1. Create one file per theme in `DesignSystem/Themes/`, such as `OceanTheme.swift`. Copy an existing theme’s `extension AppTheme`, then change the static property name, display name and visual values. Shared types supply defaults for values you do not override.
2. In `ThemeConfiguration.swift`, set `defaultTheme` to the new definition. Optionally add a case to `resolve(environment:fallback:)` for an Xcode launch override.
3. Keep all style branches inside `DesignSystem`. Use capabilities such as `effects.illuminated`; do not add theme-name checks to screens.
4. If you need a new visual role, add a named value to the shared types and use it in the relevant screens. Keep data and action code unchanged.
5. Run the checks below before publishing.

Font roles use SwiftUI text styles, so Dynamic Type remains available. Custom action buttons keep at least a 44-point target. TRON uses one short ease-out transition for presses and changes in the dotted selection; there are no looping animations or timers. Reduce Motion disables custom transitions and scaling. Increased Contrast removes decorative glow. Do not add glow to body text or use color alone to indicate action state.

## Verify a change

Run `swift test` (including `ThemeTests`), the contract checks and both Apple builds listed in the repository README. Then launch each theme and check:

- Focus: empty, review, execution and completed states; Yes/No, Done, partial work and Choose again.
- All work: available, dotted, blocked and completed actions; long titles; outcome rows.
- Every sheet: work editor, nested required-action editor, conversion, urgency, projects and project editor.
- Settings, help and full specification; error/notice banners and disabled/destructive controls.
- Default in light and dark mode; TRON remains dark. Check text and field contrast.
- Reduce Motion and Increased Contrast; large text, narrow iPhone width, Mac resizing, keyboard shortcuts and VoiceOver labels.

Theme tests cover launch selection/fallback and motion suppression. They do not replace checking the actual rendered screens.
