//
//  SweptApp.swift
//  Swept
//

import SwiftUI
import AppKit
import UserNotifications

/// App-window / activation-policy helpers shared across the app.
enum AppWindow {
    static let mainID = "main"

    /// Captured from the main window's environment so AppKit code (status item, delegate)
    /// can reopen the SwiftUI window even after it has been closed. The scene is a
    /// single-instance `Window`, so this focuses the existing window rather than adding one.
    nonisolated(unsafe) static var opener: OpenWindowAction?

    /// Set at launch when macOS opened Swept at login with monitoring on: the main window
    /// that SwiftUI opens is closed straight away so Swept starts quietly in the menu bar.
    /// Consumed by the first window that appears.
    nonisolated(unsafe) static var startHidden = false

    /// Restore the Dock icon and bring the main window forward.
    @MainActor static func showMain() {
        NSApp.setActivationPolicy(.regular)
        if let opener {
            opener(id: mainID)
        } else {
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }

    /// Drop to background (no Dock icon). Only used while monitoring is on.
    @MainActor static func enterBackground() {
        NSApp.setActivationPolicy(.accessory)
    }
}

final class SweptAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var backgroundMonitor: BackgroundMonitor?
    private var statusController: StatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The launch Apple event is only available now, not later.
        if MonitorSettings.shared.isMonitoring, LoginItem.isLaunchingAtLogin() {
            AppWindow.startHidden = true
            AppWindow.enterBackground()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        let background = BackgroundMonitor(settings: .shared)
        backgroundMonitor = background
        statusController = StatusItemController(monitor: .shared, backgroundMonitor: background)
    }

    /// Closing the last window quits — EXCEPT while the menu bar icon or reminders are on,
    /// when Swept keeps running in the background (reopen it from the Dock, Spotlight or Finder).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !MonitorSettings.shared.isMonitoring
    }

    /// Relaunching Swept while it's already running in the background reopens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MonitorSettings.shared.requestOpenWindow() }
        return true
    }

    // Show the banner even if Swept is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    // Clicking the notification restores the Dock icon and opens the main window.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await MainActor.run { MonitorSettings.shared.requestOpenWindow() }
    }
}

@main
struct SweptApp: App {
    @NSApplicationDelegateAdaptor(SweptAppDelegate.self) private var appDelegate
    @State private var monitor = MonitorSettings.shared

    var body: some Scene {
        // A single-instance `Window` (not `WindowGroup`): openWindow(id:) brings the one
        // existing window forward instead of spawning a new window/tab each time.
        Window("Swept", id: AppWindow.mainID) {
            ContentView()
                .environment(monitor)
        }
        .defaultSize(width: 1160, height: 762)

        // Preferences (⌘,) — where monitoring is turned on/off. The menu bar item itself is
        // managed in AppKit (StatusItemController) so it can offer a right-click menu.
        Settings {
            SettingsView(monitor: monitor)
        }
    }
}
