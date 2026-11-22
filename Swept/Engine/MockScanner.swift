//
//  MockScanner.swift
//  Swept
//
//  Simulated scan for previews/tests. Animates progress, then returns MockData.
//

import Foundation

struct MockScanner: Scanning {
    func scan(progress: @escaping @Sendable (Double, String) -> Void) async throws -> [Category] {
        let paths = MockData.scanPaths
        let steps = 60
        for step in 1...steps {
            try await Task.sleep(nanoseconds: 30_000_000) // ~1.8s total; throws on cancel
            let index = min(paths.count - 1, step * paths.count / steps)
            progress(Double(step) / Double(steps), paths[index])
        }
        return MockData.categories
    }

    func sizesOnlyScan() async throws -> SizesSnapshot {
        try await Task.sleep(nanoseconds: 100_000_000) // pretend a quick measurement pass
        return SizesSnapshot(categories: MockData.categories)
    }

    func trashItem() async -> CleanItem? {
        MockData.categories.first { $0.kind == .trash }?.items.first
    }
}
