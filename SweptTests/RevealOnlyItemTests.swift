//
//  RevealOnlyItemTests.swift
//  SweptTests
//
//  Reveal-only items are shown but can never be checked, trashed, or counted as reclaimable.
//

import Foundation
import Testing
@testable import Swept

/// Disambiguates from Testing's own `Category`.
private typealias Category = Swept.Category

@MainActor
@Suite("Reveal-only items")
struct RevealOnlyItemTests {

    private func item(_ bytes: Int64, _ kind: DeletionKind) -> CleanItem {
        CleanItem(name: "item", explanation: "", detail: "", bytes: bytes, safety: .careful,
                  url: URL(fileURLWithPath: "/tmp/item"), lastModified: .distantPast,
                  deletionKind: kind)
    }

    @Test func excludedFromCategoryTotal() {
        let category = Category(kind: .applicationSupport,
                                items: [item(100, .trashable), item(5_000, .revealOnly)])
        #expect(category.total == 100)
        #expect(SizesSnapshot(categories: [category]).total == 100)
    }

    @Test func cannotBeChecked() {
        let protected = item(5_000, .revealOnly)
        let model = ScanModel(categories: [Category(kind: .applicationSupport, items: [protected])],
                              scanner: MockScanner())
        model.toggleChecked(protected.id)
        #expect(model.checked.isEmpty)
    }

    @Test func skippedBySelectAll() {
        let trashable = item(100, .trashable)
        let model = ScanModel(
            categories: [Category(kind: .applicationSupport,
                                  items: [trashable, item(5_000, .revealOnly)])],
            scanner: MockScanner())
        model.selectAll()
        #expect(model.checked == [trashable.id])
    }
}
