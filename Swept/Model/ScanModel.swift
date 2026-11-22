//
//  ScanModel.swift
//  Swept
//
//  Observable state for a scan session. Views stay dumb; all logic lives here.
//  Item/category/selection sums are always computed from `categories`, never stored.
//

import Foundation
import Observation
import SwiftUI

/// Result of a clean, recorded as the post-clean summary.
struct CleanSummary: Equatable {
    var trashedCount = 0
    var trashedBytes: Int64 = 0
    var permanentCount = 0
    var permanentBytes: Int64 = 0
    /// Human-readable notes for anything that failed.
    var failures: [String] = []

    var isEmpty: Bool {
        trashedCount == 0 && permanentCount == 0 && failures.isEmpty
    }
}

@Observable
final class ScanModel {

    /// Categories, sorted largest-first (items within each are sorted too).
    private(set) var categories: [Category]

    var selectedCategory: Category.ID?
    var selectedItem: CleanItem.ID?

    /// Items the user has ticked for cleaning.
    var checked: Set<CleanItem.ID> = []

    var isScanning: Bool = false
    var scanProgress: Double = 0
    /// The path the scanner is currently visiting (shown live on the Scanning screen).
    var currentPath: String = ""
    /// When the last completed scan finished.
    var lastScanned: Date?

    /// Total System Data footprint reported by the OS (a separate measurement, not a
    /// sum of items). Falls back to `reclaimable` when unknown.
    private var systemDataTotal: Int64?

    /// Injected scanner. Defaults to the real read-only filesystem scanner;
    /// previews/tests can pass `MockScanner()`.
    private let scanner: Scanning

    init(categories: [Category] = [],
         totalSystemData: Int64? = nil,
         scanner: Scanning = FileSystemScanner()) {
        let sorted = ScanModel.sorted(categories)
        self.categories = sorted
        self.systemDataTotal = totalSystemData
        self.scanner = scanner
        // Auto-select the largest category and its first (largest) item.
        self.selectedCategory = sorted.first?.id
        self.selectedItem = sorted.first?.items.first?.id
    }

    // MARK: - Mutating

    /// Replaces the category set, keeping the largest-first ordering invariant.
    func setCategories(_ categories: [Category]) {
        self.categories = ScanModel.sorted(categories)
    }

    /// Selects a category and auto-selects its first (largest) item.
    func selectCategory(_ id: Category.ID?) {
        selectedCategory = id
        selectedItem = categories.first { $0.id == id }?.items.first?.id
    }

    /// Toggles an item in the delete set. Independent of row selection.
    /// Reveal-only items can never join the delete set.
    func toggleChecked(_ id: CleanItem.ID) {
        if checked.contains(id) {
            checked.remove(id)
        } else if let item = allItems.first(where: { $0.id == id }), !item.isRevealOnly, !item.isDeleting {
            checked.insert(id)
        }
    }

    /// Checks everything eligible for bulk selection — system clutter that can go to the Trash.
    /// User files (and permanent items) are skipped; they must be checked individually.
    func selectAll() {
        checked = Set(
            allItems
                .filter { $0.ownership == .systemJunk && $0.deletionKind == .trashable && !$0.isDeleting }
                .map(\.id)
        )
    }

    /// Categories of system clutter (largest-first) — the "System clutter" sidebar group.
    var systemCategories: [Category] { categories.filter { !$0.isUserFiles } }

    /// Categories of the user's own files (largest-first) — the "Your Files" sidebar group.
    var userFileCategories: [Category] { categories.filter(\.isUserFiles) }

    // MARK: - Computed totals (never stored)

    /// Every reclaimable item across all categories.
    var reclaimable: Int64 {
        categories.reduce(0) { $0 + $1.total }
    }

    /// Combined size of the currently checked items.
    var selectedBytes: Int64 {
        allItems
            .filter { checked.contains($0.id) }
            .reduce(0) { $0 + $1.bytes }
    }

    /// Total System Data footprint Swept is tracking.
    var totalSystemData: Int64 {
        systemDataTotal ?? reclaimable
    }

    // MARK: - Lookups

    /// Flat view of every item across all categories.
    var allItems: [CleanItem] {
        categories.flatMap(\.items)
    }

