//
//  Safety.swift
//  Swept
//
//  How risky a given item is to remove.
//

import SwiftUI

enum Safety: Hashable, CaseIterable {
    case safe
    case caution
    case careful

    /// Semantic color from the design tokens.
    var color: Color {
        switch self {
        case .safe: Theme.safe
        case .caution: Theme.caution
        case .careful: Theme.careful
        }
    }

    /// Short human-facing label (e.g. shown in a chip).
    var label: String {
        switch self {
        case .safe: "Safe"
        case .caution: "Caution"
        case .careful: "Careful"
        }
    }
}
