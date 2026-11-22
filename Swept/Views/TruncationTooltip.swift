//
//  TruncationTooltip.swift
//  Swept
//
//  Shows a `.help` tooltip with the full text ONLY when a label is actually truncated.
//  Apply after setting the font and `.lineLimit(1)`:
//      Text(name).font(...).lineLimit(1).truncationTooltip(name)
//  The hidden measuring copy is the label itself (same font, weight and tracking), so its
//  width always matches — `Text.font(_:)` doesn't reach the environment, so a fresh `Text`
//  would measure in the default font and miss slightly-truncated labels.
//

import SwiftUI

private struct TruncationTooltip: ViewModifier {
    let text: String
    @State private var isTruncated = false

    func body(content: Content) -> some View {
        content
            .background(alignment: .leading) {
                GeometryReader { available in
                    content
                        .fixedSize(horizontal: true, vertical: false) // full width (may overflow; background doesn't affect layout)
                        .hidden()
                        .background {
                            GeometryReader { full in
                                Color.clear
                                    .onAppear {
                                        update(full: full.size.width, available: available.size.width)
                                    }
                                    .onChange(of: full.size.width) { _, newFull in
                                        update(full: newFull, available: available.size.width)
                                    }
                                    .onChange(of: available.size.width) { _, newAvailable in
                                        update(full: full.size.width, available: newAvailable)
                                    }
                            }
                        }
                }
            }
            .help(isTruncated ? text : "")
    }

    private func update(full: CGFloat, available: CGFloat) {
        let truncated = full - available > 0.5
        if truncated != isTruncated { isTruncated = truncated }
    }
}

extension View {
    /// Adds a tooltip with the full `text`, shown only while the label is truncated.
    func truncationTooltip(_ text: String) -> some View {
        modifier(TruncationTooltip(text: text))
    }
}
