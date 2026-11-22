//
//  SelectionBox.swift
//  Swept
//
//  19pt checkbox for the delete set. Toggling is independent of row selection.
//

import SwiftUI

struct SelectionBox: View {
    let isChecked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isChecked ? Theme.accent : Color.clear)
                .overlay {
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Theme.controlOutline, lineWidth: 1.5)
                    }
                }
                .frame(width: 19, height: 19)
                // A clear fill isn't hit-testable, so without this only the outline took clicks.
                // Pad the target a little too, since 19 pt is small to aim at.
                .padding(4)
                .contentShape(Rectangle())
        }
        .padding(-4) // keep the visual layout unchanged
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack(spacing: 12) {
        SelectionBox(isChecked: false) {}
        SelectionBox(isChecked: true) {}
    }
    .padding()
    .background(Theme.windowBackground)
    .preferredColorScheme(.dark)
}
