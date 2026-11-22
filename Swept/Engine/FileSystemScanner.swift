//
//  FileSystemScanner.swift
//  Swept
//
//  ============================================================================
//  READ-ONLY. This engine ONLY reads the filesystem. It never writes, moves,
//  renames, or deletes anything. It only ever touches paths contained in
//  ScanSources.allowedRoots (guarded on every item). Deletion lives elsewhere.
//  ============================================================================
//

import Foundation
import AppKit

/// Thread-safe cancellation flag bridged from Swift task cancellation.
private final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func cancel() { lock.lock(); flag = true; lock.unlock() }
}

/// Caches whether an app with a given bundle id is currently installed.
private final class AppPresence: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: Bool] = [:]

    func isInstalled(bundleID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[bundleID] { return cached }
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        cache[bundleID] = installed
        return installed
    }
}

/// Index of installed app display names, for resolving plainly-named data folders (e.g. "Claude").
private final class InstalledApps: @unchecked Sendable {
    private let byName: [String: String] // lowercased app name → canonical display name

    init() {
        var map: [String: String] = [:]
        let dirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
        ]
        for dir in dirs {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for app in entries where app.pathExtension == "app" {
                let name = app.deletingPathExtension().lastPathComponent
                map[name.lowercased()] = name
            }
        }
        byName = map
    }

    /// Canonical app name if an installed app matches this folder name, else nil.
    func match(folderName: String) -> String? { byName[folderName.lowercased()] }
}

struct FileSystemScanner: Scanning {

    /// Ignore anything smaller than this to avoid noise.
    private static let sizeFloor: Int64 = 5_000_000 // ~5 MB
    /// A VM / disk-image payload must be at least this big to be split out.
    private static let vmFloor: Int64 = 200_000_000 // ~200 MB
    /// How deep to look inside an app-data folder for VM payloads.
    private static let vmSearchDepth = 4

    /// Roots (that aren't surfaceAll) whose children may be reclassified as leftovers.
    private static let leftoverEligible: Set<CategoryKind> = [.appCaches, .savedAppState]

    /// Reverse-DNS namespaces owned by tools/frameworks, not user apps. Never leftovers.
    private static let nonAppNamespaces = ["com.apple.", "org.swift."]

    /// File extensions that denote a virtual-machine / disk image.
    private static let imageExtensions: Set<String> = ["img", "raw", "qcow2", "vmdk", "vhdx", "sparseimage"]

    /// App-data folders that may hold IRREPLACEABLE data (iCloud files, device backups).
    /// Still deletable, but flagged critical so the UI demands an extra confirmation.
    /// Matched case-insensitively against the folder name. (Extend conservatively.)
    private static let criticalNames: Set<String> = [
        "clouddocs", "com.apple.clouddocs", "fileprovider", "com.apple.fileprovider",
        "mobilesync", "com.apple.bird", "mobile documents", "backup",
    ]

    private nonisolated static func isCriticalData(_ name: String) -> Bool {
        criticalNames.contains(name.lowercased())
    }

    // MARK: - Entry point

