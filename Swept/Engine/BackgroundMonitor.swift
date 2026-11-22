//
//  BackgroundMonitor.swift
//  Swept
//
//  Owns the cadence for the low-impact, sizes-only background scan that powers the
//  menu-bar monitor. Runs once when the menu bar extra appears, then every 6 hours via
//  NSBackgroundActivityScheduler (App Nap–aware, unlike a plain Timer in a menu-bar-only
//  app), recomputing after the machine wakes from sleep. Read-only — it never deletes.
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

    private let interval: TimeInterval = 6 * 60 * 60 // 6 hours
    private let minimumGap: TimeInterval = 60 * 60    // never more often than hourly

    init(settings: MonitorSettings, scanner: Scanning = FileSystemScanner()) {
        self.settings = settings
        self.scanner = scanner
    }

    // MARK: - Lifecycle (tied to the menu bar extra being present)

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // A scan on launch of the menu bar extra.
        Task { await tick(force: true) }

        // Every 6 hours, with generous tolerance (low priority — timing isn't precise).
        // The system picks a good moment and keeps it from being starved by App Nap.
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.rebekkaorth.Swept.monitor")
        scheduler.repeats = true
        scheduler.interval = interval
        scheduler.tolerance = 30 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task {
                await self?.tick(force: false)
                completion(.finished)
            }
        }
        self.scheduler = scheduler

        // Tolerate sleep: re-evaluate on wake. `tick` enforces the 1-hour gap, so this is a
        // no-op if we scanned recently and catches up if we slept through a scheduled run.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.tick(force: false) }
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

    // MARK: - Scan tick

    /// Runs a measurement when conditions allow. `force` bypasses ONLY the 1-hour gap (for the
    /// launch scan); it never overrides the mid-scan or FDA guards. Snooze silences the
    /// notification only — measuring continues so the popover stays current.
    @MainActor
    private func tick(force: Bool) async {
        guard settings.isEnabled else { return }
        let now = Date()
        guard !settings.isFullScanRunning else { return } // defer to a full scan in the main app
        guard FullDiskAccess.isGranted() else { return }  // nothing to measure without FDA
        if !force, let last = settings.lastCheck, now.timeIntervalSince(last) < minimumGap { return }
        guard !settings.isChecking else { return }        // already measuring

        settings.isChecking = true
        defer { settings.isChecking = false }
        do {
            let snapshot = try await scanner.sizesOnlyScan() // utility QoS, off the main thread
            settings.record(snapshot, at: Date())
            // Threshold notification: over the limit, not snoozed, and >24h since the last one.
            // The cooldown only starts once macOS accepted it, so a denied permission or a
            // failed post doesn't silently swallow the day's reminder.
            if settings.shouldNotifyForThreshold(now: Date()),
               await MonitorNotifications.postThreshold(reclaimableBytes: settings.lastReclaimableBytes) {
                settings.markNotified(at: Date())
            }
        } catch {
            // Leave the previous snapshot in place.
        }
    }
}
