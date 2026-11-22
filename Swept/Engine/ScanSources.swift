//
//  ScanSources.swift
//  Swept
//
//  The HARD-CODED allowlist of filesystem roots Swept is ever permitted to read.
//  This is a READ-ONLY manifest — nothing here is written, moved, or deleted.
//  The scanner refuses to touch any path that is not contained in one of these roots,
//  and reveal-only stores (Mail, Messages, Photos, Keychains, TCC, iCloud Drive) are
//  never trashable even when they sit inside one.
//

import Foundation

struct ScanSource {
    let kind: CategoryKind
    /// Path relative to the user's home directory, or absolute if it begins with "/".
    let relativePath: String
    let safety: Safety
    /// Marks system paths (e.g. /var/log) as opposed to per-user paths. Full Disk Access
    /// is required app-wide before any scan runs, so all sources are reachable here.
    let requiresElevation: Bool
    /// true → each top-level child becomes a CleanItem; false → the root itself is one item.
    let enumerateChildren: Bool
    /// true → surface EVERY sizable child as app data (installed or leftover), and recurse
    /// for nested VM / disk-image payloads. Used for the app-data roots below.
    let surfaceAll: Bool
    /// System clutter vs. the user's own files (user files are never preselected).
    let ownership: Ownership
    /// How items from this source are removed (Trash vs. permanent).
    let deletionKind: DeletionKind

    init(kind: CategoryKind, relativePath: String, safety: Safety,
         requiresElevation: Bool, enumerateChildren: Bool, surfaceAll: Bool = false,
         ownership: Ownership = .systemJunk, deletionKind: DeletionKind = .trashable) {
        self.kind = kind
        self.relativePath = relativePath
        self.safety = safety
        self.requiresElevation = requiresElevation
        self.enumerateChildren = enumerateChildren
        self.surfaceAll = surfaceAll
        self.ownership = ownership
        self.deletionKind = deletionKind
    }