    nonisolated func scan(progress: @escaping @Sendable (Double, String) -> Void) async throws -> [Category] {
        let box = CancelBox()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                try Self.performScan(progress: progress, isCancelled: { box.isCancelled })
            }.value
        } onCancel: {
            box.cancel()
        }
    }

    #if DEBUG
    /// Synchronous read-only scan for previews/inspection only. Blocks the caller;
    /// never used on the app's real code path.
    nonisolated func scanBlocking() -> [Category] {
        (try? Self.performScan(progress: { _, _ in }, isCancelled: { false })) ?? []
    }
    #endif

    // MARK: - Background measurement (READ-ONLY, allowlist-only)

    /// Runs the same read-only pass as `scan` and keeps only the per-category totals. Sharing
    /// the pass (instead of a separate, simpler walk) keeps the menu-bar numbers identical to
    /// the main window's: leftovers, VM payloads, and size floors are all bucketed the same way.
    /// Runs at utility QoS and is cancellable.
    nonisolated func sizesOnlyScan() async throws -> SizesSnapshot {
        let categories = try await scan(progress: { _, _ in })
        return SizesSnapshot(categories: categories)
    }

    nonisolated func trashItem() async -> CleanItem? {
        await Task.detached(priority: .utility) {
            guard let source = ScanSources.all.first(where: { $0.kind == .trash }) else { return nil }
            return Self.makeItem(at: source.url, source: source,
                                 appPresence: AppPresence(), isCancelled: { false })
        }.value
    }

    // MARK: - Core scan (runs off the main thread)

    private nonisolated static func performScan(
        progress: @escaping @Sendable (Double, String) -> Void,
        isCancelled: () -> Bool
    ) throws -> [Category] {
        // FDA is required app-wide before a scan is ever started (see ContentView gate),
        // so all sources — including system paths — are reachable. This stays as a
        // defensive belt in case the scanner is ever invoked without access.
        let fdaGranted = FullDiskAccess.isGranted()
        let sources = ScanSources.all.filter { !$0.requiresElevation || fdaGranted }

        // A container child is skipped when a more-specific source already handles it — either
        // the child IS another source root (e.g. Caches/Homebrew) or CONTAINS one (e.g.
        // Application Support/MobileSync, whose Backup subfolder is its own source).
        let sourceRoots = ScanSources.all.map { $0.url.standardizedFileURL.path }
        func handledMoreSpecifically(_ child: URL) -> Bool {
            let path = child.standardizedFileURL.path
            return sourceRoots.contains { $0 == path || $0.hasPrefix(path + "/") }
        }

        let appPresence = AppPresence()
        let installed = InstalledApps()
        var itemsByKind: [CategoryKind: [CleanItem]] = [:]
        let total = max(sources.count, 1)

        var lastReport = Date.distantPast
        func report(_ fraction: Double, _ path: String) {
            let now = Date()
            if now.timeIntervalSince(lastReport) >= 0.05 { // coalesce to ~20/sec
                lastReport = now
                progress(min(max(fraction, 0), 1), abbreviate(path))
            }
        }

        func bucket(_ item: CleanItem, defaultKind: CategoryKind) {
            let kind: CategoryKind = item.isLeftover ? .leftovers : defaultKind
            itemsByKind[kind, default: []].append(item)
        }

        for (i, source) in sources.enumerated() {
            if isCancelled() { throw CancellationError() }
            let base = Double(i) / Double(total)
            let children = source.enumerateChildren ? topLevelChildren(of: source.url) : [source.url]
            let childCount = max(children.count, 1)

            for (j, child) in children.enumerated() {
                if isCancelled() { throw CancellationError() }
                report(base + (Double(j) / Double(childCount)) / Double(total), child.path)

                if source.enumerateChildren, handledMoreSpecifically(child) { continue }

                // Irreplaceable stores are surfaced reveal-only, before any trashable classification.
                if ScanSources.isRevealOnly(child) {
                    if let item = makeRevealOnlyItem(at: child, source: source, isCancelled: isCancelled) {
                        bucket(item, defaultKind: source.kind)
                    }
                    continue
                }

                if source.surfaceAll {
                    // App data: surface the folder + split out nested VM payloads.
                    for item in makeAppDataItems(at: child, source: source,
                                                 appPresence: appPresence, installed: installed,
                                                 isCancelled: isCancelled) {
                        bucket(item, defaultKind: source.kind)
                    }
                } else {
                    let item: CleanItem?
                    switch source.kind {
                    case .iosBackups: item = makeBackupItem(at: child, source: source, isCancelled: isCancelled)
                    case .downloads:  item = makeDownloadItem(at: child, source: source, isCancelled: isCancelled)
                    default:          item = makeItem(at: child, source: source,
                                                      appPresence: appPresence, isCancelled: isCancelled)
                    }
                    if let item { bucket(item, defaultKind: source.kind) }
                }
            }
        }

        // Time Machine local snapshots (listed via tmutil — see localSnapshotItems).
        if isCancelled() { throw CancellationError() }
        let snapshots = localSnapshotItems()
        if !snapshots.isEmpty { itemsByKind[.localSnapshots, default: []].append(contentsOf: snapshots) }

        progress(1.0, "")

        // Fixed CategoryKind order; ScanModel re-sorts everything largest-first.
        return CategoryKind.allCases.compactMap { kind in
            guard let items = itemsByKind[kind], !items.isEmpty else { return nil }
            return Category(kind: kind, items: items)
        }
    }

    // MARK: - App-data folder → parent item + nested VM items (BUG 1 + BUG 2)

    /// Surfaces a top-level app-data folder as ACTIVE/leftover data, plus a separate item for
    /// each large nested VM / disk-image payload. VM bytes are subtracted from the parent to
    /// avoid double-counting; a parent that drops below the floor is dropped in favor of the VMs.
    private nonisolated static func makeAppDataItems(
        at url: URL,
        source: ScanSource,
        appPresence: AppPresence,
        installed: InstalledApps,
        isCancelled: () -> Bool
    ) -> [CleanItem] {
        guard ScanSources.isAllowed(url) else {
            assertionFailure("Scanner reached a path outside the allowlist: \(url.path)")
            return []
        }
        let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey, .nameKey])
        if rv?.isSymbolicLink == true { return [] }
        let rawName = rv?.name ?? url.lastPathComponent
        let modified = rv?.contentModificationDate ?? Date(timeIntervalSince1970: 0)

        let folderTotal = size(of: url, isCancelled: isCancelled)

        let cls = classify(rawName: rawName, appPresence: appPresence, installed: installed)
        let appName = cls.owner ?? prettyName(rawName, kind: source.kind)

        // Find & split out nested VM / disk-image payloads.
        let payloads = findVMPayloads(in: url, isCancelled: isCancelled)
        var vmItems: [CleanItem] = []
        var vmBytes: Int64 = 0
        for payload in payloads {
            if isCancelled() { break }
            guard ScanSources.isAllowed(payload) else { continue }
            let size = size(of: payload, isCancelled: isCancelled)
            guard size >= vmFloor else { continue }
            vmBytes += size
            let pMod = (try? payload.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? modified
            let copy = ScanCopy.vmImage(app: appName)
            let name = payloads.count > 1
                ? "\(appName) — \(payload.lastPathComponent)"
                : "\(appName) — virtual machine"
            vmItems.append(CleanItem(
                name: name, explanation: copy.explanation, detail: copy.detail,
                bytes: size, safety: .caution, url: payload, lastModified: pMod,
                owner: appName, badge: .virtualMachine))
        }

        var items = vmItems

        // Parent (folder minus the extracted VM payloads).
        let remaining = folderTotal - vmBytes
        if remaining >= sizeFloor {
            let critical = isCriticalData(rawName)
            let copy = ScanCopy.appData(app: appName, badge: cls.badge, unverified: cls.unverified)
            let detail = critical
                ? copy.detail + "\n\nThis may hold irreplaceable data (such as iCloud files or device backups) that can't be re-downloaded. Swept moves it to the Trash, so you can restore it, but review carefully first."
                : copy.detail
            let parent = CleanItem(
                name: prettyName(rawName, kind: source.kind),
                explanation: copy.explanation, detail: detail,
                bytes: remaining, safety: cls.safety, url: url, lastModified: modified,
                owner: cls.owner, badge: cls.badge, isCritical: critical)
            items.insert(parent, at: 0)
        }
        return items
    }

    /// Classifies an app-data folder by its owning app.
    private nonisolated static func classify(
        rawName: String, appPresence: AppPresence, installed: InstalledApps
    ) -> (badge: ItemBadge, safety: Safety, owner: String?, unverified: Bool) {
        if let candidate = candidateBundleID(name: rawName, kind: .applicationSupport) {
            if isOrphanApp(bundleID: candidate, appPresence: appPresence) {
                return (.leftover, .caution, nil, false) // owning app uninstalled
            }
            let owner = appDisplayName(forBundleID: candidate) ?? candidate
            return (.inUse, .careful, owner, false)       // installed / system component
        }
        // Plain name (e.g. "Claude").
        if let match = installed.match(folderName: rawName) {
            return (.inUse, .careful, match, false)       // resolved to an installed app
        }
        return (.inUse, .careful, nil, true)              // sizable, owner unverified — surface, don't drop
    }

    // MARK: - VM / disk-image detection (BUG 2)

    /// Returns URLs of VM / disk-image payloads inside `folder` (bounded depth). A payload is:
    /// a bare image file; a `.sparsebundle` package; or a `.bundle` package that wraps an image.
    private nonisolated static func findVMPayloads(in folder: URL, isCancelled: () -> Bool) -> [URL] {
        var payloads: [URL] = []

        func walk(_ dir: URL, _ depth: Int) {
            if depth > vmSearchDepth || isCancelled() { return }
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [])) ?? []
            for entry in entries {
                let rv = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if rv?.isSymbolicLink == true { continue }
                let ext = entry.pathExtension.lowercased()
                if rv?.isDirectory == true {
                    if ext == "sparsebundle" {
                        payloads.append(entry)          // disk-image package
                    } else if ext == "bundle", bundleWrapsImage(entry) {
                        payloads.append(entry)          // VM bundle (e.g. claudevm.bundle) — don't descend
                    } else {
                        walk(entry, depth + 1)          // ordinary directory — recurse
                    }
                } else if imageExtensions.contains(ext) {
                    payloads.append(entry)              // bare image file
                }
            }
        }

        walk(folder, 1)
        return payloads
    }

    /// True if a `.bundle` package contains any image file (so it's a VM bundle, not just any bundle).
    private nonisolated static func bundleWrapsImage(_ bundle: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: bundle, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return false }
        for case let file as URL in enumerator {
            if imageExtensions.contains(file.pathExtension.lowercased()) { return true }
        }
        return false
    }

    // MARK: - One item (non-surfaceAll roots: Xcode, Caches, dev tools, logs, saved state)

    private nonisolated static func makeItem(
        at url: URL,
        source: ScanSource,
        appPresence: AppPresence,
        isCancelled: () -> Bool
    ) -> CleanItem? {
        guard ScanSources.isAllowed(url) else {
            assertionFailure("Scanner reached a path outside the allowlist: \(url.path)")
            return nil
        }

        let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey, .nameKey])
        if rv?.isSymbolicLink == true { return nil } // never follow symlinks out of a root
        let rawName = rv?.name ?? url.lastPathComponent
        let modified = rv?.contentModificationDate ?? Date(timeIntervalSince1970: 0)

        let bytes = size(of: url, isCancelled: isCancelled)
        guard bytes >= sizeFloor else { return nil }

        var safety = source.safety
        var badge: ItemBadge?
        let candidate = candidateBundleID(name: rawName, kind: source.kind)

        if leftoverEligible.contains(source.kind),
           let candidate, isOrphanApp(bundleID: candidate, appPresence: appPresence) {
            safety = .caution
            badge = .leftover
        }

        let isLeftover = badge == .leftover
        let effectiveKind: CategoryKind = isLeftover ? .leftovers : source.kind
        let displayName = wholeFolderName(for: source.kind) ?? prettyName(rawName, kind: source.kind)
        let copy = ScanCopy.text(kind: effectiveKind, name: displayName, isLeftover: isLeftover)
        let owner = resolveOwner(url: url, bundleID: candidate, appInstalled: !isLeftover)

        return CleanItem(
            name: displayName, explanation: copy.explanation, detail: copy.detail,
            bytes: bytes, safety: safety, url: url, lastModified: modified,
            owner: owner, badge: badge,
            ownership: source.ownership, deletionKind: source.deletionKind)
    }

    /// Friendly name for single-item ("whole folder") sources, where the folder name itself
    /// (e.g. ".Trash") wouldn't read well.
    private nonisolated static func wholeFolderName(for kind: CategoryKind) -> String? {
        switch kind {
        case .trash: "Items in the Trash"
        case .mailAttachments: "Mail Downloads"
        default: nil
        }
    }

    // MARK: - Reveal-only stores (shown, never trashable)

    /// Shown regardless of the size floor so the user can see Swept found and protected it.
    private nonisolated static func makeRevealOnlyItem(
        at url: URL, source: ScanSource, isCancelled: () -> Bool
    ) -> CleanItem? {
        let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey, .nameKey])
        if rv?.isSymbolicLink == true { return nil }
        let rawName = rv?.name ?? url.lastPathComponent
        let name = prettyName(rawName, kind: source.kind)
        let copy = ScanCopy.revealOnly(name: name)
        return CleanItem(
            name: name, explanation: copy.explanation, detail: copy.detail,
            bytes: size(of: url, isCancelled: isCancelled), safety: .careful, url: url,
            lastModified: rv?.contentModificationDate ?? Date(timeIntervalSince1970: 0),
            owner: nil, badge: nil, isCritical: true,
            ownership: source.ownership, deletionKind: .revealOnly)
    }

    // MARK: - iOS backups (device name + last-backup date from each backup's Info.plist)

    private nonisolated static func makeBackupItem(
        at url: URL, source: ScanSource, isCancelled: () -> Bool
    ) -> CleanItem? {
        guard ScanSources.isAllowed(url) else {
            assertionFailure("Scanner reached a path outside the allowlist: \(url.path)")
            return nil
        }
        let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey])
        if rv?.isSymbolicLink == true { return nil }
        let bytes = size(of: url, isCancelled: isCancelled)
        guard bytes >= sizeFloor else { return nil }

        let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist"))
        let device = (info?["Device Name"] as? String) ?? url.lastPathComponent
        let lastBackup = info?["Last Backup Date"] as? Date
        let modified = lastBackup ?? rv?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        let copy = ScanCopy.iosBackup(device: device, date: lastBackup)

        return CleanItem(
            name: device,
            explanation: copy.explanation,
            detail: copy.detail,
            bytes: bytes, safety: source.safety, url: url, lastModified: modified,
            owner: "Finder", badge: nil, isCritical: true,
            ownership: source.ownership, deletionKind: source.deletionKind)
    }

    // MARK: - Downloads (last-opened date via contentAccessDateKey)

    private nonisolated static func makeDownloadItem(
        at url: URL, source: ScanSource, isCancelled: () -> Bool
    ) -> CleanItem? {
        guard ScanSources.isAllowed(url) else {
            assertionFailure("Scanner reached a path outside the allowlist: \(url.path)")
            return nil
        }
        let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .nameKey,
                                                   .contentAccessDateKey, .contentModificationDateKey,
                                                   .addedToDirectoryDateKey, .creationDateKey])
        if rv?.isSymbolicLink == true { return nil }
        let name = rv?.name ?? url.lastPathComponent
        let bytes = size(of: url, isCancelled: isCancelled)
        guard bytes >= sizeFloor else { return nil }

        // Last-opened drives the row's "Last opened …" caption; the download date (when it landed
        // in Downloads) drives the explanation copy.
        let lastOpened = rv?.contentAccessDate ?? rv?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        let downloadedOn = rv?.addedToDirectoryDate ?? rv?.creationDate ?? rv?.contentModificationDate
        let copy = ScanCopy.downloadFile(downloadedOn: downloadedOn)
        return CleanItem(
            name: name,
            explanation: copy.explanation,
            detail: copy.detail,
            bytes: bytes, safety: source.safety, url: url, lastModified: lastOpened,
            owner: "You", badge: nil,
            ownership: source.ownership, deletionKind: source.deletionKind)
    }

    // MARK: - Time Machine local snapshots

    /// Lists APFS local Time Machine snapshots.
    ///
    /// `tmutil` is the only subprocess in the whole app — used here READ-ONLY
    /// (`listlocalsnapshots`) and, for deletion, in ScanModel (`deletelocalsnapshots`). There is
    /// no public API and no filesystem path to enumerate/remove local snapshots (a snapshot can't
    /// be moved to the Trash), so shelling out to `tmutil` is the only option. This call never
    /// mutates anything.
    ///
    /// Per-snapshot size isn't available from the listing — snapshots share storage — so `bytes`
    /// is 0; removing one reclaims purgeable space that the listing can't attribute per item.
    private nonisolated static func localSnapshotItems() -> [CleanItem] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var items: [CleanItem] = []
        for line in output.split(separator: "\n") {
            let name = line.trimmingCharacters(in: .whitespaces)
            guard let date = snapshotDate(from: name) else { continue }
            let copy = ScanCopy.text(kind: .localSnapshots, name: "", isLeftover: false)
            items.append(CleanItem(
                name: "Snapshot · \(date.formatted(date: .abbreviated, time: .shortened))",
                explanation: copy.explanation,
                detail: copy.detail,
                bytes: 0, // not available from the listing; deletion frees purgeable space
                safety: .caution,
                url: URL(fileURLWithPath: "/"),
                lastModified: date,
                owner: "Time Machine", badge: nil,
                ownership: .systemJunk, deletionKind: .permanent))
        }
        return items
    }

    /// Parses the date from a snapshot name like `com.apple.TimeMachine.2026-07-07-091423.local`.
    private nonisolated static func snapshotDate(from name: String) -> Date? {
        guard name.hasPrefix("com.apple.TimeMachine.") else { return nil }
        var stamp = name.replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
        if let dot = stamp.firstIndex(of: ".") { stamp = String(stamp[..<dot]) } // drop trailing ".local"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.date(from: stamp)
    }

    // MARK: - Sizing (recursive allocated size, matching Finder)

    private nonisolated static func size(of url: URL, isCancelled: () -> Bool) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey,
            .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey
        ]

        // A plain file: size it directly.
        if let rv = try? url.resourceValues(forKeys: keys), rv.isRegularFile == true {
            return Int64(rv.fileAllocatedSize ?? rv.totalFileAllocatedSize ?? rv.fileSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [], // include hidden so totals match Finder
            errorHandler: { _, _ in true } // skip unreadable entries, keep going
        ) else { return 0 }

        var total: Int64 = 0
        var counter = 0
        for case let child as URL in enumerator {
            counter += 1
            if counter & 0x1FF == 0, isCancelled() { break }
            guard let rv = try? child.resourceValues(forKeys: keys) else { continue }
            if rv.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if rv.isRegularFile == true {
                total += Int64(rv.fileAllocatedSize ?? rv.totalFileAllocatedSize ?? rv.fileSize ?? 0)
            }
        }
        return total
    }

    // MARK: - Small helpers

    private nonisolated static func topLevelChildren(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .nameKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    /// Conservative orphan test: a bundle id is an orphan only if it isn't a known
    /// tool/system namespace AND neither it nor any ancestor prefix is an installed app.
    private nonisolated static func isOrphanApp(bundleID: String, appPresence: AppPresence) -> Bool {
        if nonAppNamespaces.contains(where: { bundleID.hasPrefix($0) }) { return false }
        var components = bundleID.split(separator: ".").map(String.init)
        while components.count >= 2 {
            if appPresence.isInstalled(bundleID: components.joined(separator: ".")) { return false }
            components.removeLast()
        }
        return true
    }

    /// Display name of the installed app for a bundle id (or an ancestor prefix), if any.
    private nonisolated static func appDisplayName(forBundleID id: String) -> String? {
        var components = id.split(separator: ".").map(String.init)
        while components.count >= 2 {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: components.joined(separator: ".")) {
                return FileManager.default.displayName(atPath: url.path)
            }
            components.removeLast()
        }
        return nil
    }

    private nonisolated static func candidateBundleID(name: String, kind: CategoryKind) -> String? {
        var id = name
        if kind == .savedAppState, id.hasSuffix(".savedState") {
            id = String(id.dropLast(".savedState".count))
        }
        return looksLikeBundleID(id) ? id : nil
    }

    private nonisolated static func looksLikeBundleID(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    private nonisolated static func prettyName(_ name: String, kind: CategoryKind) -> String {
        if kind == .savedAppState, name.hasSuffix(".savedState") {
            return String(name.dropLast(".savedState".count))
        }
        return name
    }

    private nonisolated static func resolveOwner(url: URL, bundleID: String?, appInstalled: Bool) -> String? {
        if let bundleID, appInstalled, let name = appDisplayName(forBundleID: bundleID) {
            return name
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.ownerAccountName] as? String
    }

    /// Collapse the user's home prefix to "~" for display.
    private nonisolated static func abbreviate(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
