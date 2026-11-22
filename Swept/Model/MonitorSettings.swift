//
//  MonitorSettings.swift
//  Swept
//
//  Settings for optional background monitoring. Persists to UserDefaults.
//  No networking. BackgroundMonitor owns the schedule; this holds settings + the last snapshot.
//

import Foundation
import Observation

/// A persisted (kind, bytes) pair — a Codable stand-in for the tuple, since tuples aren't Codable.
struct CategorySize: Codable, Hashable, Sendable {
    let kind: CategoryKind
    let bytes: Int64
}

@Observable
final class MonitorSettings {

    /// The one instance shared by the UI, the background monitor, and the app delegate.
    static let shared = MonitorSettings()

    /// Threshold presets offered in the UI (10 / 25 / 50 GB).
    static let thresholdPresets: [Int64] = [10, 25, 50].map { $0 * 1_000_000_000 }

    // MARK: - Persisted settings

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return } // ignore redundant writes (avoid needless login-item churn)
            defaults.set(isEnabled, forKey: Key.isEnabled)
            LoginItem.setEnabled(isEnabled) // launch-at-login tracks monitoring
        }
    }

    /// Transient: true while a background measurement pass is running (drives the menu-bar
    /// "scanning" animation). Not persisted.
    var isChecking: Bool = false

    /// Transient: the path the background pass is currently visiting (shown in the popover).
    var currentPath: String = ""

    /// Transient: true while the main app is running a full scan — the background monitor
    /// defers to it to avoid competing disk I/O. Not persisted.
    var isFullScanRunning: Bool = false

    /// Transient: bumped when the user taps "Review in Swept"; the main window observes it
    /// to focus and start a full scan. Not persisted.
    private(set) var reviewRequestToken: Int = 0

    /// Ask the main window to come forward and run a full scan.
    func requestReview() { reviewRequestToken += 1 }

    /// Transient: bumped to ask the app to bring the main window forward (Dock reopen,
    /// notification tap) — a persistent scene observes it and restores Dock + window. Not persisted.
    private(set) var openWindowToken: Int = 0

    /// Ask the app to restore the Dock icon and show the main window.
    func requestOpenWindow() { openWindowToken += 1 }

    /// Suppress notifications for a week from now.
    func snoozeForAWeek(from now: Date) {
        snoozedUntil = now.addingTimeInterval(7 * 24 * 60 * 60)
    }

    /// Notify when reclaimable rises above this. Default 25 GB.
    var thresholdBytes: Int64 {
        didSet { defaults.set(Int(thresholdBytes), forKey: Key.thresholdBytes) }
    }

    /// Suppress notifications until this date (user chose "snooze").
    var snoozedUntil: Date? {
        didSet { setDate(snoozedUntil, forKey: Key.snoozedUntil) }
    }

    /// When we last posted a notification.
    var lastNotified: Date? {
        didSet { setDate(lastNotified, forKey: Key.lastNotified) }
    }

    // MARK: - Last measurement snapshot

    var lastCheck: Date? {
        didSet { setDate(lastCheck, forKey: Key.lastCheck) }
    }

    var lastReclaimableBytes: Int64 {
        didSet { defaults.set(Int(lastReclaimableBytes), forKey: Key.lastReclaimableBytes) }
    }

    /// Top 3 categories from the last measurement, largest-first.
    var topCategories: [CategorySize] {
        didSet { persistTopCategories() }
    }

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Key.isEnabled) // default false
        self.thresholdBytes = (defaults.object(forKey: Key.thresholdBytes) as? Int).map(Int64.init)
            ?? 25_000_000_000
        self.snoozedUntil = defaults.object(forKey: Key.snoozedUntil) as? Date
        self.lastNotified = defaults.object(forKey: Key.lastNotified) as? Date
        self.lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
        self.lastReclaimableBytes = (defaults.object(forKey: Key.lastReclaimableBytes) as? Int).map(Int64.init) ?? 0
        if let data = defaults.data(forKey: Key.topCategories),
           let decoded = try? JSONDecoder().decode([CategorySize].self, from: data) {
            self.topCategories = decoded
        } else {
            self.topCategories = []
        }
    }

    // MARK: - Recording a measurement

    /// Stores the result of a `sizesOnlyScan()` (keeps only the top 3 categories).
    func record(_ snapshot: SizesSnapshot, at date: Date) {
        lastCheck = date
        lastReclaimableBytes = snapshot.total
        topCategories = snapshot.byCategory
            .map { CategorySize(kind: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
            .prefix(3)
            .map { $0 }
    }

    /// Whether notifications are currently suppressed by a snooze.
    func isSnoozed(now: Date) -> Bool {
        guard let snoozedUntil else { return false }
        return now < snoozedUntil
    }

    /// Minimum gap between threshold notifications: one reminder per day while the
    /// reclaimable amount stays over the threshold. (Snooze suppresses them for a week.)
    private static let notifyCooldown: TimeInterval = 24 * 60 * 60 // 1 day

    /// Decides whether a threshold notification is due for the latest snapshot. Clears
    /// `lastNotified` whenever we're below the threshold, so a fresh crossing can notify
    /// immediately (no cooldown wait). Call `markNotified(at:)` once one was actually delivered.
    func shouldNotifyForThreshold(now: Date) -> Bool {
        guard isEnabled else { return false }
        guard lastReclaimableBytes >= thresholdBytes else {
            lastNotified = nil // below threshold → reset the cap
            return false
        }
        guard !isSnoozed(now: now) else { return false }
        if let last = lastNotified, now.timeIntervalSince(last) < Self.notifyCooldown { return false }
        return true
    }

    /// Starts the one-day cooldown. Only call after macOS accepted the notification.
    func markNotified(at date: Date) { lastNotified = date }

    /// Called when the user cleans in the main app: if reclaimable has dropped below the
    /// threshold, reset the notification cap so the next crossing can notify right away.
    func resetNotificationIfCleared(currentBytes: Int64) {
        if currentBytes < thresholdBytes { lastNotified = nil }
    }

    // MARK: - Helpers

    private func setDate(_ date: Date?, forKey key: String) {
        if let date { defaults.set(date, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    private func persistTopCategories() {
        if let data = try? JSONEncoder().encode(topCategories) {
            defaults.set(data, forKey: Key.topCategories)
        }
    }

    private enum Key {
        static let isEnabled = "monitor.isEnabled"
        static let thresholdBytes = "monitor.thresholdBytes"
        static let snoozedUntil = "monitor.snoozedUntil"
        static let lastNotified = "monitor.lastNotified"
        static let lastCheck = "monitor.lastCheck"
        static let lastReclaimableBytes = "monitor.lastReclaimableBytes"
        static let topCategories = "monitor.topCategories"
    }
}
