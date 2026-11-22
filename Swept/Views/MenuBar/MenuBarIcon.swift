//
//  MenuBarIcon.swift
//  Swept
//
//  Three-state menu-bar glyph. Always monochrome (renders as a template in the menu bar):
//  no color, no red, no badge count.
//

import SwiftUI

enum MenuBarIconState {
    case idle        // plain glyph
    case scanning    // animated (variable color) — "something is happening now"
    case attention   // filled variant — reclaimable is over the threshold
}

struct MenuBarIcon: View {
    let state: MenuBarIconState

    var body: some View {
        Image(systemName: state == .attention ? Theme.brandSymbolProminent : Theme.brandSymbol)
            .symbolEffect(.variableColor.iterative, isActive: state == .scanning)
    }
}
