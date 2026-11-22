//
//  EmptyStateView.swift
//  Swept
//
//  Shown when a scan finds almost nothing. Calm and rewarding — not an error.
//

import SwiftUI

struct EmptyStateView: View {
    var lastScanned: Date?
    var onScanAgain: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(Theme.safe)
                .symbolRenderingMode(.hierarchical)

            Text("You're all swept up")
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)

            Text("Nothing worth cleaning right now.")
                .font(Typography.body)
                .foregroundStyle(Theme.textSecondary)

            if let lastScanned {
                Text("Last scanned \(lastScanned.formatted(date: .abbreviated, time: .shortened))")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Button {
                onScanAgain()
            } label: {
                Label("Scan again", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: .command) // ⌘R re-scan
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
    }
}

#Preview {
    EmptyStateView(lastScanned: Date(), onScanAgain: {})
        .frame(width: 1000, height: 700)
        .preferredColorScheme(.dark)
}
