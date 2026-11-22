//
//  ScanCopy.swift
//  Swept
//
//  Honest, calm one-liner + detail per category. Matches the MockData tone.
//

import Foundation

enum ScanCopy {
    /// The exact required leftover explanation (mirrors MockData.leftoverExplanation).
    static let leftoverExplanation = "Leftover — the app that created this is no longer installed."

    static func text(kind: CategoryKind, name: String, isLeftover: Bool) -> (explanation: String, detail: String) {
        if isLeftover {
            return (leftoverExplanation,
                    "These files were left behind by “\(name)”, which is no longer installed on this Mac. They're safe to move to the Trash unless you plan to reinstall the app and keep its data.")
        }
        switch kind {
        case .xcodeSimulators:
            return ("Xcode build data that regenerates on the next build.",
                    "Xcode created this while building or running your projects. It's rebuilt automatically the next time you build, so removing it only costs a one-time rebuild.")
        case .appCaches:
            return ("Cached data for \(name) that rebuilds as you use it.",
                    "“\(name)” stores cached files here to load faster. Clearing it frees space and the app repopulates what it needs on demand.")
        case .developerToolCaches:
            return ("Downloaded packages and build caches.",
                    "A cache used by a developer tool to speed up repeat installs and builds. It's re-downloaded or rebuilt automatically when needed.")
        case .applicationSupport:
            return ("Application support data.",
                    "Support files stored by an app. Review before removing — some of this may hold settings you still want.")
        case .logs:
            return ("Diagnostic and log files.",
                    "Logs written by the system or apps. They're useful for troubleshooting but safe to clear when you no longer need them.")
        case .savedAppState:
            return ("Saved window and document state for \(name).",
                    "macOS saved this app's window layout and open documents so it can restore them. Clearing it just means the app reopens fresh.")
        case .leftovers:
            return (leftoverExplanation,
                    "Files left behind by an app that is no longer installed.")
        case .trash:
            return ("Files you've already deleted, waiting to be emptied.",
                    "Emptying the Trash removes these permanently — they aren't moved anywhere else, so this can't be undone.")
        case .iosBackups:
            return iosBackup(device: name, date: nil) // generic; scanner passes device + date
        case .mailAttachments:
            return ("Attachments Mail has downloaded — re-downloaded from the server when opened again.",
                    "Mail keeps local copies of attachments you've opened. Removing them frees space; Mail fetches them from the server again the next time you open the message.")
        case .localSnapshots:
            return ("Hourly Time Machine safety copies. macOS thins them automatically; deleting frees space now but removes those restore points.",
                    "These are local Time Machine snapshots kept on your disk between backups. macOS removes them over time on its own — deleting one now frees space immediately but permanently removes that restore point, and it can't be moved to the Trash.")
        case .downloads:
            return downloadFile(downloadedOn: nil) // generic; scanner passes the download date
        }
    }

    /// Copy for an iOS device backup (device name + backup date from Info.plist).
    static func iosBackup(device: String, date: Date?) -> (explanation: String, detail: String) {
        let explanation: String
        if let date {
            explanation = "A backup of ‘\(device)’ from \(date.formatted(date: .abbreviated, time: .omitted))."
        } else {
            explanation = "A backup of ‘\(device)’."
        }
        return (explanation,
                "You only need this to restore \(device). If \(device) still syncs with this Mac, a fresh backup is created the next time you connect it.")
    }

    /// Copy for a file in the user's Downloads (download date via the file's added/created date).
    static func downloadFile(downloadedOn date: Date?) -> (explanation: String, detail: String) {
        let explanation = date.map { "A file you downloaded on \($0.formatted(date: .abbreviated, time: .omitted))." }
            ?? "A file you downloaded."
        return (explanation,
                "This is your own file. Swept only moves it to the Trash — nothing is deleted permanently.")
    }

    /// Copy for a surfaced app-data folder (Application Support / Containers / Group Containers).
    static func appData(app: String, badge: ItemBadge, unverified: Bool)
        -> (explanation: String, detail: String) {
        if badge == .leftover {
            return (leftoverExplanation,
                    "These files were left behind by “\(app)”, which is no longer installed on this Mac. They're safe to move to the Trash unless you plan to reinstall the app and keep its data.")
        }
        if unverified {
            return ("App data — Swept couldn't confirm the owning app.",
                    "This is sizable app data that Swept couldn't confidently attribute to an installed app. Review before deleting: removing it frees space but may reset whichever app owns it to a fresh state.")
        }
        return ("Data stored by \(app).",
                "This is \(app)'s application data — settings, saved state, and support files. Deleting it frees space but resets \(app) to a fresh state; it will rebuild what it needs on next launch.")
    }

    /// Copy for a reveal-only store (Mail, Messages, Photos, Keychains, TCC, iCloud Drive).
    static func revealOnly(name: String) -> (explanation: String, detail: String) {
        ("Protected — Swept can show this but never removes it.",
         "“\(name)” holds data that can't be recreated, such as mail, messages, photos, passwords, privacy permissions, or iCloud Drive files. Swept never moves it to the Trash. To manage it, use the app that owns it, or reveal it in Finder.")
    }

    /// Copy for a nested virtual-machine / disk-image payload.
    static func vmImage(app: String) -> (explanation: String, detail: String) {
        ("Virtual machine disk image for \(app). Deleting it removes the VM's state; \(app) will recreate or re-download it on next use.",
         "This is a virtual-machine disk image created by \(app) — usually the largest part of its data. Deleting it removes the VM's saved state; \(app) will recreate or re-download it on next use.")
    }
}