    var selectedCategoryValue: Category? {
        categories.first { $0.id == selectedCategory }
    }

    var selectedItemValue: CleanItem? {
        guard let selectedItem else { return nil }
        return allItems.first { $0.id == selectedItem }
    }

    /// The category that contains the given item, if any.
    func category(containing id: CleanItem.ID) -> Category? {
        categories.first { category in category.items.contains { $0.id == id } }
    }

    /// The currently checked items (grouped-order preserved: largest category first).
    var checkedItems: [CleanItem] {
        categories.flatMap { $0.items.filter { checked.contains($0.id) } }
    }

    /// Checked items grouped by category, largest-first, for the review sheet.
    var checkedGroups: [(kind: CategoryKind, items: [CleanItem])] {
        categories.compactMap { category in
            let items = category.items.filter { checked.contains($0.id) }
            return items.isEmpty ? nil : (category.kind, items)
        }
    }

    // MARK: - Deletion

    /// The result of the most recent clean (trashed + permanently-deleted + failures).
    private(set) var lastCleanSummary: CleanSummary?

    /// Per-row / ⌘⌫ path — trashable only, single step (behavior unchanged).
    /// Permanent items are ignored here; they require the sheet's forever-confirmation.
    func delete(_ ids: Set<CleanItem.ID>) {
        performClean(trashable: ids, permanent: [])
    }

    /// Executes a clean. Trashable items are moved to the Trash (recoverable); permanent items
    /// are deleted IRREVERSIBLY (empty Trash / delete snapshots) and must already have been
    /// confirmed by the caller's forever-alert. Both tiers are logged to `lastCleanSummary`.
    ///
    /// Returns immediately: the items are marked `isDeleting` (greyed out, bytes deducted) while
    /// the file work runs off the main thread, then removed — or restored if they failed.
    func performClean(trashable: Set<CleanItem.ID>, permanent: Set<CleanItem.ID>) {
        let trashTargets = allItems.filter {
            trashable.contains($0.id) && $0.deletionKind == .trashable && !$0.isDeleting
        }
        let permanentTargets = allItems
            .filter { permanent.contains($0.id) && $0.deletionKind == .permanent && !$0.isDeleting }
            .map { (item: $0, kind: category(containing: $0.id)?.kind) }
        let ids = Set(trashTargets.map(\.id)).union(permanentTargets.map(\.item.id))
        guard !ids.isEmpty else { return }

        checked.subtract(ids)
        withAnimation(Theme.Motion.standard) { setDeleting(ids, true) }

        Task {
            let (summary, removed) = await Task.detached(priority: .userInitiated) {
                var summary = CleanSummary()
                var removed = Set<CleanItem.ID>()
                // Empty the Trash BEFORE moving new items into it, or emptying would take them too.
                removed.formUnion(Self.deletePermanently(permanentTargets, summary: &summary))
                removed.formUnion(Self.moveToTrash(trashTargets, summary: &summary))
                return (summary, removed)
            }.value

            if !summary.isEmpty { lastCleanSummary = summary }
            withAnimation(Theme.Motion.standard) {
                setDeleting(ids.subtracting(removed), false) // failures come back, size and all
                removeItems(removed)
            }

            // What was just moved now sits in the Trash — re-measure it so its row is current.
            if summary.trashedCount > 0 {
                let trash = await scanner.trashItem()
                withAnimation(Theme.Motion.standard) { updateTrash(trash) }
            }
        }
    }

    /// Replaces the Trash row with a fresh measurement (keeping its id, so selection survives),
    /// or adds the Trash category if it wasn't there before. Leaves a Trash empty in progress alone.
    private func updateTrash(_ fresh: CleanItem?) {
        guard let fresh else { return }
        var updated = categories
        if let c = updated.firstIndex(where: { $0.kind == .trash }) {
            guard let existing = updated[c].items.first, !existing.isDeleting else { return }
            updated[c].items = [CleanItem(
                id: existing.id, name: fresh.name, explanation: fresh.explanation,
                detail: fresh.detail, bytes: fresh.bytes, safety: fresh.safety,
                url: fresh.url, lastModified: fresh.lastModified, owner: fresh.owner,
                badge: fresh.badge, isCritical: fresh.isCritical,
                ownership: fresh.ownership, deletionKind: fresh.deletionKind)]
        } else {
            updated.append(Category(kind: .trash, items: [fresh]))
        }
        categories = ScanModel.sorted(updated)
    }

