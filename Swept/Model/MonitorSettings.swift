//
//  MonitorSettings.swift
//  Swept
//
//  Settings for the menu bar icon, background monitoring and reminders. Persists to UserDefaults.
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

    /// Threshold reminders on/off (limit, how often and what time are set below).
    /// Stored under the old "monitoring enabled" key, so existing setups keep their reminders.
    var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Key.remindersEnabled) }
    }

    /// Show the Swept icon in the menu bar. On by default.
    var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Key.showInMenuBar) }
    }

    /// Whether Swept keeps measuring in the background (and keeps running after the window
    /// closes): needed for the menu bar icon's numbers and for reminders.
    var isMonitoring: Bool { showInMenuBar || remindersEnabled }

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

    /// Time of day for the daily reminder, in minutes after midnight (local time). Default 10:00.
    var reminderMinutes: Int {
        didSet { defaults.set(reminderMinutes, forKey: Key.reminderMinutes) }
    }

    /// How many days between reminders while over the limit (1 = daily, 3, or 7). Default daily.
    var reminderIntervalDays: Int {
        didSet { defaults.set(reminderIntervalDays, forKey: Key.reminderIntervalDays) }
    }

    /// Reminder frequency choices offered in the UI.
    static let reminderIntervalOptions: [(days: Int, label: String)] = [
        (1, "Daily"), (3, "Every 3 days"), (7, "Weekly"),
    ]

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
    @ObservationIgnored private let calendar: Calendar

    // MARK: - Init

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        self.reminderMinutes = (defaults.object(forKey: Key.reminderMinutes) as? Int)
            .map { min(max($0, 0), 24 * 60 - 1) } ?? Self.defaultReminderMinutes
        self.reminderIntervalDays = (defaults.object(forKey: Key.reminderIntervalDays) as? Int)
            .map { min(max($0, 1), 30) } ?? 1
        self.remindersEnabled = defaults.bool(forKey: Key.remindersEnabled) // default off
        self.showInMenuBar = defaults.object(forKey: Key.showInMenuBar) as? Bool ?? true
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

    /// Default daily reminder time: 10:00.
    static let defaultReminderMinutes = 10 * 60

    /// Two reminders are never closer than this: if the next reminder time falls sooner after
    /// the previous one (e.g. you first passed the limit at 23:00), it moves to the day after.
    static let minimumReminderGap: TimeInterval = 12 * 60 * 60

    /// The most recent moment the reminder time of day was reached, at or before `date`.
    func latestReminderTime(atOrBefore date: Date) -> Date {
        let today = reminderTime(onDayOf: date)
        return today <= date ? today : reminderTime(onDayOf: calendar.date(byAdding: .day, value: -1, to: date)!)
    }

    /// When the reminder after one sent at `last` is due: `reminderIntervalDays` after the
    /// reminder time that `last` belonged to, at the reminder time of day. Anchoring on the
    /// scheduled time (not on when it actually went out) keeps a late reminder (Mac asleep)
    /// from pushing every later one back.
    func reminderDue(after last: Date) -> Date {
        let slot = latestReminderTime(atOrBefore: last)
        var due = reminderTime(onDayOf: calendar.date(byAdding: .day, value: reminderIntervalDays, to: slot)!)
        while due.timeIntervalSince(last) < Self.minimumReminderGap {
            due = reminderTime(onDayOf: calendar.date(byAdding: .day, value: 1, to: due)!)
        }
        return due
    }

    /// When the next reminder can arrive, if Swept is still over the limit then.
    /// `nil` when none has been sent yet (the first crossing notifies right away).
    func nextReminderDate(now: Date) -> Date? {
        guard let last = lastNotified else { return nil }
        let due = reminderDue(after: last)
        if let snoozedUntil, snoozedUntil > due { return snoozedUntil }
        return due
    }

    private func reminderTime(onDayOf date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60,
                             second: 0, of: start) ?? start
    }

    /// Decides whether a threshold notification is due for the latest snapshot:
    /// - the first time reclaimable is over the limit, right away;
    /// - after that, every `reminderIntervalDays` days at the reminder time of day (or at the
    ///   first check after it, if the Mac was asleep). See `reminderDue(after:)`.
    /// Clears `lastNotified` whenever we're below the threshold, so a fresh crossing notifies
    /// immediately again. Call `markNotified(at:)` once one was actually delivered.
    func shouldNotifyForThreshold(now: Date) -> Bool {
        guard remindersEnabled else { return false }
        guard lastReclaimableBytes >= thresholdBytes else {
            lastNotified = nil // below threshold → reset the cap
            return false
        }
        guard !isSnoozed(now: now) else { return false }
        guard let last = lastNotified else { return true }
        return now >= reminderDue(after: last)
    }

    /// Starts the wait for the next reminder. Only call after macOS accepted the notification.
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
        static let remindersEnabled = "monitor.isEnabled" // pre-split key: monitoring + reminders
        static let showInMenuBar = "menuBar.show"
        static let thresholdBytes = "monitor.thresholdBytes"
        static let reminderMinutes = "monitor.reminderMinutes"
        static let reminderIntervalDays = "monitor.reminderIntervalDays"
        static let snoozedUntil = "monitor.snoozedUntil"
        static let lastNotified = "monitor.lastNotified"
        static let lastCheck = "monitor.lastCheck"
        static let lastReclaimableBytes = "monitor.lastReclaimableBytes"
        static let topCategories = "monitor.topCategories"
    }
}
