//
//  ContentView.swift
//  Swept
//
//  Root router. Full Disk Access is the single gate: on macOS 26 (Tahoe) reading
//  other apps' data requires FDA, so without it there is nothing to scan. The FDA
//  check — re-evaluated on every launch and on reactivation — decides the screen.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Environment(MonitorSettings.self) private var monitor
    @AppStorage("hasSeenMonitoringSetup") private var hasSeenMonitoringSetup = false
    /// Set once the user pressed "Scan My Mac" on the welcome screen. Until then, nothing scans.
    @AppStorage("hasStartedFirstScan") private var hasStartedFirstScan = false

    @State private var model = ScanModel()
    @State private var route: AppRoute = ContentView.initialRoute
    @State private var scanTask: Task<Void, Never>?
    /// True once the user has come back to the app with FDA still off (needs a relaunch hint).
    @State private var showRelaunchHint = false
    @State private var showMonitoringSetup = false
    @State private var observedWindow: NSWindow?

    /// Reclaimable below this after a scan → Empty screen.
    private let emptyThreshold: Int64 = 500_000_000 // ~0.5 GB

    /// First launch starts on the welcome screen. (Anyone who already finished the old setup
    /// has scanned before, so they skip it.)
    private static var initialRoute: AppRoute {
        let d = UserDefaults.standard
        return d.bool(forKey: "hasStartedFirstScan") || d.bool(forKey: "hasSeenMonitoringSetup")
            ? .onboarding : .welcome
    }

    var body: some View {
        ZStack {
            switch route {
            case .welcome:
                WelcomeView(onStart: startFirstScan)
                    .transition(.opacity)
            case .onboarding:
                OnboardingView(showRelaunchHint: showRelaunchHint)
                    .transition(.opacity)
            case .scanning:
                ScanningView(model: model, onCancel: cancelScan)
                    .transition(.opacity)
            case .main:
                MainSplitView(model: model, onScanAgain: startScan,
                              onSetUpReminders: monitor.remindersEnabled ? nil : { showMonitoringSetup = true })
                    .transition(.opacity)
            case .empty:
                EmptyStateView(lastScanned: model.lastScanned, onScanAgain: startScan)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
        .background(Theme.windowBackground)
        // Grab the main window: while it's shown the app is .regular; when it closes with
        // monitoring on, drop to .accessory (menu-bar only, no Dock icon).
        .background(WindowAccessor { window in
            guard observedWindow !== window else { return }
            observedWindow = window
            if AppWindow.startHidden {
                // Opened at login: stay in the menu bar. The next "Show App" opens a fresh window.
                AppWindow.startHidden = false
                window.close()
                AppWindow.enterBackground()
                return
            }
            NSApp.setActivationPolicy(.regular)
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                if monitor.isMonitoring { AppWindow.enterBackground() }
            }
        })
        // Dark-first, but follow the system appearance so light mode works too.
        .onAppear {
            AppWindow.opener = openWindow // let AppKit reopen this window later
            // Opened at login: skip the full scan; the menu-bar monitor measures on its own.
            guard !AppWindow.startHidden else { return }
            refresh(isReactivation: false)
        }
        .onChange(of: scenePhase) { _, phase in
            // The user may have just granted (or revoked) Full Disk Access in System Settings.
            if phase == .active { refresh(isReactivation: true) }
        }
        .onChange(of: monitor.reviewRequestToken) { _, _ in
            // "Review in Swept" was tapped in the menu-bar popover → run a full scan.
            if FullDiskAccess.isGranted() { startScan() } else { refresh(isReactivation: true) }
        }
        .onChange(of: model.isScanning) { _, running in
            // Let the background monitor defer while a full scan is running.
            monitor.isFullScanRunning = running
        }
        .onChange(of: model.reclaimable) { _, bytes in
            // A full scan or a clean is the freshest measurement — hand it to the menu bar so
            // the popover never shows older numbers than the window.
            if model.lastScanned != nil {
                monitor.record(SizesSnapshot(categories: model.categories), at: Date())
            }
            // If the user cleaned below the threshold, allow a fresh notification next crossing.
            monitor.resetNotificationIfCleared(currentBytes: bytes)
        }
        .onChange(of: model.lastScanned) { _, scanned in
            // A rescan can land on the same total; still refresh "Last checked" and the culprits.
            if scanned != nil {
                monitor.record(SizesSnapshot(categories: model.categories), at: Date())
            }
        }
        .onChange(of: route) { _, newRoute in
            // First run: once the first scan is done, run the setup (reminders, then login item).
            if newRoute == .main || newRoute == .empty, !hasSeenMonitoringSetup {
                hasSeenMonitoringSetup = true
                showMonitoringSetup = true
            }
        }
        .sheet(isPresented: $showMonitoringSetup) {
            MonitoringSetupView(monitor: monitor) { showMonitoringSetup = false }
        }
    }

    // MARK: - Gate

    /// Re-evaluates Full Disk Access and routes accordingly. FDA is the source of truth.
    private func refresh(isReactivation: Bool) {
        // The welcome screen waits for "Scan My Mac" (see startFirstScan).
        if route == .welcome { return }
        FullDiskAccess.recheck()

        if FullDiskAccess.isGranted() {
            showRelaunchHint = false
            // Auto-advance from the gate into a scan; don't disturb an active scan/results.
            if route == .onboarding { startScan() }
        } else {
            // No FDA → nothing to scan on Tahoe. Show the gate.
            scanTask?.cancel()
            if route != .onboarding {
                withAnimation(Theme.Motion.cross) { route = .onboarding }
            }
            // If they've returned and it's still off, Tahoe likely needs a relaunch.
            if isReactivation { showRelaunchHint = true }
        }
    }

    // MARK: - Flow

    /// "Scan My Mac" on the welcome screen: scan now, or ask for Full Disk Access first.
    private func startFirstScan() {
        hasStartedFirstScan = true
        FullDiskAccess.recheck()
        if FullDiskAccess.isGranted() {
            startScan()
        } else {
            withAnimation(Theme.Motion.cross) { route = .onboarding } // the gate auto-scans once granted
        }
    }

    private func startScan() {
        // Where Cancel should return us: Main if we already have results, else Onboarding.
        let previous: AppRoute = model.categories.isEmpty ? .welcome : .main

        scanTask?.cancel()
        withAnimation(Theme.Motion.cross) { route = .scanning }

        scanTask = Task {
            let completed = await model.scan()
            withAnimation(Theme.Motion.cross) {
                if completed {
                    route = model.reclaimable < emptyThreshold ? .empty : .main
                } else {
                    route = previous
                }
            }
        }
    }

    private func cancelScan() {
        scanTask?.cancel() // scan() returns false → the Task routes back to `previous`.
    }
}

/// Resolves the hosting `NSWindow` so we can observe its close and toggle the Dock icon.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in if let window = view?.window { onResolve(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in if let window = nsView?.window { onResolve(window) } }
    }
}

#Preview {
    ContentView()
        .environment(MonitorSettings(defaults: UserDefaults(suiteName: "swept.preview.content")!))
}
