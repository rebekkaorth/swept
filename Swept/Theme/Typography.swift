//
//  Typography.swift
//  Swept
//
//  Type tokens. SF Mono for every size, path, and number (with monospaced digits);
//  SF Pro (system default) for all other text.
//

import SwiftUI

/// Namespace for Swept's type tokens.
enum Typography {

    // MARK: - Monospaced (SF Mono) — numbers, sizes, paths

    /// Headline reclaimable figure: 27pt semibold mono.
    static let reclaimableNumber = Font.system(size: 27, weight: .semibold, design: .monospaced)
    /// Inspector size figure: 26pt semibold mono.
    static let inspectorSize = Font.system(size: 26, weight: .semibold, design: .monospaced)
    /// General mono for file paths / inline sizes.
    static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)

    // MARK: - Titles (SF Pro)

    static let titleXL = Font.system(size: 30, weight: .semibold)   // 30
    static let title = Font.system(size: 22, weight: .semibold)     // 22
    static let title2 = Font.system(size: 18, weight: .semibold)    // 18
    static let title3 = Font.system(size: 17, weight: .semibold)    // 17
    static let headline = Font.system(size: 15, weight: .semibold)  // 15

    // MARK: - Body

    static let body = Font.system(size: 14)
    static let bodySmall = Font.system(size: 13)

    // MARK: - Captions

    static let caption = Font.system(size: 12)
    static let captionSmall = Font.system(size: 11)

    // MARK: - Uppercase section label

    /// 11pt semibold, uppercased, +0.5 tracking (see `.uppercaseLabelStyle()`).
    static let uppercaseLabel = Font.system(size: 11, weight: .semibold)
    static let uppercaseTracking: CGFloat = 0.5
}

extension View {
    /// Applies the standard uppercase section-label styling
    /// (11pt semibold, +0.5 tracking, uppercased).
    func uppercaseLabelStyle(_ color: Color = Theme.textTertiary) -> some View {
        font(Typography.uppercaseLabel)
            .tracking(Typography.uppercaseTracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
