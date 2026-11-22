//
//  Theme.swift
//  Swept
//
//  Central design tokens (colors, radii, motion) and small view helpers.
//  Dark-mode first, but every token adapts to light appearance: text uses
//  semantic label colors, surfaces use `Color.primary`-based overlays (black on
//  light, white on dark), and fixed backgrounds use explicit light/dark pairs.
//

import SwiftUI
import AppKit

extension Color {
    /// Creates a color from a 24-bit RGB hex value, e.g. `Color(hex: 0x0A84FF)`.
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// An appearance-adaptive color built from a light and a dark hex value.
    init(light: UInt32, dark: UInt32) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }
}

/// Namespace for Swept's design tokens.
enum Theme {

    // MARK: - Brand

    /// Mirrors the Assets `AccentColor` (#0A84FF).
    static let accent = Color(hex: 0x0A84FF)

    /// The app's brand glyph (matches the scanning motif); `.inverse` is the filled/attention variant.
    static let brandSymbol = "wand.and.sparkles"
    static let brandSymbolProminent = "wand.and.sparkles.inverse"

    // MARK: - Safety colors (vivid in both appearances)

    static let safe = Color(hex: 0x30D158)
    static let caution = Color(hex: 0xFF9F0A)
    static let careful = Color(hex: 0xFF453A)

    /// Destructive actions share the "careful" red.
    static let destructive = careful

    // MARK: - Backgrounds

    /// Opaque window fill. Dark = the designed #1C1C1E; light = a soft off-white.
    static let windowBackground = Color(light: 0xF4F4F6, dark: 0x1C1C1E)
    /// Subtle tint for the inspector column (adapts: white-ish on dark, black-ish on light).
    static let inspectorBackground = Color.primary.opacity(0.02)

    // MARK: - Surfaces & states (all adapt via .primary / semantic colors)

    static let hairline = Color(nsColor: .separatorColor)
    static let hairlineStrong = Color.primary.opacity(0.14)

    /// Row hover highlight.
    static let hover = Color.primary.opacity(0.06)

    /// Selected list row (accent-tinted, adapts naturally).
    static let selectedRow = accent.opacity(0.12)

    /// Fill behind icon tiles.
    static let iconTileBackground = Color.primary.opacity(0.08)
    /// Subtle fill used by `.cardBackground()`.
    static let cardFill = Color.primary.opacity(0.04)
    /// Track behind progress / size bars.
    static let trackFill = Color.primary.opacity(0.10)
    /// Outline for unchecked controls (e.g. the selection box).
    static let controlOutline = Color.primary.opacity(0.28)
    /// Faint bar/footer background.
    static let barBackground = Color.primary.opacity(0.03)

    // MARK: - Text

    static let textPrimary = Color.primary
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    // MARK: - Chips & pills

    /// Chip background = its safety color at 15%.
    static func chipBackground(_ color: Color) -> Color { color.opacity(0.15) }

    /// Leftover pill background = amber (caution) at 16%.
    static let leftoverPill = caution.opacity(0.16)

    // MARK: - Radii

    enum Radius {
        static let card: CGFloat = 12
        static let sheet: CGFloat = 14
        static let button: CGFloat = 8
        static let buttonLarge: CGFloat = 9
        static let iconTileSmall: CGFloat = 6
        static let iconTile: CGFloat = 8
        static let iconTileLarge: CGFloat = 11
    }

    // MARK: - Motion (standardized, calm — no bounce)

    enum Motion {
        /// Default for state changes (totals, deletes, selection).
        static let standard = Animation.easeInOut(duration: 0.22)
        /// Fast hover/press feedback.
        static let quick = Animation.easeOut(duration: 0.14)
        /// Route cross-fades.
        static let cross = Animation.easeInOut(duration: 0.28)
    }
}

extension View {
    /// Standard card/sheet surface: subtle fill, continuous rounded corners, hairline border.
    func cardBackground(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    /// Adds a 1pt hairline divider along the top edge (used above footers/toolbars).
    func hairlineTop(_ color: Color = Theme.hairline) -> some View {
        overlay(alignment: .top) {
            Rectangle()
                .fill(color)
                .frame(height: 1)
        }
    }
}
