//
//  ReviewDeleteSheet.swift
//  Swept
//
//  Bulk confirmation for the checked set. Two tiers: items "Moving to Trash"
//  (recoverable, single step) and, visually separated, items "Deleting forever"
//  (permanent — empty Trash / snapshots) which require a second native alert.
//

import SwiftUI

struct ReviewDeleteSheet: View {
    let model: ScanModel
    @Binding var isPresented: Bool

    @State private var showCriticalConfirm = false
    @State private var showForeverConfirm = false

    private var count: Int { model.checked.count }
    private var total: Int64 { model.selectedBytes }

    private var trashableGroups: [(kind: CategoryKind, items: [CleanItem])] {
        model.checkedGroups.compactMap { group in
            let items = group.items.filter { $0.deletionKind == .trashable }
            return items.isEmpty ? nil : (group.kind, items)
        }
    }
    private var permanentItems: [CleanItem] {
        model.checkedItems.filter { $0.deletionKind == .permanent }
    }
    private var permanentBytes: Int64 { permanentItems.reduce(0) { $0 + $1.bytes } }
    /// Trashable, irreplaceable-data items (e.g. device backups) — get the existing extra confirm.
    private var criticalItems: [CleanItem] {
        model.checkedItems.filter { $0.isCritical && $0.deletionKind == .trashable }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            itemList
            banner
            footer
        }
        .padding(24)
        .frame(width: 480)
        .background(Theme.windowBackground)
        .onChange(of: model.checked.isEmpty) { _, isEmpty in
            if isEmpty { isPresented = false }
        }
        // 1. Trashable but irreplaceable (e.g. device backups) — confirm before trashing.
        .alert("Some items hold irreplaceable data", isPresented: $showCriticalConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move all to Trash", role: .destructive) { proceedAfterCritical() }
        } message: {
            Text(criticalMessage)
        }
        // 2. Permanent tier — irreversible, macOS-native, cancel defaulted.
        .alert("Delete \(permanentBytes.fileSize) forever?", isPresented: $showForeverConfirm) {
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction) // safest option is the default
            Button("Delete Forever", role: .destructive) { executeClean() }
        } message: {
            Text("These items can't be moved to the Trash. This can't be undone.")
        }
    }

    // MARK: - Confirmation flow

    private func onPrimary() {
        if !criticalItems.isEmpty { showCriticalConfirm = true } else { proceedAfterCritical() }
    }

    private func proceedAfterCritical() {
        if !permanentItems.isEmpty { showForeverConfirm = true } else { executeClean() }
    }

    private func executeClean() {
        model.performClean(
            trashable: Set(trashableGroups.flatMap { $0.items }.map(\.id)),
            permanent: Set(permanentItems.map(\.id))
        )
        isPresented = false
    }

    private var criticalMessage: String {
        let names = criticalItems.map(\.name).joined(separator: ", ")
        return "\(names) may hold data that can't be re-downloaded (such as iCloud files or device backups). Everything goes to the Trash, so you can still restore it — but review carefully first."
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Review & Delete")
                .font(Typography.title2)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 0) {
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(" \(itemsWord(count)) · ")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Text(total.fileSize)
                    .font(.system(size: 13, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Partitioned item list

    private var itemList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !trashableGroups.isEmpty {
                    sectionLabel("Moving to Trash", color: Theme.textTertiary, icon: "arrow.up.bin")
                    ForEach(trashableGroups, id: \.kind) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.kind.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(Typography.uppercaseTracking)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.textTertiary)
                            ForEach(group.items) { line($0, kind: group.kind) }
                        }
                    }
                }

                if !permanentItems.isEmpty {
                    if !trashableGroups.isEmpty {
                        Divider().overlay(Theme.hairline).padding(.vertical, 2)
                    }
                    sectionLabel("Deleting forever", color: Theme.destructive, icon: "exclamationmark.triangle.fill")
                    ForEach(permanentItems) { item in
                        line(item, kind: model.category(containing: item.id)?.kind ?? .trash)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 320)
    }

    private func sectionLabel(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .tracking(Typography.uppercaseTracking)
                .textCase(.uppercase)
        }
        .foregroundStyle(color)
    }

    private func line(_ item: CleanItem, kind: CategoryKind) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: Theme.Radius.iconTileSmall, style: .continuous)
                .fill(Theme.iconTileBackground)
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            Text(item.name)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationTooltip(item.name)
            Spacer(minLength: 8)
            SafetyChip(safety: item.safety)
            Text(item.bytes.fileSize)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    // MARK: - Safety banner (describes the trashable items only — the "Deleting forever"
    // section carries its own warning and the forever alert).

    private var trashableItems: [CleanItem] { trashableGroups.flatMap { $0.items } }

    /// Only shown when something needs a closer look — an all-safe selection needs no banner.
    @ViewBuilder
    private var banner: some View {
        if !trashableItems.isEmpty, mostSevere != .safe {
            let severity = mostSevere
            HStack(spacing: 10) {
                Image(systemName: bannerSymbol(severity))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(severity.color)
                Text(bannerText(severity))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(severity.color.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { isPresented = false }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction) // esc
            Button(primaryTitle) { onPrimary() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
        }
    }

    private var primaryTitle: String {
        permanentItems.isEmpty
            ? "Move \(count) \(itemsWord(count)) to Trash"
            : "Clean \(count) \(itemsWord(count))"
    }

    // MARK: - Helpers

    private func itemsWord(_ count: Int) -> String { count == 1 ? "item" : "items" }

    /// Highest severity among the TRASHABLE items (the banner only covers those).
    private var mostSevere: Safety {
        let safeties = trashableItems.map(\.safety)
        if safeties.contains(.careful) { return .careful }
        if safeties.contains(.caution) { return .caution }
        return .safe
    }

    private func bannerSymbol(_ severity: Safety) -> String {
        switch severity {
        case .safe: "checkmark.circle.fill" // not shown: the banner hides when all are safe
        case .caution: "exclamationmark.circle.fill"
        case .careful: "exclamationmark.triangle.fill"
        }
    }

    private func bannerText(_ severity: Safety) -> String {
        guard severity != .safe else { return "" }
        let flagged = trashableItems.filter { $0.safety != .safe }
        let names = trashableGroups
            .filter { $0.items.contains { $0.safety != .safe } }
            .map(\.kind.title)
        let list = names.joined(separator: ", ")
        let noun = flagged.count == 1 ? "item needs" : "items need"
        return "\(flagged.count) \(noun) a closer look — \(list). They'll be recoverable from the Trash."
    }
}

#Preview("All safe") {
    let model = ScanModel.mock
    if let safe = model.categories.first(where: { $0.kind == .appCaches }) {
        model.checked = Set(safe.items.map(\.id))
    }
    return ReviewDeleteSheet(model: model, isPresented: .constant(true))
}

#Preview("With permanent tier") {
    let model = ScanModel.mock
    var ids = Set<CleanItem.ID>()
    if let caches = model.categories.first(where: { $0.kind == .appCaches }) {
        ids.formUnion(caches.items.prefix(1).map(\.id)) // trashable
    }
    if let trash = model.categories.first(where: { $0.kind == .trash }) {
        ids.formUnion(trash.items.map(\.id)) // permanent
    }
    if let snaps = model.categories.first(where: { $0.kind == .localSnapshots }) {
        ids.formUnion(snaps.items.map(\.id)) // permanent
    }
    model.checked = ids
    return ReviewDeleteSheet(model: model, isPresented: .constant(true))
}
