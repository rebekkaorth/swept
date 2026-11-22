//
//  SafetyChip.swift
//  Swept
//
//  Reusable capsule showing an item's safety level.
//

import SwiftUI

struct SafetyChip: View {
    let safety: Safety

    var body: some View {
        Text(safety.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(safety.color)
            .lineLimit(1)
            .fixedSize() // a chip must never wrap or truncate
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Theme.chipBackground(safety.color), in: Capsule())
    }
}

#Preview {
    HStack(spacing: 8) {
        ForEach(Safety.allCases, id: \.self) { SafetyChip(safety: $0) }
    }
    .padding()
    .background(Theme.windowBackground)
    .preferredColorScheme(.dark)
}
