//
//  BackgroundMonitor.swift
//  Swept
//
//  Owns the cadence for the menu-bar monitor. Wakes about once an hour via
//  NSBackgroundActivityScheduler (App Nap–aware, unlike a plain Timer in a menu-bar-only
//  app) and after the Mac wakes from sleep. Each wake:
//    1. runs the low-impact, sizes-only scan if the last measurement is 6+ hours old;
//    2. checks whether a reminder is due (limit reached, reminder time passed, not snoozed).
//  Checking hourly is what lets the reminder arrive close to the chosen time of day, while
//  the disk is only measured every 6 hours. Read-only — it never deletes.
//

import Foundation
import AppKit
import Observation

@Observable
final class BackgroundMonitor {

    /// Real scanning state, mirrored from settings so the icon + popover reflect actual work.
    var isScanning: Bool { settings.isChecking }

    @ObservationIgnored private let settings: MonitorSettings
    @ObservationIgnored private let scanner: Scanning
    @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var isRunning = false

    private let checkInterval: TimeInterval = 60 * 60     // wake up hourly to check the reminder
    private let scanInterval: TimeInterval = 6 * 60 * 60  // re-measure the disk every 6 hours
    /// A reminder is only sent from a reasonably fresh measurement.
    private let maxSnapshotAge: TimeInterval = 7 * 60 * 60

    init(settings: MonitorSettings, scanner: Scanning = FileSystemScanner()) {
        self.settings = settings
        self.scanner = scanner
    }

    // MARK: - Lifecycle (runs while the menu bar icon or reminders are on)

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // A scan when monitoring starts (launch, login, or switching it on).
        Task { await tick(forceScan: true) }

        let scheduler = NSBackgroundActivityScheduler(identifier: "com.rebekkaorth.Swept.monitor")
        scheduler.repeats = true
        scheduler.interval = checkInterval
        scheduler.tolerance = 10 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task {
                await self?.tick(forceScan: false)
                completion(.finished)
            }
        }
        self.scheduler = scheduler

        // Scheduled runs don't happen while the Mac sleeps: catch up on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.tick(forceScan: false) }
        }
    }

    func stop() {
        isRunning = false
        scheduler?.invalidate()
        scheduler = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    // MARK: - Tick

    /// Measures if due, then sends the reminder if due. `forceScan` bypasses only the 6-hour
    /// scan interval; the mid-scan and Full Disk Access guards always apply.
    @MainActor
    private func tick(forceScan: Bool) async {
        guard settings.isMonitoring else { return }
        await scanIfDue(force: forceScan)
        await remindIfDue()
    }

    @MainActor
    private func scanIfDue(force: Bool) async {
        guard !settings.isFullScanRunning else { return } // defer to a full scan in the main app
        guard FullDiskAccess.isGranted() else { return }  // nothing to measure without FDA
        guard !settings.isChecking else { return }        // already measuring
        if !force, let last = settings.lastCheck, Date().timeIntervalSince(last) < scanInterval { return }

        settings.isChecking = true
        defer { settings.isChecking = false }
        do {
            let snapshot = try await scanner.sizesOnlyScan() // utility QoS, off the main thread
            settings.record(snapshot, at: Date())
        } catch {
            // Leave the previous snapshot in place.
        }
    }

    /// Sends the reminder when it's due. The cooldown only starts once macOS accepted the
    /// notification, so a denied permission or a failed post doesn't silently use it up.
    @MainActor
    private func remindIfDue() async {
        guard let lastCheck = settings.lastCheck,
              Date().timeIntervalSince(lastCheck) < maxSnapshotAge else { return }
        guard settings.shouldNotifyForThreshold(now: Date()) else { return }
        if await MonitorNotifications.postThreshold(reclaimableBytes: settings.lastReclaimableBytes) {
            settings.markNotified(at: Date())
        }
    }
}
