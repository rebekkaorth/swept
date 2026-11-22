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

    @State private var model = ScanModel()
    @State private var route: AppRoute = .onboarding
    @State private var scanTask: Task<Void, Never>?
    /// True once the user has come back to the app with FDA still off (needs a relaunch hint).
    @State private var showRelaunchHint = false
    @State private var showMonitoringSetup = false
    @State private var observedWindow: NSWindow?

    /// Reclaimable below this after a scan → Empty screen.
    private let emptyThreshold: Int64 = 500_000_000 // ~0.5 GB

    var body: some View {
        ZStack {
            switch route {
            case .onboarding:
                OnboardingView(showRelaunchHint: showRelaunchHint)
                    .transition(.opacity)
            case .scanning:
                ScanningView(model: model, onCancel: cancelScan)
                    .transition(.opacity)
            case .main:
                MainSplitView(model: model, onScanAgain: startScan,
                              onTurnOnMonitoring: monitor.isEnabled ? nil : { showMonitoringSetup = true })
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
            NSApp.setActivationPolicy(.regular)
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                if monitor.isEnabled { AppWindow.enterBackground() }
            }
        })
        // Dark-first, but follow the system appearance so light mode works too.
        .onAppear {
            AppWindow.opener = openWindow // let AppKit reopen this window later
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
            // First run: once results are in and monitoring is off, offer the (skippable) setup.
            if newRoute == .main, !hasSeenMonitoringSetup, !monitor.isEnabled {
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

    private func startScan() {
        // Where Cancel should return us: Main if we already have results, else Onboarding.
        let previous: AppRoute = model.categories.isEmpty ? .onboarding : .main

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
