//
//  SummaryCard.swift
//  Swept
//
//  Pinned sidebar card: total reclaimable, a fill bar vs. System Data, caption.
//

import SwiftUI

struct SummaryCard: View {
    let reclaimable: Int64
    let totalSystemData: Int64

    private var fraction: Double {
        totalSystemData > 0 ? Double(reclaimable) / Double(totalSystemData) : 0
    }

    var body: some View {
        let parts = ByteFormat.parts(reclaimable)

        VStack(alignment: .leading, spacing: 10) {
            Text("Reclaimable")
                .uppercaseLabelStyle(Theme.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parts.value)
                    .font(Typography.reclaimableNumber)
                    .tracking(-1)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(parts.unit)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textSecondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.trackFill)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Theme.accent, Color(hex: 0x5EB4FF)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * max(0, min(fraction, 1)))
                }
            }
            .frame(height: 5)
            .animation(Theme.Motion.standard, value: fraction)

            Text("of \(totalSystemData.fileSize) used storage")
                .font(Typography.captionSmall)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(LinearGradient(
                    colors: [Theme.accent.opacity(0.14), Theme.accent.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1)
        )
    }
}

#Preview {
    let model = ScanModel.mock
    return SummaryCard(reclaimable: model.reclaimable, totalSystemData: model.totalSystemData)
        .frame(width: 222)
        .padding()
        .background(Theme.windowBackground)
        .preferredColorScheme(.dark)
}
