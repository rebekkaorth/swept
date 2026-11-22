//
//  LoginItem.swift
//  Swept
//
//  Thin wrapper over SMAppService for opening Swept at login. Its own choice, asked in the
//  first-run setup and switchable in Settings, independent of the menu bar and reminders.
//  No networking.
//

import Foundation
import AppKit
import ServiceManagement

enum LoginItem {
    /// What macOS says about Swept as a login item. Read this, not a stored flag: the user can
    /// switch it off in System Settings ▸ General ▸ Login Items at any time.
    enum State: Equatable {
        case on              // Swept opens at login
        case needsApproval   // registered, but switched off / not yet allowed in System Settings
        case off             // not registered
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        default: .off
        }
    }

    /// Whether Swept is currently registered AND allowed to open at login.
    static var isEnabled: Bool { state == .on }

    /// Registers or unregisters the app as a login item. Idempotent — only acts when the
    /// current status differs — so redundant calls don't produce "not permitted" noise.
    /// Returns the resulting state. Failures are logged, not fatal.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> State {
        let status = SMAppService.mainApp.status
        do {
            if enabled {
                if status != .enabled { try SMAppService.mainApp.register() }
            } else if status == .enabled || status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Swept: login item \(enabled ? "register" : "unregister") failed — \(error.localizedDescription)")
        }
        return state
    }

    /// Opens System Settings ▸ General ▸ Login Items, where the user can allow Swept.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// True when this process was started by macOS as a login item (not by the user).
    /// Only meaningful while the app is finishing launching.
    static func isLaunchingAtLogin() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }
}
