//
//  ContentPaneView.swift
//  Swept
//
//  Middle column: category toolbar, scrollable item list, and the action bar
//  (the action bar lives here so it never spans under the inspector).
//

import SwiftUI

struct ContentPaneView: View {
    let model: ScanModel

    @State private var confirmDeleteSelected = false
    @State private var confirmCriticalDelete = false
    @FocusState private var listFocused: Bool

    private var category: Category? { model.selectedCategoryValue }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if category?.isUserFiles == true { userFilesBanner }
            itemList
            ActionBar(model: model)
        }
        .background(Theme.windowBackground)
        .focusable()
        .focused($listFocused)
        .onAppear { listFocused = true }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.space) {
            if let id = model.selectedItem { model.toggleChecked(id) }
            return .handled
        }
        .background {
            // ⌘⌫ moves the selected item to the Trash (same confirmation as the row button).
            // Reveal-only items have no Trash action, so the shortcut does nothing for them.
            Button("") {
                if let item = model.selectedItemValue, !item.isRevealOnly, !item.isDeleting {
                    confirmDeleteSelected = true
                }
            }
                .keyboardShortcut(.delete, modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .background {
            // ⌘A selects all — system clutter only; user files are skipped by design.
            Button("") { model.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .alert(deleteAlertTitle, isPresented: $confirmDeleteSelected) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                if model.selectedItemValue?.isCritical == true {
                    confirmCriticalDelete = true
                } else if let id = model.selectedItem {
                    model.delete([id])
                }
            }
        } message: {
            Text(deleteAlertMessage)
        }
        // Extra confirmation for critical (irreplaceable-data) items.
        .alert("Really move \u{201C}\(model.selectedItemValue?.name ?? "")\u{201D} to Trash?",
               isPresented: $confirmCriticalDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                if let id = model.selectedItem { model.delete([id]) }
            }
        } message: {
            Text("This may hold irreplaceable data (such as iCloud files or device backups) that can't be re-downloaded. It will go to the Trash, so you can still restore it.")
        }
    }

    // MARK: - Keyboard navigation

    private func moveSelection(_ delta: Int) {
        guard let items = category?.items, !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == model.selectedItem } ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        model.selectedItem = items[next].id
    }

    private var deleteAlertTitle: String {
        "Move \u{201C}\(model.selectedItemValue?.name ?? "")\u{201D} to Trash?"
    }

    private var deleteAlertMessage: String {
        guard let item = model.selectedItemValue else { return "" }
        var lines: [String] = []
        if item.safety == .careful { lines.append("This may need to be rebuilt after deletion.") }
        lines.append(item.detail)
        lines.append("You can restore it from the Trash anytime.")
        return lines.joined(separator: "\n\n")
    }

    // MARK: - User-files banner (persistent, non-dismissable)

    private var userFilesBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("These are your own files. If you delete them, they are moved to the Trash.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.10))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(category?.title ?? "—")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationTooltip(category?.title ?? "")
                if let category {
                    HStack(spacing: 5) {
                        Text("\(category.items.count) items")
                            .font(.system(size: 12))
                        Text("·")
                            .font(.system(size: 12))
                        Text(category.total.fileSize)
                            .font(.system(size: 12, design: .monospaced))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Theme.barBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    // MARK: - List

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let category {
                        ForEach(category.items) { item in
                            ItemRow(item: item,
                                    categoryTotal: category.total,
                                    kind: category.kind,
                                    model: model)
                                .id(item.id)
                        }
                    }
                }
            }
            .onChange(of: model.selectedItem) { _, id in
                guard let id else { return }
                withAnimation(Theme.Motion.quick) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("System clutter") {
    ContentPaneView(model: .mock)
        .frame(width: 620, height: 720)
        .preferredColorScheme(.dark)
}

#Preview("Your Files") {
    let model = ScanModel.mock
    if let downloads = model.userFileCategories.first(where: { $0.kind == .downloads }) {
        model.selectCategory(downloads.id)
    }
    return ContentPaneView(model: model)
        .frame(width: 620, height: 720)
        .preferredColorScheme(.dark)
}
