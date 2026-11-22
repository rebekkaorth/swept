//
//  SizesSnapshotTests.swift
//  SweptTests
//
//  The menu bar total and the main window must agree: SizesSnapshot(categories:)
//  buckets bytes exactly as the categories do.
//

import Foundation
import Testing
@testable import Swept

/// Disambiguates from Testing's own `Category`.
private typealias Category = Swept.Category

@Suite("SizesSnapshot(categories:)")
struct SizesSnapshotTests {

    private func item(_ bytes: Int64) -> CleanItem {
        CleanItem(name: "item", explanation: "", detail: "", bytes: bytes, safety: .safe,
                  url: URL(fileURLWithPath: "/tmp/item"), lastModified: .distantPast)
    }

    private func expectMatches(_ categories: [Category]) {
        let snapshot = SizesSnapshot(categories: categories)

        var expected: [CategoryKind: Int64] = [:]
        for category in categories { expected[category.kind, default: 0] += category.total }

        #expect(snapshot.byCategory == expected)
        #expect(snapshot.total == categories.reduce(0) { $0 + $1.total })
        #expect(snapshot.total == snapshot.byCategory.values.reduce(0, +))
    }

    @Test func emptyCategoriesGiveZero() {
        let snapshot = SizesSnapshot(categories: [])
        #expect(snapshot.total == 0)
        #expect(snapshot.byCategory.isEmpty)
    }

    @Test func totalsMatchPerKind() {
        let categories = [
            Category(kind: .xcodeSimulators, items: [item(1_000), item(2_500)]),
            Category(kind: .appCaches, items: [item(300)]),
            Category(kind: .leftovers, items: [item(7), item(8), item(9)]),
            Category(kind: .downloads, items: []),
        ]
        expectMatches(categories)

        let snapshot = SizesSnapshot(categories: categories)
        #expect(snapshot.byCategory[.xcodeSimulators] == 3_500)
        #expect(snapshot.byCategory[.appCaches] == 300)
        #expect(snapshot.byCategory[.leftovers] == 24)
        #expect(snapshot.byCategory[.downloads] == 0)
        #expect(snapshot.total == 3_824)
    }

    @Test func duplicateKindsAreSummedTogether() {
        let categories = [
            Category(kind: .logs, items: [item(100)]),
            Category(kind: .logs, items: [item(250), item(50)]),
        ]
        expectMatches(categories)
        #expect(SizesSnapshot(categories: categories).byCategory == [.logs: 400])
    }

    @Test func mockDataTotalsMatch() {
        expectMatches(MockData.categories)
    }

    @Test func largeSizesDoNotLoseBytes() {
        let categories = [
            Category(kind: .applicationSupport, items: [item(400_000_000_000), item(123_456_789_012)]),
            Category(kind: .trash, items: [item(1)]),
        ]
        expectMatches(categories)
        #expect(SizesSnapshot(categories: categories).total == 523_456_789_013)
    }
}
