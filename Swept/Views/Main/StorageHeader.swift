//
//  StorageHeader.swift
//  Swept
//
//  Compact disk-usage header for the sidebar: total used vs free, plus the opaque
//  "System Data" figure reframed — Swept shows what's actually inside it.
//

import SwiftUI

struct StorageHeader: View {
    /// The System Data figure Swept tracks (approximated as volume-used; see VolumeInfo).
    let systemDataBytes: Int64

    private let usage = VolumeInfo.usage()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let usage {
                diskBar(usage)
                HStack {
                    Text("\(usage.used.fileSize) used")
                    Spacer()
                    Text("\(usage.free.fileSize) free")
                }
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)

                Divider().overlay(Theme.hairline)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("System Data")
                    .uppercaseLabelStyle(Theme.textSecondary)
                Spacer()
                Text(systemDataBytes.fileSize)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Apple shows you this number. Swept shows you what's inside it.")
                .font(Typography.captionSmall)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .cardBackground()
    }

    private func diskBar(_ usage: VolumeInfo.Usage) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.trackFill)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: geometry.size.width * min(max(usage.usedFraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

#Preview {
    StorageHeader(systemDataBytes: 128_000_000_000)
        .frame(width: 246)
        .padding()
        .background(Theme.windowBackground)
        .preferredColorScheme(.dark)
}
