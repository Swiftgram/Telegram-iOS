import SwiftUI

/// Immutable semantic palette. Independent of Telegram and usable in previews or standalone hosts.
public struct SGSwiftUITheme: Equatable {
    public let accentColor: Color
    /// Foreground for content drawn on an accent-colored fill.
    public let accentForegroundColor: Color
    public let overallDarkAppearance: Bool
    public let primaryTextColor: Color
    public let secondaryTextColor: Color
    public let backgroundColor: Color
    public let secondaryBackgroundColor: Color
    public let separatorColor: Color
    public let destructiveColor: Color

    public init(accentColor: Color, accentForegroundColor: Color, overallDarkAppearance: Bool, primaryTextColor: Color, secondaryTextColor: Color, backgroundColor: Color, secondaryBackgroundColor: Color, separatorColor: Color, destructiveColor: Color) {
        self.accentColor = accentColor
        self.accentForegroundColor = accentForegroundColor
        self.overallDarkAppearance = overallDarkAppearance
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.backgroundColor = backgroundColor
        self.secondaryBackgroundColor = secondaryBackgroundColor
        self.separatorColor = separatorColor
        self.destructiveColor = destructiveColor
    }

    // Palette constants from TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift:
    // defaultDayAccentColor and makeDefaultDayPresentationTheme's Classic navigation/list/check colors.
    public static let light = SGSwiftUITheme(
        accentColor: color(rgb: 0x0088FF),
        accentForegroundColor: .white,
        overallDarkAppearance: false,
        primaryTextColor: .black,
        secondaryTextColor: color(rgb: 0x8E8E93),
        backgroundColor: color(rgb: 0xEFEFF4),
        secondaryBackgroundColor: .white,
        separatorColor: color(rgb: 0xC8C7CC),
        destructiveColor: color(rgb: 0xFF3B30)
    )

    // Palette constants from TelegramPresentationData/Sources/DefaultDarkPresentationTheme.swift:
    // makeDefaultDarkPresentationTheme (Night), not the blue-accent defaultDarkColorPresentationTheme.
    public static let dark = SGSwiftUITheme(
        accentColor: .white,
        accentForegroundColor: .black,
        overallDarkAppearance: true,
        primaryTextColor: .white,
        secondaryTextColor: color(rgb: 0x98989E),
        backgroundColor: .black,
        secondaryBackgroundColor: color(rgb: 0x1C1C1D),
        separatorColor: color(rgb: 0x545458, opacity: 0.55),
        destructiveColor: color(rgb: 0xEB5545)
    )

    private static func color(rgb: UInt32, opacity: Double = 1.0) -> Color {
        return Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255.0, green: Double((rgb >> 8) & 0xFF) / 255.0, blue: Double(rgb & 0xFF) / 255.0, opacity: opacity)
    }
}

private struct SGSwiftUIThemeKey: EnvironmentKey {
    static let defaultValue: SGSwiftUITheme? = nil
}

public extension EnvironmentValues {
    /// Explicit host palette, or a standalone palette matching the native color scheme.
    var sgTheme: SGSwiftUITheme {
        get { self[SGSwiftUIThemeKey.self] ?? (self.colorScheme == .dark ? .dark : .light) }
        set { self[SGSwiftUIThemeKey.self] = newValue }
    }
}

public extension View {
    /// Supplies custom colors and the native control tint/appearance without replacing view identity.
    func sgTheme(_ theme: SGSwiftUITheme) -> some View {
        self.environment(\.sgTheme, theme)
            .environment(\.colorScheme, theme.overallDarkAppearance ? .dark : .light)
            .accentColor(theme.accentColor)
            .tint(theme.accentColor)
    }
}
