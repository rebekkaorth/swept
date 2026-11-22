//
//  MockData.swift
//  Swept
//
//  Realistic sample dataset for building/previewing the UI before the real
//  scan engine exists. Sums to 87.4 GB reclaimable of 128 GB System Data.
//
//  NOTE: numbers match the values called out in the spec; exact parity with the
//  Swept.dc.html prototype pending that file being added to the repo.
//

import Foundation

extension ScanModel {
    /// A fully-populated model for previews and UI development.
    static var mock: ScanModel {
        ScanModel(categories: MockData.categories, totalSystemData: MockData.totalSystemData)
    }
}

private let GB: Int64 = 1_000_000_000
private let day: TimeInterval = 86_400

private func ago(_ days: Double) -> Date {
    Date(timeIntervalSinceNow: -days * day)
}

private func item(
    _ name: String,
    _ explanation: String,
    _ detail: String,
    gb: Double,
    _ safety: Safety,
    _ path: String,
    modified: Double,
    owner: String? = nil,
    badge: ItemBadge? = nil,
    isCritical: Bool = false,
    ownership: Ownership = .systemJunk,
    deletionKind: DeletionKind = .trashable
) -> CleanItem {
    CleanItem(
        name: name,
        explanation: explanation,
        detail: detail,
        bytes: Int64(gb * Double(GB)),
        safety: safety,
        // Safety: append a non-existent "SweptSample" suffix so this mock URL can never
        // resolve to a real file. It stays under an allowlist root (no false asserts), but
        // trashItem would simply no-op if delete were ever triggered from a live preview.
        url: URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .appendingPathComponent("SweptSample-" + name.replacingOccurrences(of: " ", with: "-")),
        lastModified: ago(modified),
        owner: owner,
        badge: badge,
        isCritical: isCritical,
        ownership: ownership,
        deletionKind: deletionKind
    )
}

enum MockData {
    static let leftoverExplanation = "Leftover — the app that created this is no longer installed."

    /// Total System Data footprint the "scan" reports (larger than the reclaimable sum).
    static let totalSystemData: Int64 = 128 * GB

    /// Believable paths the mock scanner "visits" as it runs.
    static let scanPaths: [String] = [
        "~/Library/Developer/Xcode/DerivedData",
        "~/Library/Developer/CoreSimulator/Devices",
        "~/Library/Caches/Google/Chrome",
        "~/Library/Caches/com.spotify.client",
        "~/.npm/_cacache",
        "~/Library/Caches/Homebrew",
        "~/Library/Application Support",
        "~/Library/Logs/DiagnosticReports",
        "~/Library/Saved Application State",
    ]

