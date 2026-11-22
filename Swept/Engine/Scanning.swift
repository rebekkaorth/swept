//
//  Scanning.swift
//  Swept
//
//  Abstraction over "how we find reclaimable items". Two conformers exist:
//  MockScanner (previews/tests) and FileSystemScanner (the real, read-only scan).
//

import Foundation

/// Result of a fast, totals-only measurement pass (no CleanItems built).
struct SizesSnapshot: Sendable {
    var total: Int64
    var byCategory: [CategoryKind: Int64]
}

extension SizesSnapshot {
    /// Totals derived from a full scan's categories, so the menu bar and the main window
    /// always agree on how bytes are bucketed (e.g. orphaned app data → Leftovers).
    init(categories: [Category]) {
        var byCategory: [CategoryKind: Int64] = [:]
        for category in categories { byCategory[category.kind, default: 0] += category.total }
        self.init(total: byCategory.values.reduce(0, +), byCategory: byCategory)
    }
}

protocol Scanning: Sendable {
    /// Performs a READ-ONLY scan and returns the found categories.
    /// `progress` is called with (fractionComplete 0…1, currentPath) and may be
    /// invoked off the main thread. Throws `CancellationError` if cancelled.
    func scan(progress: @escaping @Sendable (Double, String) -> Void) async throws -> [Category]

    /// READ-ONLY measurement pass over `ScanSources.all`: total reclaimable bytes and
    /// per-CategoryKind totals, bucketed exactly like `scan` so the numbers match the main
    /// window. Allowlist-only. Used by background monitoring to detect growth.
    func sizesOnlyScan() async throws -> SizesSnapshot

    /// READ-ONLY re-measure of just the Trash, after Swept moved things into it. `nil` when the
    /// Trash is empty (below the size floor).
    func trashItem() async -> CleanItem?
}
