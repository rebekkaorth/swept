//
//  MonitorSettingsTests.swift
//  SweptTests
//
//  Reminder cooldown / snooze logic, against an isolated UserDefaults suite so tests
//  never read or write the real app's settings.
//

import Foundation
import Testing
@testable import Swept

@Suite("MonitorSettings reminders")
struct MonitorSettingsTests {

    private let suiteName = "SweptTests.MonitorSettings.\(UUID().uuidString)"
    private let defaults: UserDefaults
    /// Fixed UTC calendar so time-of-day rules don't depend on the machine's time zone.
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private var now: Date { at(day: 1, hour: 9) }
    private let threshold: Int64 = 25_000_000_000
    private let day: TimeInterval = 24 * 60 * 60

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        // Reminders on, seeded under the stored key (also checks the pre-split key still works).
        defaults.set(true, forKey: "monitor.isEnabled")
    }

    /// Fresh settings backed by this test's suite, with the last measurement at `bytes`.
    private func makeSettings(bytes: Int64) -> MonitorSettings {
        let settings = MonitorSettings(defaults: defaults, calendar: calendar)
        settings.thresholdBytes = threshold
        settings.lastReclaimableBytes = bytes
        return settings
    }

    /// 2026-11-(day) hour:minute UTC.
    private func at(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func cleanUp() { defaults.removePersistentDomain(forName: suiteName) }

    @Test func notifiesWhenOverThresholdAndNeverNotified() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        #expect(settings.remindersEnabled)
        #expect(settings.shouldNotifyForThreshold(now: now))
    }

    @Test func menuBarIsOnByDefaultAndIndependentOfReminders() {
        defer { cleanUp() }
        defaults.removeObject(forKey: "monitor.isEnabled")
        let settings = makeSettings(bytes: threshold * 2)
        #expect(settings.showInMenuBar)
        #expect(!settings.remindersEnabled)
        #expect(settings.isMonitoring)                    // the menu bar icon needs measurements
        #expect(!settings.shouldNotifyForThreshold(now: now)) // …but no reminders

        settings.showInMenuBar = false
        #expect(!settings.isMonitoring)
        settings.remindersEnabled = true
        #expect(settings.isMonitoring)                    // reminders work without the icon
        #expect(settings.shouldNotifyForThreshold(now: now))

        let reloaded = MonitorSettings(defaults: defaults, calendar: calendar)
        #expect(!reloaded.showInMenuBar)
        #expect(reloaded.remindersEnabled)
    }

    @Test func doesNotNotifyWhenDisabled() {
        defer { cleanUp() }
        defaults.set(false, forKey: "monitor.isEnabled")
        let settings = makeSettings(bytes: threshold * 2)
        #expect(!settings.shouldNotifyForThreshold(now: now))
    }

    @Test func belowThresholdReturnsFalseAndClearsLastNotified() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold - 1)
        settings.lastNotified = now.addingTimeInterval(-60)

        #expect(!settings.shouldNotifyForThreshold(now: now))
        #expect(settings.lastNotified == nil)
        #expect(defaults.object(forKey: "monitor.lastNotified") == nil)
    }

    @Test func fallingBelowThresholdLetsAFreshCrossingNotifyImmediately() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.markNotified(at: now)

        settings.lastReclaimableBytes = threshold - 1
        #expect(!settings.shouldNotifyForThreshold(now: now.addingTimeInterval(60)))

        settings.lastReclaimableBytes = threshold
        #expect(settings.shouldNotifyForThreshold(now: now.addingTimeInterval(120)))
    }

    @Test func doesNotNotifyWhileSnoozed() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold * 2)
        settings.snoozeForAWeek(from: now)

        #expect(settings.isSnoozed(now: now))
        #expect(!settings.shouldNotifyForThreshold(now: now))
        #expect(!settings.shouldNotifyForThreshold(now: now.addingTimeInterval(7 * day - 1)))
        #expect(settings.shouldNotifyForThreshold(now: now.addingTimeInterval(7 * day)))
    }

    @Test func defaultsToDailyAtTen() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        #expect(settings.reminderMinutes == 10 * 60)
        #expect(settings.reminderIntervalDays == 1)
    }

    @Test func dailyReminderComesAtTheSetTime() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.lastNotified = at(day: 1, hour: 10)

        #expect(!settings.shouldNotifyForThreshold(now: at(day: 1, hour: 23)))
        #expect(!settings.shouldNotifyForThreshold(now: at(day: 2, hour: 9, minute: 59)))
        #expect(settings.shouldNotifyForThreshold(now: at(day: 2, hour: 10)))
        #expect(settings.shouldNotifyForThreshold(now: at(day: 2, hour: 10, minute: 40)))
    }

    @Test func remindersDoNotDriftLaterAfterALateOne() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        // Mac was asleep at 10:00 on day 2 → the reminder went out on wake at 15:00.
        settings.lastNotified = at(day: 2, hour: 15)
        // Day 3 is back at 10:00, not 15:00.
        #expect(!settings.shouldNotifyForThreshold(now: at(day: 3, hour: 9)))
        #expect(settings.shouldNotifyForThreshold(now: at(day: 3, hour: 10)))
    }

    @Test func firstCrossingLateInTheDaySkipsTheTooCloseReminder() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.lastNotified = at(day: 1, hour: 23) // first crossing, notified right away
        // Day 2 at 10:00 is only 11 h later → skipped; next one is day 3 at 10:00.
        #expect(!settings.shouldNotifyForThreshold(now: at(day: 2, hour: 10)))
        #expect(!settings.shouldNotifyForThreshold(now: at(day: 2, hour: 22)))
        #expect(settings.shouldNotifyForThreshold(now: at(day: 3, hour: 10)))
    }

    @Test func firstCrossingJustBeforeReminderTimeWaitsForTomorrow() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.lastNotified = at(day: 1, hour: 9, minute: 30)
        #expect(!settings.shouldNotifyForThreshold(now: at(day: 1, hour: 10)))
        #expect(!settings.shouldNotifyForThreshold(now: at(day: 1, hour: 22)))
        #expect(settings.shouldNotifyForThreshold(now: at(day: 2, hour: 10)))
    }

    @Test func customTimeOfDay() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.reminderMinutes = 18 * 60 + 30
        settings.lastNotified = at(day: 1, hour: 18, minute: 30)
        #expect(!settings.shouldNotifyForThreshold(now: at(day: 2, hour: 18, minute: 29)))
        #expect(settings.shouldNotifyForThreshold(now: at(day: 2, hour: 18, minute: 30)))
    }

    @Test func everyThreeDays() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.reminderIntervalDays = 3
        settings.lastNotified = at(day: 1, hour: 10)
        #expect(!settings.shouldNotifyForThreshold(now: at(day: 2, hour: 10)))
        #expect(!settings.shouldNotifyForThreshold(now: at(day: 3, hour: 23)))
        #expect(settings.shouldNotifyForThreshold(now: at(day: 4, hour: 10)))
    }

    @Test func weekly() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.reminderIntervalDays = 7
        settings.lastNotified = at(day: 1, hour: 10)
        #expect(!settings.shouldNotifyForThreshold(now: at(day: 7, hour: 10)))
        #expect(settings.shouldNotifyForThreshold(now: at(day: 8, hour: 10)))
    }

    @Test func nextReminderDateFollowsTimeAndInterval() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        #expect(settings.nextReminderDate(now: now) == nil) // nothing sent yet → right away

        settings.lastNotified = at(day: 1, hour: 10)
        #expect(settings.nextReminderDate(now: at(day: 1, hour: 12)) == at(day: 2, hour: 10))

        settings.lastNotified = at(day: 1, hour: 23)
        #expect(settings.nextReminderDate(now: at(day: 1, hour: 23)) == at(day: 3, hour: 10))

        settings.reminderIntervalDays = 3
        settings.lastNotified = at(day: 1, hour: 10)
        #expect(settings.nextReminderDate(now: at(day: 1, hour: 12)) == at(day: 4, hour: 10))
    }

    @Test func reminderSettingsPersist() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.reminderMinutes = 8 * 60 + 15
        settings.reminderIntervalDays = 7
        let reloaded = MonitorSettings(defaults: defaults, calendar: calendar)
        #expect(reloaded.reminderMinutes == 8 * 60 + 15)
        #expect(reloaded.reminderIntervalDays == 7)
    }

    @Test func shouldNotifyDoesNotItselfStartTheCooldown() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        #expect(settings.shouldNotifyForThreshold(now: now))
        #expect(settings.lastNotified == nil)
        #expect(settings.shouldNotifyForThreshold(now: now.addingTimeInterval(60)))
    }

    @Test func markNotifiedStartsTheCooldownAndPersists() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.markNotified(at: now)

        #expect(settings.lastNotified == now)
        #expect(!settings.shouldNotifyForThreshold(now: now.addingTimeInterval(60)))

        let reloaded = MonitorSettings(defaults: defaults, calendar: calendar)
        #expect(reloaded.lastNotified == now)
        #expect(!reloaded.shouldNotifyForThreshold(now: now.addingTimeInterval(60)))
    }

    @Test func resetNotificationIfClearedBelowThresholdClearsCooldown() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.markNotified(at: now)

        settings.resetNotificationIfCleared(currentBytes: threshold - 1)
        #expect(settings.lastNotified == nil)
    }

    @Test func resetNotificationIfClearedAtOrAboveThresholdKeepsCooldown() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.markNotified(at: now)

        settings.resetNotificationIfCleared(currentBytes: threshold)
        #expect(settings.lastNotified == now)
        settings.resetNotificationIfCleared(currentBytes: threshold * 2)
        #expect(settings.lastNotified == now)
    }
}
