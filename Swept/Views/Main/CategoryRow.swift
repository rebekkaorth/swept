//
//  CategoryRow.swift
//  Swept
//
//  A single sidebar category: icon tile, name, and rolled-up size.
//

import SwiftUI

struct CategoryRow: View {
    let category: Category

    /// `.increased` while the row sits on the sidebar's accent selection highlight.
    @Environment(\.backgroundProminence) private var prominence
    private var isHighlighted: Bool { prominence == .increased }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: Theme.Radius.iconTileSmall, style: .continuous)
                .fill(isHighlighted ? Color.white.opacity(0.2) : Theme.iconTileBackground)
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: category.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isHighlighted ? Color.white : Theme.textPrimary)
                }

            Text(category.title)
                .font(Typography.bodySmall)
                .foregroundStyle(isHighlighted ? Color.white : Theme.textPrimary)
                .lineLimit(1)
                .truncationTooltip(category.title)

            Spacer(minLength: 8)

            Text(category.total.fileSize)
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isHighlighted ? Color.white : Theme.textSecondary)
        }
    }
}

#Preview {
    List {
        ForEach(ScanModel.mock.categories) { CategoryRow(category: $0) }
    }
    .listStyle(.sidebar)
    .frame(width: 246, height: 320)
    .preferredColorScheme(.dark)
}
