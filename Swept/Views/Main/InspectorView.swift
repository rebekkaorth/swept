//
//  InspectorView.swift
//  Swept
//
//  Right column: full detail for the selected item. No delete button here.
//

import SwiftUI
import AppKit

struct InspectorView: View {
    let model: ScanModel

    var body: some View {
        Group {
            if let item = model.selectedItemValue {
                detail(for: item)
            } else {
                Text("Select an item")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.inspectorBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.hairline).frame(width: 1)
        }
    }

    private func detail(for item: CleanItem) -> some View {
        let kind = model.category(containing: item.id)?.kind

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: Theme.Radius.iconTileLarge, style: .continuous)
                    .fill(Theme.iconTileBackground)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: kind?.symbol ?? "doc")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(item.bytes.fileSize)
                        .font(Typography.inspectorSize)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(item.safety.color)
                        .frame(width: 9, height: 9)
                    Text(item.isRevealOnly ? "Protected — Swept never removes this" : advice(for: item.safety))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(item.safety.color)
                }

                Text(item.detail)
                    .font(.system(size: 13))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                metadata(for: item)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Text("Reveal in Finder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 22, leading: 22, bottom: 20, trailing: 22))
        }
    }

    private func metadata(for item: CleanItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                metaLabel("Location")
                Text(item.url.path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    metaLabel("Last Modified")
                    Text(item.lastModified.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    metaLabel("Owner")
                    Text(item.owner ?? "—")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private func metaLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(Typography.uppercaseTracking)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textTertiary)
    }

    private func advice(for safety: Safety) -> String {
        switch safety {
        case .safe: "Safe to delete"
        case .caution: "Review before deleting"
        case .careful: "Delete with care"
        }
    }
}

#Preview {
    InspectorView(model: .mock)
        .frame(width: 302, height: 720)
        .preferredColorScheme(.dark)
}
