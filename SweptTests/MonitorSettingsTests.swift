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
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let threshold: Int64 = 25_000_000_000
    private let day: TimeInterval = 24 * 60 * 60

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        // Seed `isEnabled` directly: setting the property would register a real login item.
        defaults.set(true, forKey: "monitor.isEnabled")
    }

    /// Fresh settings backed by this test's suite, with the last measurement at `bytes`.
    private func makeSettings(bytes: Int64) -> MonitorSettings {
        let settings = MonitorSettings(defaults: defaults)
        settings.thresholdBytes = threshold
        settings.lastReclaimableBytes = bytes
        return settings
    }

    private func cleanUp() { defaults.removePersistentDomain(forName: suiteName) }

    @Test func notifiesWhenOverThresholdAndNeverNotified() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        #expect(settings.isEnabled)
        #expect(settings.shouldNotifyForThreshold(now: now))
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

    @Test func doesNotNotifyWithin24HoursOfLastNotified() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.lastNotified = now

        #expect(!settings.shouldNotifyForThreshold(now: now))
        #expect(!settings.shouldNotifyForThreshold(now: now.addingTimeInterval(day - 1)))
    }

    @Test func notifiesAgainOnce24HoursHavePassed() {
        defer { cleanUp() }
        let settings = makeSettings(bytes: threshold)
        settings.lastNotified = now

        #expect(settings.shouldNotifyForThreshold(now: now.addingTimeInterval(day)))
        #expect(settings.shouldNotifyForThreshold(now: now.addingTimeInterval(day + 3600)))
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

        let reloaded = MonitorSettings(defaults: defaults)
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