    /// Flags (or unflags) items as being deleted, without re-sorting the list.
    private func setDeleting(_ ids: Set<CleanItem.ID>, _ deleting: Bool) {
        guard !ids.isEmpty else { return }
        categories = categories.map { category in
            var category = category
            for index in category.items.indices where ids.contains(category.items[index].id) {
                category.items[index].isDeleting = deleting
            }
            return category
        }
    }

    /// Moves trashable items to the Trash. TRASH-ONLY (recoverable); allowlist-guarded;
    /// a single failure is skipped so it never aborts the batch. Runs off the main thread.
    private nonisolated static func moveToTrash(_ targets: [CleanItem], summary: inout CleanSummary) -> Set<CleanItem.ID> {
        var trashed = Set<CleanItem.ID>()
        for item in targets {
            guard ScanSources.isAllowed(item.url) else {
                assertionFailure("Refusing to trash a path outside the allowlist: \(item.url.path)")
                continue
            }
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                trashed.insert(item.id)
                summary.trashedCount += 1
                summary.trashedBytes += item.bytes
            } catch {
                summary.failures.append("\(item.name): \(error.localizedDescription)")
                NSLog("Swept: could not move \(item.url.path) to Trash — \(error.localizedDescription)")
            }
        }
        return trashed
    }

    /// Deletes permanent items IRREVERSIBLY: empties the Trash (FileManager.removeItem on its
    /// contents) or removes a Time Machine snapshot (tmutil). Callers MUST have confirmed first.
    /// Runs off the main thread.
    private nonisolated static func deletePermanently(
        _ targets: [(item: CleanItem, kind: CategoryKind?)], summary: inout CleanSummary
    ) -> Set<CleanItem.ID> {
        var removed = Set<CleanItem.ID>()
        for (item, kind) in targets {
            let result: (ok: Bool, freed: Int64, failure: String?)
            switch kind {
            case .trash:          result = emptyTrash(reportedBytes: item.bytes)
            case .localSnapshots: result = deleteSnapshot(item)
            default:              result = (false, 0, "\(item.name): unsupported permanent item")
            }
            if result.ok {
                removed.insert(item.id)
                summary.permanentCount += 1
                summary.permanentBytes += result.freed
            }
            if let failure = result.failure {
                summary.failures.append(failure)
                NSLog("Swept: \(failure)")
            }
        }
        return removed
    }

    /// Empties the Trash by removing each item under ~/.Trash (the contents, not the folder).
    private nonisolated static func emptyTrash(reportedBytes: Int64) -> (ok: Bool, freed: Int64, failure: String?) {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: trash, includingPropertiesForKeys: nil, options: [])
            var stuck: [String] = []
            for url in contents {
                do { try FileManager.default.removeItem(at: url) }
                catch {
                    // Usually a read-only folder or a locked file inside the item: unlock our own
                    // files and retry once before giving up on it.
                    makeRemovable(url)
                    do { try FileManager.default.removeItem(at: url) }
                    catch {
                        stuck.append(url.lastPathComponent)
                        NSLog("Swept: could not empty \(url.lastPathComponent) — \(error.localizedDescription)")
                    }
                }
            }
            guard !stuck.isEmpty else { return (true, reportedBytes, nil) }
            let failure = "Trash — \(stuck.count) item\(stuck.count == 1 ? "" : "s") couldn't be removed (\(stuck.joined(separator: ", "))). Empty the Trash in Finder to remove \(stuck.count == 1 ? "it" : "them")."
            return (false, 0, failure)
        } catch {
            return (false, 0, "Trash — \(error.localizedDescription)")
        }
    }

    /// Clears the lock flag and adds owner read/write(/search) permission on `url` and everything
    /// below it, so `removeItem` can descend into read-only folders. Only touches files the user
    /// owns, never follows symlinks (a link could point outside the Trash), and is only ever
    /// called on items inside ~/.Trash that the user already chose to delete permanently.
    private nonisolated static func makeRemovable(_ url: URL) {
        let fm = FileManager.default
        let trash = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(trash + "/") else { return }
        let uid = NSNumber(value: getuid())

        func unlock(_ path: String) {
            guard let attrs = try? fm.attributesOfItem(atPath: path), // doesn't follow a final symlink
                  attrs[.type] as? FileAttributeType != .typeSymbolicLink,
                  attrs[.ownerAccountID] as? NSNumber == uid else { return }
            let isDir = attrs[.type] as? FileAttributeType == .typeDirectory
            let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
            var update: [FileAttributeKey: Any] = [
                .posixPermissions: perms | (isDir ? 0o700 : 0o600),
            ]
            if attrs[.immutable] as? Bool == true { update[.immutable] = false }
            try? fm.setAttributes(update, ofItemAtPath: path)
        }

        unlock(url.path) // first, so the enumerator can read the top folder
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil,
                                             options: [], errorHandler: { _, _ in true }) else { return }
        for case let child as URL in enumerator { unlock(child.path) }
    }

    /// Deletes a local Time Machine snapshot via `tmutil deletelocalsnapshots <date>`.
    /// (tmutil is the only subprocess used for snapshots — see FileSystemScanner.)
    private nonisolated static func deleteSnapshot(_ item: CleanItem) -> (ok: Bool, freed: Int64, failure: String?) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: item.lastModified)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["deletelocalsnapshots", stamp]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return (true, item.bytes, nil) }
            let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (false, 0, "Snapshot \(stamp) — \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
        } catch {
            return (false, 0, "Snapshot \(stamp) — \(error.localizedDescription)")
        }
    }

    /// Removes already-trashed items from the in-memory model and repairs selection.
    private func removeItems(_ ids: Set<CleanItem.ID>) {
        var remaining = categories.map { category -> Category in
            var category = category
            category.items.removeAll { ids.contains($0.id) }
            return category
        }
        remaining.removeAll { $0.items.isEmpty }
        categories = ScanModel.sorted(remaining)

        checked.subtract(ids)

        // Clear selection if the selected item was deleted.
        if let selectedItem, ids.contains(selectedItem) {
            self.selectedItem = nil
        }
        // If the selected category is gone, fall back to the new largest one.
        if selectedCategory == nil
            || !categories.contains(where: { $0.id == selectedCategory }) {
            selectedCategory = categories.first?.id
        }
        // Ensure a valid item is selected within the current category.
        let itemStillValid = selectedItem.map { id in
            selectedCategoryValue?.items.contains { $0.id == id } ?? false
        } ?? false
        if !itemStillValid {
            selectedItem = selectedCategoryValue?.items.first?.id
        }
    }

    // MARK: - Scanning

    /// Runs the injected scanner and returns `true` if it completed, `false` if cancelled.
    /// The scanner is READ-ONLY; this method only reads and updates in-memory state.
    func scan() async -> Bool {
        isScanning = true
        scanProgress = 0
        currentPath = ""

        do {
            let found = try await scanner.scan { fraction, path in
                // Callback may arrive off the main thread; hop back to update UI state.
                Task { @MainActor [weak self] in
                    self?.scanProgress = fraction
                    self?.currentPath = path
                }
            }
            setCategories(found)
            systemDataTotal = VolumeInfo.approxSystemData()
            selectedCategory = categories.first?.id
            selectedItem = categories.first?.items.first?.id
            lastScanned = Date()
            isScanning = false
            currentPath = ""
            return true
        } catch is CancellationError {
            // Cancelled: leave prior results untouched.
            isScanning = false
            currentPath = ""
            return false
        } catch {
            // Unexpected failure: finish gracefully; routing decides main/empty.
            isScanning = false
            currentPath = ""
            return true
        }
    }

    // MARK: - Helpers

    /// Sorts categories largest-first and each category's items largest-first.
    private static func sorted(_ categories: [Category]) -> [Category] {
        categories
            .map { category in
                var category = category
                category.items.sort { $0.bytes > $1.bytes }
                return category
            }
            .sorted { $0.total > $1.total }
    }
}
