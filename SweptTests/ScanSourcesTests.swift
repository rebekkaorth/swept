//
//  ScanSourcesTests.swift
//  SweptTests
//
//  The allowlist is the last line of defence before anything is moved to the Trash.
//  These tests pin down what `ScanSources.isAllowed` accepts and refuses.
//

import Foundation
import Testing
@testable import Swept

@Suite("ScanSources.isAllowed")
struct ScanSourcesTests {

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private static func homeURL(_ relative: String) -> URL {
        home.appendingPathComponent(relative)
    }

    // MARK: - Inside the allowlist

    @Test("Every allowlist root is itself allowed")
    func rootsAreAllowed() {
        for source in ScanSources.all {
            #expect(ScanSources.isAllowed(source.url), "\(source.url.path)")
        }
    }

    @Test("Paths inside allowlisted roots are allowed", arguments: [
        "Library/Developer/Xcode/DerivedData/MyApp-abcdef",
        "Library/Caches/com.example.app",
        "Library/Caches/com.example.app/nested/deep/file.bin",
        "Library/Logs/DiagnosticReports/crash.ips",
        "Library/Saved Application State/com.example.app.savedState",
        "Library/Application Support/SomeApp",
        "Library/Containers/com.example.app/Data",
        "Library/Group Containers/group.com.example",
        "Library/Application Support/MobileSync/Backup/0000-0000",
        "Downloads/installer.dmg",
        ".npm/_cacache",
        ".Trash/old.txt",
    ])
    func insideIsAllowed(_ relative: String) {
        #expect(ScanSources.isAllowed(Self.homeURL(relative)))
    }

    @Test("Absolute system roots resolve and allow their children")
    func absoluteRootsAllowChildren() {
        #expect(ScanSources.isAllowed(URL(fileURLWithPath: "/var/log/system.log")))
        #expect(ScanSources.isAllowed(URL(fileURLWithPath: "/private/var/log/system.log")))
        #expect(ScanSources.isAllowed(URL(fileURLWithPath: "/var/db/diagnostics/Persist")))
    }

    // MARK: - Outside the allowlist

    @Test("Paths outside the allowlist are refused", arguments: [
        "/",
        "/System",
        "/Applications",
        "/Users",
        "/var",
        "/var/db",
        "/private/var",
        "/tmp",
    ])
    func absoluteOutsideIsRefused(_ path: String) {
        #expect(!ScanSources.isAllowed(URL(fileURLWithPath: path)))
    }

    @Test("Home-relative paths outside the allowlist are refused", arguments: [
        "",
        "Documents",
        "Documents/taxes.pdf",
        "Desktop",
        "Pictures",
        "Library",
        "Library/Preferences",
        "Library/Developer",
        "Library/Developer/Xcode",
    ])
    func homeOutsideIsRefused(_ relative: String) {
        let url = relative.isEmpty ? Self.home : Self.homeURL(relative)
        #expect(!ScanSources.isAllowed(url))
    }

    @Test("A sibling sharing a root's name prefix is refused", arguments: [
        "Library/CachesEvil",
        "Library/Caches-backup/file",
        "Downloads2",
        "Library/LogsArchive",
    ])
    func prefixSiblingIsRefused(_ relative: String) {
        #expect(!ScanSources.isAllowed(Self.homeURL(relative)))
    }

    @Test("`..` traversal out of an allowlisted root is refused", arguments: [
        "Library/Caches/../../Documents",
        "Library/Caches/../Preferences/com.apple.finder.plist",
        "Downloads/../Documents/secret.txt",
        "Library/Caches/com.example/../../../Desktop",
    ])
    func dotDotTraversalIsRefused(_ relative: String) {
        let url = URL(fileURLWithPath: Self.home.path + "/" + relative)
        #expect(!ScanSources.isAllowed(url))
    }

    @Test("`..` that stays inside a root is still allowed")
    func dotDotWithinRootIsAllowed() {
        let url = URL(fileURLWithPath: Self.home.path + "/Library/Caches/a/../b")
        #expect(ScanSources.isAllowed(url))
    }

