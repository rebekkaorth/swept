//
//  FullDiskAccess.swift
//  Swept
//
//  Probe for Full Disk Access. On macOS 26 (Tahoe) FDA is REQUIRED to read other
//  apps' data, so this is the app's gate: without it there is nothing to scan.
//
//  macOS has no API to request or query FDA (Apple recommends trying a protected location
//  and treating "permission denied" as "no access"). So the probe tries to list several
//  folders that macOS only opens with FDA. Any one that opens means access is on; folders
//  that don't exist on this Mac (e.g. Safari never used) are skipped, so a single missing
//  folder can't leave the user stuck on the access screen.
//
//  The result is cached and re-checked whenever the app becomes active.
//

import Foundation

enum FullDiskAccess {
    nonisolated(unsafe) private static var cached: Bool?
    private static let lock = NSLock()

    /// Folders macOS only lets an app list with Full Disk Access (verified on macOS 26).
    static var protectedFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            "Library/Safari",
            "Library/Mail",
            "Library/Messages",
            "Library/Cookies",
            "Library/Suggestions",
            "Library/HomeKit",
            "Library/Metadata/CoreSpotlight",
            "Library/Application Support/com.apple.TCC",
        ].map { home.appendingPathComponent($0) }
        + [URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC")]
    }

    /// Cached grant status. First call probes; later calls reuse the result.
    static func isGranted() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let result = probe(protectedFolders)
        cached = result
        return result
    }

    /// Re-probe (call on activation, since the user may have just granted it).
    static func recheck() {
        lock.lock(); defer { lock.unlock() }
        cached = probe(protectedFolders)
    }

    /// True if any existing folder in `folders` can be listed. Missing folders are skipped.
    /// If none of them exist there's nothing to test against, so access is assumed (better
    /// than trapping the user on the access screen; a scan without access just finds less).
    static func probe(_ folders: [URL]) -> Bool {
        let fm = FileManager.default
        var testedAny = false
        for folder in folders {
            var isDirectory: ObjCBool = false
            // Checking that a folder exists is allowed without FDA; listing its contents isn't.
            guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            testedAny = true
            if (try? fm.contentsOfDirectory(atPath: folder.path)) != nil { return true }
        }
        return !testedAny
    }
}
