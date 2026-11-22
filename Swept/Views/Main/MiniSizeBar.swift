//
//  MiniSizeBar.swift
//  Swept
//
//  Small proportional bar showing an item's share of its category, tinted by safety.
//

import SwiftUI

struct MiniSizeBar: View {
    /// 0...1 share of the category total.
    let fraction: Double
    let tint: Color

    private let width: CGFloat = 84
    private let minFraction: Double = 0.04

    var body: some View {
        let clamped = max(minFraction, min(fraction, 1))
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.trackFill)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tint)
                .frame(width: width * clamped)
        }
        .frame(width: width, height: 6)
    }
}

#Preview {
    VStack(spacing: 10) {
        MiniSizeBar(fraction: 0.9, tint: Theme.safe)
        MiniSizeBar(fraction: 0.45, tint: Theme.caution)
        MiniSizeBar(fraction: 0.02, tint: Theme.careful)
    }
    .padding()
    .background(Theme.windowBackground)
    .preferredColorScheme(.dark)
}
