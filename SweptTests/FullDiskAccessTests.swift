//
//  FullDiskAccessTests.swift
//  SweptTests
//
//  The Full Disk Access probe, against temporary folders: a locked folder (no permissions)
//  stands in for one macOS protects, a missing path for a folder this Mac doesn't have.
//

import Foundation
import Testing
@testable import Swept

@Suite("FullDiskAccess.probe")
struct FullDiskAccessTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SweptTests.FDA.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func readable(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func locked(_ name: String) throws -> URL {
        let url = try readable(name)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        return url
    }

    private func missing(_ name: String) -> URL { root.appendingPathComponent(name) }

    private func cleanUp() {
        // Unlock first so the temporary folders can be removed.
        if let items = try? FileManager.default.contentsOfDirectory(atPath: root.path) {
            for item in items {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                       ofItemAtPath: root.appendingPathComponent(item).path)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    @Test func allLockedMeansNoAccess() throws {
        defer { cleanUp() }
        #expect(!FullDiskAccess.probe([try locked("Safari"), try locked("Mail")]))
    }

    @Test func oneOpenFolderMeansAccess() throws {
        defer { cleanUp() }
        #expect(FullDiskAccess.probe([try locked("Safari"), try readable("Mail")]))
    }

    @Test func missingFirstFolderDoesNotTrapTheUser() throws {
        defer { cleanUp() }
        // The old probe only looked at Safari: if it was missing, access was never detected.
        #expect(FullDiskAccess.probe([missing("Safari"), try readable("Mail")]))
        #expect(!FullDiskAccess.probe([missing("Safari"), try locked("Mail")]))
    }

    @Test func nothingToTestAssumesAccess() {
        defer { cleanUp() }
        #expect(FullDiskAccess.probe([missing("Safari"), missing("Mail")]))
    }

    @Test func realProtectedFoldersIncludeOneThatAlwaysExists() {
        let systemTCC = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC")
        #expect(FullDiskAccess.protectedFolders.contains(systemTCC))
        #expect(FileManager.default.fileExists(atPath: systemTCC.path))
    }
}