    static var categories: [Category] {
        [
            Category(kind: .xcodeSimulators, items: [
                item("DerivedData",
                     "Rebuilt automatically the next time you open a project.",
                     "Xcode regenerates DerivedData whenever it builds. Removing it forces a one-time clean build but reclaims a large amount of space and often fixes stale-index issues.",
                     gb: 18.4, .safe, "~/Library/Developer/Xcode/DerivedData",
                     modified: 1.2, owner: "Xcode"),
                item("iOS 16.2 Simulator",
                     "An older simulator runtime you can re-download from Xcode.",
                     "This is a full iOS 16.2 simulator runtime and its device data. If you no longer test against 16.2 it is safe to remove; Xcode can re-download the runtime on demand.",
                     gb: 11.9, .caution, "~/Library/Developer/CoreSimulator/Devices/iOS-16-2",
                     modified: 41, owner: "Simulator"),
                item("iOS 15.5 Simulator",
                     "An older simulator runtime you can re-download from Xcode.",
                     "A full iOS 15.5 simulator runtime and device data. Safe to remove if you no longer support 15.5; it can be re-downloaded later.",
                     gb: 5.2, .caution, "~/Library/Developer/CoreSimulator/Devices/iOS-15-5",
                     modified: 92, owner: "Simulator"),
                item("Old Archives",
                     "Build archives from past app submissions.",
                     "Xcode keeps an archive each time you distribute a build. Older archives are rarely needed once a version has shipped, but keep any you might still submit or symbolicate.",
                     gb: 3.2, .caution, "~/Library/Developer/Xcode/Archives",
                     modified: 120, owner: "Xcode"),
            ]),

            Category(kind: .appCaches, items: [
                item("Google Chrome",
                     "Cached web content that will rebuild as you browse.",
                     "Chrome stores cached images, scripts and other web assets to speed up page loads. Clearing it frees space and Chrome repopulates it as you browse.",
                     gb: 6.4, .safe, "~/Library/Caches/Google/Chrome",
                     modified: 0.3, owner: "Google Chrome"),
                item("Slack",
                     "Cached messages, images and files.",
                     "Slack caches attachments and images from your workspaces. Removing the cache signs you into nothing new and Slack re-downloads content on demand.",
                     gb: 4.1, .safe, "~/Library/Caches/com.tinyspeck.slackmacgap",
                     modified: 0.5, owner: "Slack"),
                item("Spotify",
                     "Cached audio for offline and recent playback.",
                     "Spotify keeps recently played and downloaded audio here. Clearing it may require re-downloading offline playlists but is otherwise harmless.",
                     gb: 3.8, .safe, "~/Library/Caches/com.spotify.client",
                     modified: 2, owner: "Spotify"),
                item("Figma",
                     "Cached design files and fonts.",
                     "Figma caches document data and fonts for faster loading. It rebuilds automatically the next time you open your files.",
                     gb: 2.5, .safe, "~/Library/Caches/com.figma.Desktop",
                     modified: 1, owner: "Figma"),
            ]),

            Category(kind: .developerToolCaches, items: [
                item("npm cache",
                     "Downloaded package tarballs, re-fetched on demand.",
                     "npm caches every package it downloads so installs are faster offline. It can be cleared safely; npm re-downloads packages as projects need them.",
                     gb: 4.9, .safe, "~/.npm/_cacache",
                     modified: 3, owner: "npm"),
                item("CocoaPods",
                     "Cached pod specs and downloaded sources.",
                     "CocoaPods keeps a cache of downloaded pods and specs. Clearing it triggers a re-download on the next `pod install` but is otherwise safe.",
                     gb: 3.6, .safe, "~/Library/Caches/CocoaPods",
                     modified: 7, owner: "CocoaPods"),
                item("Homebrew downloads",
                     "Cached formula downloads and bottles.",
                     "Homebrew stores downloaded bottles and source archives here. Running `brew cleanup` removes them; Homebrew re-downloads as needed.",
                     gb: 2.4, .safe, "~/Library/Caches/Homebrew",
                     modified: 9, owner: "Homebrew"),
                item("SwiftPM cache",
                     "Cached Swift Package dependencies.",
                     "Swift Package Manager caches resolved dependencies to speed up builds. It is rebuilt automatically the next time a package resolves.",
                     gb: 1.4, .safe, "~/Library/Caches/org.swift.swiftpm",
                     modified: 4, owner: "Swift Package Manager"),
            ]),

            Category(kind: .applicationSupport, items: [
                item("Docker.raw",
                     "Docker's virtual disk image.",
                     "Docker Desktop stores all container and image data in this single disk image. It can grow very large; reclaim space from within Docker rather than deleting outright unless you no longer use Docker.",
                     gb: 5.7, .careful, "~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
                     modified: 0.4, owner: "Docker Desktop"),
                item("Adobe",
                     "Support files and caches for Adobe apps.",
                     "Adobe apps keep support data, presets and caches here. Some of it is regenerated, but presets and settings may live alongside caches, so review before removing.",
                     gb: 3.2, .caution, "~/Library/Application Support/Adobe",
                     modified: 18, owner: "Adobe"),
            ]),

            Category(kind: .leftovers, items: [
                item("Sketch",
                     leftoverExplanation,
                     "These files were created by Sketch, which is no longer installed on this Mac. They are safe to remove unless you plan to reinstall the app and keep its data.",
                     gb: 2.9, .careful, "~/Library/Application Support/com.bohemiancoding.sketch3",
                     modified: 210, owner: "Sketch", badge: .leftover),
                item("Kaleidoscope",
                     leftoverExplanation,
                     "Support data left behind by Kaleidoscope, which is no longer installed. Safe to remove unless you intend to reinstall and reuse its settings.",
                     gb: 2.5, .careful, "~/Library/Application Support/com.blackpixel.kaleidoscope",
                     modified: 260, owner: "Kaleidoscope", badge: .leftover),
            ]),

            Category(kind: .logs, items: [
                item("Diagnostic Reports",
                     "Crash and diagnostic logs from apps.",
                     "macOS and apps write crash reports and diagnostic logs here. They are useful for debugging but safe to clear once you no longer need them.",
                     gb: 1.8, .safe, "~/Library/Logs/DiagnosticReports",
                     modified: 5, owner: "macOS"),
                item("CoreSimulator Logs",
                     "Verbose logs from simulator runs.",
                     "The simulator writes detailed logs during runs. They accumulate over time and are safe to clear between debugging sessions.",
                     gb: 1.3, .safe, "~/Library/Logs/CoreSimulator",
                     modified: 6, owner: "Simulator"),
            ]),

            Category(kind: .savedAppState, items: [
                item("Saved Application State",
                     "Window and document state restored on app launch.",
                     "macOS saves each app's window layout and open documents so they can be restored. Clearing it just means apps reopen to a fresh state.",
                     gb: 2.2, .safe, "~/Library/Saved Application State",
                     modified: 1.5, owner: "macOS"),
            ]),

            // MARK: - Permanent-deletion clutter (cannot go to the Trash)

            Category(kind: .trash, items: [
                item("Items in the Trash",
                     "Files you've already deleted, waiting to be emptied.",
                     "Emptying the Trash removes these permanently — they aren't moved anywhere else, so this can't be undone.",
                     gb: 6.1, .caution, "~/.Trash",
                     modified: 4, owner: "Finder",
                     deletionKind: .permanent),
            ]),

            Category(kind: .localSnapshots, items: [
                item("Snapshot · Jul 7, 09:14",
                     "Hourly Time Machine safety copies. macOS thins them automatically; deleting frees space now but removes those restore points.",
                     "These are local Time Machine snapshots kept on your disk between backups. macOS removes them over time on its own — deleting one now frees space immediately but permanently removes that restore point, and it can't be moved to the Trash.",
                     gb: 8.5, .caution, "/Volumes/.timemachine/local-1",
                     modified: 0.5, owner: "Time Machine",
                     deletionKind: .permanent),
                item("Snapshot · Jul 6, 21:02",
                     "Hourly Time Machine safety copies. macOS thins them automatically; deleting frees space now but removes those restore points.",
                     "These are local Time Machine snapshots kept on your disk between backups. macOS removes them over time on its own — deleting one now frees space immediately but permanently removes that restore point, and it can't be moved to the Trash.",
                     gb: 5.2, .caution, "/Volumes/.timemachine/local-2",
                     modified: 0.9, owner: "Time Machine",
                     deletionKind: .permanent),
            ]),

            // MARK: - User files (never preselected by "select all")

            Category(kind: .iosBackups, items: [
                item("iPhone 15 Pro",
                     "A backup of ‘iPhone 15 Pro’ from Jun 16, 2026.",
                     "You only need this to restore iPhone 15 Pro. If iPhone 15 Pro still syncs with this Mac, a fresh backup is created the next time you connect it.",
                     gb: 12.4, .careful, "~/Library/Application Support/MobileSync/Backup/00008120-A",
                     modified: 22, owner: "Finder",
                     isCritical: true, ownership: .userFiles),
            ]),

            Category(kind: .mailAttachments, items: [
                item("Mail Downloads",
                     "Attachments Mail has downloaded — re-downloaded from the server when opened again.",
                     "Mail keeps local copies of attachments you've opened. Removing them frees space; Mail fetches them from the server again the next time you open the message.",
                     gb: 1.8, .caution, "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
                     modified: 14, owner: "Mail",
                     ownership: .userFiles),
            ]),

            Category(kind: .downloads, items: [
                item("Old installers",
                     "A file you downloaded on Jun 8, 2026.",
                     "This is your own file. Swept only moves it to the Trash — nothing is deleted permanently.",
                     gb: 4.3, .caution, "~/Downloads",
                     modified: 30, owner: "You",
                     ownership: .userFiles),
                item("Screen recordings",
                     "A file you downloaded on Jun 29, 2026.",
                     "This is your own file. Swept only moves it to the Trash — nothing is deleted permanently.",
                     gb: 2.6, .caution, "~/Downloads",
                     modified: 9, owner: "You",
                     ownership: .userFiles),
            ]),
        ]
    }
}
