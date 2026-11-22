//
//  Category.swift
//  Swept
//
//  A group of reclaimable items of one kind.
//

import Foundation

struct Category: Identifiable, Hashable {
    let id: UUID
    var kind: CategoryKind
    var items: [CleanItem]

    /// Combined size of all reclaimable items (reveal-only items can't be reclaimed; items being
    /// deleted are already counted as gone). Always computed, never stored.
    var total: Int64 {
        items.reduce(0) { $0 + ($1.isRevealOnly || $1.isDeleting ? 0 : $1.bytes) }
    }

    /// True when this category holds the user's own files (never preselected by select-all).
    var isUserFiles: Bool {
        !items.isEmpty && items.allSatisfy { $0.ownership == .userFiles }
    }

    var title: String { kind.title }
    var symbol: String { kind.symbol }

    init(id: UUID = UUID(), kind: CategoryKind, items: [CleanItem] = []) {
        self.id = id
        self.kind = kind
        self.items = items
    }
}