    @Test("A symlink inside an allowlisted root that points outside is refused")
    func symlinkEscapeIsRefused() throws {
        let fm = FileManager.default
        let outside = fm.temporaryDirectory
            .appendingPathComponent("SweptTests-outside-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }

        let link = Self.homeURL("Library/Caches/SweptTests-link-\(UUID().uuidString)")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        defer { try? fm.removeItem(at: link) }

        let file = outside.appendingPathComponent("file.txt")
        try Data("x".utf8).write(to: file)

        #expect(!ScanSources.isAllowed(link))
        #expect(!ScanSources.isAllowed(link.appendingPathComponent("file.txt")))
    }

    /// `resolvedPath` resolves the closest existing ancestor, so a not-yet-existing child
    /// of an escaping symlink resolves outside the root too.
    @Test("A missing child of an escaping symlink is refused")
    func symlinkEscapeToMissingChild() throws {
        let fm = FileManager.default
        let outside = fm.temporaryDirectory
            .appendingPathComponent("SweptTests-outside-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }

        let link = Self.homeURL("Library/Caches/SweptTests-link-\(UUID().uuidString)")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        defer { try? fm.removeItem(at: link) }

        #expect(!ScanSources.isAllowed(link.appendingPathComponent("missing.txt")))
        #expect(!ScanSources.isAllowed(link.appendingPathComponent("missing/deeper.txt")))
    }

    @Test("A symlink outside the allowlist that points inside is allowed")
    func symlinkIntoRootIsAllowed() throws {
        let fm = FileManager.default
        let link = fm.temporaryDirectory
            .appendingPathComponent("SweptTests-in-\(UUID().uuidString)")
        try fm.createSymbolicLink(at: link, withDestinationURL: Self.homeURL("Library/Caches"))
        defer { try? fm.removeItem(at: link) }

        #expect(ScanSources.isAllowed(link))
    }

    // MARK: - Reveal-only denylist

    /// Irreplaceable stores that must never be trashable. These all live outside the
    /// allowlisted roots today, so `isAllowed` refuses them.
    @Test("Reveal-only stores outside the allowlist are refused", arguments: [
        "Library/Mail",
        "Library/Mail/V10/MailData/Envelope Index",
        "Library/Messages",
        "Library/Messages/chat.db",
        "Pictures/Photos Library.photoslibrary",
        "Library/Keychains",
        "Library/Keychains/login.keychain-db",
        "Library/Mobile Documents",
        "Library/Mobile Documents/com~apple~CloudDocs/file.pages",
    ])
    func revealOnlyIsRefused(_ relative: String) {
        #expect(!ScanSources.isAllowed(Self.homeURL(relative)))
    }

    @Test("System TCC database is refused")
    func systemTCCIsRefused() {
        #expect(!ScanSources.isAllowed(URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")))
    }

    /// These sit *inside* allowlisted roots, so only the denylist refuses them.
    @Test("Reveal-only stores nested in allowlisted roots are refused", arguments: [
        "Library/Application Support/com.apple.TCC",
        "Library/Application Support/com.apple.TCC/TCC.db",
        "Library/Application Support/COM.APPLE.TCC/TCC.db",
        "Downloads/Old Photos.photoslibrary",
        "Downloads/archive/Photos Library.photoslibrary/database/Photos.sqlite",
    ])
    func nestedRevealOnlyIsRefused(_ relative: String) {
        #expect(ScanSources.isRevealOnly(Self.homeURL(relative)))
        #expect(!ScanSources.isAllowed(Self.homeURL(relative)))
    }

    @Test("Every reveal-only store is flagged reveal-only", arguments: [
        "Library/Mail/V10",
        "Library/Messages/chat.db",
        "Library/Keychains/login.keychain-db",
        "Library/Mobile Documents/com~apple~CloudDocs",
        "Pictures/Photos Library.photoslibrary",
    ])
    func revealOnlyIsFlagged(_ relative: String) {
        #expect(ScanSources.isRevealOnly(Self.homeURL(relative)))
    }

    @Test("Names that only resemble a reveal-only store stay allowed", arguments: [
        "Library/Application Support/com.apple.TCC-notes",
        "Library/Caches/com.apple.Mail",
        "Downloads/photoslibrary-export.zip",
    ])
    func lookalikesAreAllowed(_ relative: String) {
        #expect(!ScanSources.isRevealOnly(Self.homeURL(relative)))
        #expect(ScanSources.isAllowed(Self.homeURL(relative)))
    }

    @Test("A symlink inside an allowlisted root that points at a reveal-only store is refused")
    func symlinkToRevealOnlyIsRefused() throws {
        let fm = FileManager.default
        let library = fm.temporaryDirectory
            .appendingPathComponent("SweptTests-\(UUID().uuidString).photoslibrary", isDirectory: true)
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: library) }

        let link = Self.homeURL("Library/Caches/SweptTests-link-\(UUID().uuidString)")
        try fm.createSymbolicLink(at: link, withDestinationURL: library)
        defer { try? fm.removeItem(at: link) }

        #expect(ScanSources.isRevealOnly(link))
        #expect(!ScanSources.isAllowed(link.appendingPathComponent("database")))
    }
}
