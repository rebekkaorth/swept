//
//  StatusItemController.swift
//  Swept
//
//  AppKit-owned menu bar item. SwiftUI's MenuBarExtra can't distinguish a right-click
//  (NSStatusItem.menu disables the click action), so we manage the status item directly:
//  left-click → popover (hosting MenuBarPopoverView), right-click → a small NSMenu.
//  The icon hosts the SwiftUI MenuBarIcon so its 3 states + animation are preserved.
//

import SwiftUI
import AppKit

/// Hosting view that lets clicks fall through to the status-bar button underneath.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The SwiftUI icon, re-rendered automatically as the monitor state changes.
private struct StatusBarIconView: View {
    let monitor: MonitorSettings
    private var state: MenuBarIconState {
        if monitor.isChecking { return .scanning }
        if monitor.lastReclaimableBytes >= monitor.thresholdBytes { return .attention }
        return .idle
    }
    var body: some View {
        MenuBarIcon(state: state).frame(width: 18, height: 18)
    }
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let monitor: MonitorSettings
    private let backgroundMonitor: BackgroundMonitor

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let menu = NSMenu()

    init(monitor: MonitorSettings, backgroundMonitor: BackgroundMonitor) {
        self.monitor = monitor
        self.backgroundMonitor = backgroundMonitor
        super.init()
        configurePopover()
        configureMenu()
        syncPresence()
        trackEnabled()
        trackOpenRequests()
    }

    // MARK: - Setup

    private func configurePopover() {
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: MenuBarPopoverView(monitor: monitor))
        hosting.sizingOptions = [.preferredContentSize] // let SwiftUI size the popover
        popover.contentViewController = hosting
    }

    private func configureMenu() {
        let show = NSMenuItem(title: "Show App", action: #selector(showApp), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Swept", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.delegate = self
    }

    // MARK: - Presence (follows the menu bar / reminders settings)

    private func syncPresence() {
        // Icon follows "Show in menu bar"; background checks run for the icon OR reminders.
        if monitor.showInMenuBar {
            if statusItem == nil { installStatusItem() }
        } else if statusItem != nil {
            popover.performClose(nil)
            removeStatusItem()
        }
        if monitor.isMonitoring { backgroundMonitor.start() } else { backgroundMonitor.stop() }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 28)
        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            let host = PassthroughHostingView(rootView: StatusBarIconView(monitor: monitor))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                host.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
        }
        statusItem = item
    }

    private func removeStatusItem() {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }

    // MARK: - Clicks

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isSecondary { showMenu() } else { togglePopover() }
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
        }
    }

    private func showMenu() {
        guard let item = statusItem else { return }
        // Temporarily attach the menu so a click opens it, then detach on close so the
        // left-click popover keeps working (see NSStatusItem.menu docs).
        item.menu = menu
        item.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    @objc private func showApp() { AppWindow.showMain() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Observation

    private func trackEnabled() {
        _ = withObservationTracking {
            (monitor.showInMenuBar, monitor.remindersEnabled)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncPresence()
                self?.trackEnabled()
            }
        }
    }

    private func trackOpenRequests() {
        _ = withObservationTracking {
            monitor.openWindowToken
        } onChange: { [weak self] in
            Task { @MainActor in
                AppWindow.showMain()      // Dock reopen / notification tap asked to show the window
                self?.trackOpenRequests() // re-arm for the next request
            }
        }
    }
}
