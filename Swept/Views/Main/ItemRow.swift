//
//  ItemRow.swift
//  Swept
//
//  One reclaimable item. Row tap selects (drives inspector); checkbox and trash
//  are independent buttons that do not change selection. Reveal-only items get
//  neither — only a lock and a "PROTECTED" pill; the inspector can still reveal them.
//

import SwiftUI

struct ItemRow: View {
    let item: CleanItem
    let categoryTotal: Int64
    let kind: CategoryKind
    let model: ScanModel

    @State private var isHovered = false
    @State private var isTrashHovered = false
    @State private var showDeleteAlert = false
    @State private var showCriticalConfirm = false

    private var isSelected: Bool { model.selectedItem == item.id }
    private var isChecked: Bool { model.checked.contains(item.id) }

    var body: some View {
        HStack(spacing: 13) {
            if item.isDeleting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 19, height: 19)
                    .accessibilityLabel("Deleting \(item.name)")
            } else if item.isRevealOnly {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 19, height: 19)
                    .accessibilityLabel("\(item.name) is protected and can't be selected")
            } else {
                SelectionBox(isChecked: isChecked) { model.toggleChecked(item.id) }
                    .accessibilityLabel(isChecked ? "Deselect \(item.name)" : "Select \(item.name)")
                    .accessibilityAddTraits(isChecked ? .isSelected : [])
            }

            iconTile

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationTooltip(item.name)
                    if let badge = item.badge { badgePill(badge) }
                    if item.isRevealOnly { pill("PROTECTED", Theme.careful) }
                }
                Text(item.explanation)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationTooltip(item.explanation)
            }
            .layoutPriority(1) // the file/item name keeps its space; trailing captions yield first

            Spacer(minLength: 8)

            // Fixed columns from here on, so chips line up row to row. The chip column is as wide
            // as the widest safety label, with each chip leading-aligned inside it.
            ZStack(alignment: .leading) {
                ForEach(Safety.allCases, id: \.self) { SafetyChip(safety: $0).hidden() }
                SafetyChip(safety: item.safety)
            }

            if kind == .downloads {
                // Only Downloads carries a meaningful last-opened date (from contentAccessDate);
                // backups/mail use other dates, so the "Last opened" caption is Downloads-only.
                Text(lastOpenedRelative)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationTooltip(lastOpenedRelative)
                    .frame(width: 140, alignment: .leading)
            }

            MiniSizeBar(
                fraction: categoryTotal > 0 ? Double(item.bytes) / Double(categoryTotal) : 0,
                tint: item.safety.color)
                .accessibilityHidden(true)

            Text(item.bytes.fileSize)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 66, alignment: .trailing)
                .contentTransition(.numericText())

            if item.isRevealOnly || item.isDeleting {
                Color.clear.frame(width: 28, height: 28) // keeps size columns aligned
            } else {
                trashButton
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .opacity(item.isDeleting ? 0.45 : 1) // greyed out until the delete finishes
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectedItem = item.id }
        .onHover { isHovered = $0 }
        .allowsHitTesting(!item.isDeleting)
        .alert("Move \u{201C}\(item.name)\u{201D} to Trash?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                if item.isCritical { showCriticalConfirm = true } else { model.delete([item.id]) }
            }
        } message: {
            Text(alertMessage)
        }
        // Extra confirmation for critical (irreplaceable-data) items.
        .alert("Really move \u{201C}\(item.name)\u{201D} to Trash?", isPresented: $showCriticalConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { model.delete([item.id]) }
        } message: {
            Text("This may hold irreplaceable data (such as iCloud files or device backups) that can't be re-downloaded. It will go to the Trash, so you can still restore it.")
        }
    }

    /// Relative last-opened date for user files (e.g. "Last opened 8 months ago").
    private var lastOpenedRelative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last opened " + formatter.localizedString(for: item.lastModified, relativeTo: Date())
    }

    /// Item detail plus a reassuring line; careful items get a short caution first.
    private var alertMessage: String {
        var lines: [String] = []
        if item.safety == .careful {
            lines.append("This may need to be rebuilt after deletion.")
        }
        lines.append(item.detail)
        lines.append("You can restore it from the Trash anytime.")
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Pieces

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.iconTile, style: .continuous)
            .fill(Theme.iconTileBackground)
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func badgePill(_ badge: ItemBadge) -> some View {
        let (text, color): (String, Color) = switch badge {
        case .leftover: ("LEFTOVER", Theme.caution)
        case .inUse: ("IN USE", Theme.careful)
        case .virtualMachine: ("VIRTUAL MACHINE", Theme.caution)
        }
        pill(text, color)
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var trashButton: some View {
        Button {
            showDeleteAlert = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 12))
                .foregroundStyle(isTrashHovered ? Theme.destructive : Theme.textTertiary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isTrashHovered ? Theme.destructive.opacity(0.16) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isTrashHovered = $0 }
        .accessibilityLabel("Move \(item.name) to Trash")
    }

    private var rowBackground: Color {
        if isSelected { Theme.selectedRow }
        else if isHovered { Theme.hover }
        else { Color.clear }
    }
}

#Preview {
    let model = ScanModel.mock
    let category = model.categories.first { $0.kind == .leftovers } ?? model.categories[0]
    return VStack(spacing: 0) {
        ForEach(category.items) { item in
            ItemRow(item: item, categoryTotal: category.total, kind: category.kind, model: model)
        }
    }
    .frame(width: 560)
    .background(Theme.windowBackground)
    .preferredColorScheme(.dark)
}
