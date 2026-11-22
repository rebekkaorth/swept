//
//  SidebarView.swift
//  Swept
//
//  Left column: summary card, category list, "Scan again".
//

import SwiftUI

struct SidebarView: View {
    @Bindable var model: ScanModel
    var onScanAgain: () -> Void = {}
    var onTurnOnMonitoring: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            SummaryCard(reclaimable: model.reclaimable, totalSystemData: model.totalSystemData)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

            List(selection: $model.selectedCategory) {
                Section("System clutter") {
                    ForEach(model.systemCategories) { categoryRow($0) }
                }
                if !model.userFileCategories.isEmpty {
                    Section("Your Files") {
                        ForEach(model.userFileCategories) { categoryRow($0) }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onChange(of: model.selectedCategory) { _, newValue in
                model.selectedItem = model.categories
                    .first { $0.id == newValue }?.items.first?.id
            }

            VStack(spacing: 8) {
                Button {
                    onScanAgain()
                } label: {
                    Label("Scan again", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: .command) // ⌘R re-scan

                if let onTurnOnMonitoring {
                    Button {
                        onTurnOnMonitoring()
                    } label: {
                        Label("Turn on background monitoring", systemImage: "menubar.rectangle")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(12)
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        CategoryRow(category: category)
            .listRowSeparator(.hidden)
            .tag(category.id) // the sidebar's own full-width selection highlight marks the row
    }
}

#Preview {
    NavigationSplitView {
        SidebarView(model: .mock)
    } detail: {
        Color.clear
    }
    .frame(width: 900, height: 720)
    .preferredColorScheme(.dark)
}
