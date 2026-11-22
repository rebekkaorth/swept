//
//  FullDiskAccess.swift
//  Swept
//
//  Probe for Full Disk Access. On macOS 26 (Tahoe) FDA is REQUIRED to read other
//  apps' data, so this is the app's gate: without it there is nothing to scan.
//  The result is cached and re-checked on applicationDidBecomeActive.
//

import Foundation

enum FullDiskAccess {
    nonisolated(unsafe) private static var cached: Bool?
    private static let lock = NSLock()

    /// Cached grant status. First call probes; later calls reuse the result.
    static func isGranted() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let result = probe()
        cached = result
        return result
    }

    /// Re-probe (call on applicationDidBecomeActive, since the user may have just granted it).
    static func recheck() {
        lock.lock(); defer { lock.unlock() }
        cached = probe()
    }

    /// Reading a known-gated location fails without Full Disk Access.
    private static func probe() -> Bool {
        let gated = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari")
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: gated.path)
            return true
        } catch {
            return false
        }
    }
}
