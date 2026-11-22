//
//  CleanItem.swift
//  Swept
//
//  A single reclaimable item found on disk.
//

import Foundation

/// A small qualifier shown as a pill on a row and used for classification.
enum ItemBadge: Hashable {
    case leftover        // owning app is no longer installed
    case inUse           // active data belonging to an installed (or unverified) app
    case virtualMachine  // a VM / disk-image payload extracted from an app's data
}

/// Whether an item is system-generated clutter or the user's own files.
/// User files are never preselected by "select all" and get their own sidebar group.
enum Ownership: Hashable {
    case systemJunk // default — caches, logs, rebuildable data
    case userFiles  // downloads, backups, mail attachments — the user's own content
}

/// How an item is removed.
enum DeletionKind: Hashable {
    case trashable // default — moved to the Trash (recoverable)
    case permanent // cannot go to the Trash (emptying the Trash, deleting local snapshots)
    case revealOnly // irreplaceable store (Mail, Photos, Keychains…) — shown, never removed
}

struct CleanItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    /// One-line summary shown in the list.
    var explanation: String
    /// 2–3 sentence detail shown in the inspector.
    var detail: String
    var bytes: Int64
    var safety: Safety
    var url: URL
    var lastModified: Date
    /// Owning app / tool, if known.
    var owner: String?
    /// Optional pill / classification. `nil` for plain reclaimable items.
    var badge: ItemBadge?
    /// True for items holding potentially irreplaceable data (e.g. iCloud files, device
    /// backups). Still deletable, but the UI requires an extra confirmation before trashing.
    var isCritical: Bool
    /// System clutter vs. the user's own files.
    var ownership: Ownership
    /// How this item is removed (Trash vs. permanent).
    var deletionKind: DeletionKind
    /// True while a delete is running for this item: shown greyed out with a spinner, and its
    /// bytes are already left out of every total. Cleared again if the delete fails.
    var isDeleting = false

    /// True when the app that created this is no longer installed.
    var isLeftover: Bool { badge == .leftover }

    /// True for irreplaceable stores Swept only shows: no checkbox, no Trash action.
    var isRevealOnly: Bool { deletionKind == .revealOnly }

    init(
        id: UUID = UUID(),
        name: String,
        explanation: String,
        detail: String,
        bytes: Int64,
        safety: Safety,
        url: URL,
        lastModified: Date,
        owner: String? = nil,
        badge: ItemBadge? = nil,
        isCritical: Bool = false,
        ownership: Ownership = .systemJunk,
        deletionKind: DeletionKind = .trashable
    ) {
        self.id = id
        self.name = name
        self.explanation = explanation
        self.detail = detail
        self.bytes = bytes
        self.safety = safety
        self.url = url
        self.lastModified = lastModified
        self.owner = owner
        self.badge = badge
        self.isCritical = isCritical
        self.ownership = ownership
        self.deletionKind = deletionKind
    }
}