    var url: URL {
        if relativePath.hasPrefix("/") {
            return URL(fileURLWithPath: relativePath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(relativePath, isDirectory: true)
    }
}

enum ScanSources {
    static let all: [ScanSource] = [
        // MARK: Xcode & Simulators
        ScanSource(kind: .xcodeSimulators, relativePath: "Library/Developer/Xcode/DerivedData",
                   safety: .safe, requiresElevation: false, enumerateChildren: true),
        ScanSource(kind: .xcodeSimulators, relativePath: "Library/Developer/CoreSimulator/Caches",
                   safety: .safe, requiresElevation: false, enumerateChildren: true),
        ScanSource(kind: .xcodeSimulators, relativePath: "Library/Developer/CoreSimulator/Devices",
                   safety: .safe, requiresElevation: false, enumerateChildren: true),
        ScanSource(kind: .xcodeSimulators, relativePath: "Library/Developer/Xcode/iOS DeviceSupport",
                   safety: .safe, requiresElevation: false, enumerateChildren: true),
        ScanSource(kind: .xcodeSimulators, relativePath: "Library/Developer/Xcode/Archives",
                   safety: .caution, requiresElevation: false, enumerateChildren: true),

        // MARK: App Caches (per-subfolder)
        ScanSource(kind: .appCaches, relativePath: "Library/Caches",
                   safety: .caution, requiresElevation: false, enumerateChildren: true),

        // MARK: Developer Tool Caches (each is a single known cache → one item)
        ScanSource(kind: .developerToolCaches, relativePath: "Library/Caches/CocoaPods",
                   safety: .safe, requiresElevation: false, enumerateChildren: false),
        ScanSource(kind: .developerToolCaches, relativePath: "Library/Caches/Homebrew",
                   safety: .safe, requiresElevation: false, enumerateChildren: false),
        ScanSource(kind: .developerToolCaches, relativePath: ".npm",
                   safety: .safe, requiresElevation: false, enumerateChildren: false),
        ScanSource(kind: .developerToolCaches, relativePath: ".gradle",
                   safety: .safe, requiresElevation: false, enumerateChildren: false),
        ScanSource(kind: .developerToolCaches, relativePath: "Library/Caches/com.apple.dt.Xcode",
                   safety: .safe, requiresElevation: false, enumerateChildren: false),

        // MARK: Application Support / Containers / Group Containers — installed-app data.
        // surfaceAll: every sizable child is surfaced (active or leftover) and recursed for VMs.
        ScanSource(kind: .applicationSupport, relativePath: "Library/Application Support",
                   safety: .careful, requiresElevation: false, enumerateChildren: true, surfaceAll: true),
        ScanSource(kind: .applicationSupport, relativePath: "Library/Containers",
                   safety: .careful, requiresElevation: false, enumerateChildren: true, surfaceAll: true),
        ScanSource(kind: .applicationSupport, relativePath: "Library/Group Containers",
                   safety: .careful, requiresElevation: false, enumerateChildren: true, surfaceAll: true),

        // MARK: Logs
        ScanSource(kind: .logs, relativePath: "Library/Logs",
                   safety: .safe, requiresElevation: false, enumerateChildren: true),
        ScanSource(kind: .logs, relativePath: "/var/log",
                   safety: .safe, requiresElevation: true, enumerateChildren: false),
        ScanSource(kind: .logs, relativePath: "/var/db/diagnostics",
                   safety: .safe, requiresElevation: true, enumerateChildren: false),

        // MARK: Saved App State
        ScanSource(kind: .savedAppState, relativePath: "Library/Saved Application State",
                   safety: .safe, requiresElevation: false, enumerateChildren: true),

        // MARK: Trash — a single item; emptying is PERMANENT (not a Trash move).
        ScanSource(kind: .trash, relativePath: ".Trash",
                   safety: .caution, requiresElevation: false, enumerateChildren: false,
                   deletionKind: .permanent),

        // MARK: iOS device backups — each child folder is one backup (name/date from Info.plist).
        ScanSource(kind: .iosBackups, relativePath: "Library/Application Support/MobileSync/Backup",
                   safety: .careful, requiresElevation: false, enumerateChildren: true,
                   ownership: .userFiles),

        // MARK: Mail attachment downloads — re-downloadable copies.
        ScanSource(kind: .mailAttachments,
                   relativePath: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
                   safety: .caution, requiresElevation: false, enumerateChildren: false),

        // MARK: Downloads — the user's own files; never preselected.
        ScanSource(kind: .downloads, relativePath: "Downloads",
                   safety: .careful, requiresElevation: false, enumerateChildren: true,
                   ownership: .userFiles),
    ]

    // MARK: - Reveal-only denylist

    /// Irreplaceable stores Swept may SHOW but must never trash, wherever they sit — inside an
    /// allowlisted root or not. Home-relative unless absolute. Each also covers its descendants.
    static let revealOnlyPaths: [String] = [
        "Library/Mail",
        "Library/Messages",
        "Library/Keychains",
        "/Library/Keychains",
        "Library/Application Support/com.apple.TCC",
        "/Library/Application Support/com.apple.TCC",
        "Library/Mobile Documents", // iCloud Drive
    ]

    /// Package extensions that are reveal-only wherever they appear (Photos libraries can live
    /// anywhere, including Downloads).
    static let revealOnlyExtensions: Set<String> = ["photoslibrary"]

    /// Canonicalized (symlink-resolved) reveal-only roots.
    static var revealOnlyRoots: [String] {
        revealOnlyPaths.map { relative in
            let url = relative.hasPrefix("/")
                ? URL(fileURLWithPath: relative, isDirectory: true)
                : FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(relative, isDirectory: true)
            return resolvedPath(url)
        }
    }

    /// True if `url` resolves to (or into) an irreplaceable store. Compared case-insensitively,
    /// because the default APFS volume is case-insensitive and `COM.APPLE.TCC` is the same folder.
    static func isRevealOnly(_ url: URL) -> Bool {
        let path = resolvedPath(url).lowercased()
        let hitsRoot = revealOnlyRoots.contains { root in
            let root = root.lowercased()
            return path == root || path.hasPrefix(root + "/")
        }
        if hitsRoot { return true }
        return path.split(separator: "/").contains { component in
            revealOnlyExtensions.contains((String(component) as NSString).pathExtension)
        }
    }

    // MARK: - Allowlist

    /// Canonicalized (symlink-resolved) allowlist roots.
    static var allowedRoots: [String] {
        all.map { resolvedPath($0.url) }
    }

    /// True only if `url` resolves to a location inside one of the allowlist roots and is not
    /// reveal-only. This gates both scanning and trashing.
    static func isAllowed(_ url: URL) -> Bool {
        if isRevealOnly(url) { return false }
        let path = resolvedPath(url)
        return allowedRoots.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }

    /// Standardizes `url` and resolves symlinks in its closest existing ancestor, then re-appends
    /// the missing tail. `resolvingSymlinksInPath` alone leaves a path untouched when it doesn't
    /// exist, so a missing child of an escaping symlink would otherwise look like it's inside.
    static func resolvedPath(_ url: URL) -> String {
        let fm = FileManager.default
        var ancestor = url.standardizedFileURL
        var tail: [String] = []
        // `attributesOfItem` doesn't follow a final symlink, so a dangling link counts as existing.
        while ancestor.path != "/", (try? fm.attributesOfItem(atPath: ancestor.path)) == nil {
            tail.insert(ancestor.lastPathComponent, at: 0)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath()
        for component in tail { resolved.appendPathComponent(component) }
        return resolved.path
    }
}
