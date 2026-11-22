//
//  CategoryKind.swift
//  Swept
//
//  The fixed set of clutter categories Swept scans for, in display order.
//

import Foundation

enum CategoryKind: String, CaseIterable, Identifiable, Hashable, Codable {
    case xcodeSimulators
    case appCaches
    case leftovers
    case developerToolCaches
    case applicationSupport
    case logs
    case savedAppState
    case trash
    case iosBackups
    case mailAttachments
    case localSnapshots
    case downloads

    var id: Self { self }

    var title: String {
        switch self {
        case .xcodeSimulators: "Xcode & Simulators"
        case .appCaches: "App Caches"
        case .leftovers: "Leftovers"
        case .developerToolCaches: "Developer Tool Caches"
        case .applicationSupport: "Application Support"
        case .logs: "Logs"
        case .savedAppState: "Saved App State"
        case .trash: "Trash"
        case .iosBackups: "iOS Backups"
        case .mailAttachments: "Mail Attachments"
        case .localSnapshots: "Time Machine Snapshots"
        case .downloads: "Downloads"
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .xcodeSimulators: "hammer"
        case .appCaches: "shippingbox"
        case .leftovers: "trash.slash"
        case .developerToolCaches: "wrench.and.screwdriver"
        case .applicationSupport: "folder"
        case .logs: "doc.text"
        case .savedAppState: "macwindow"
        case .trash: "trash"
        case .iosBackups: "iphone"
        case .mailAttachments: "envelope"
        case .localSnapshots: "clock.arrow.circlepath"
        case .downloads: "arrow.down.circle"
        }
    }
}
