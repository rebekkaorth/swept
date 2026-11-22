//
//  LoginItem.swift
//  Swept
//
//  Thin wrapper over SMAppService for launching Swept at login. Toggled alongside
//  background monitoring. No networking.
//

import Foundation
import ServiceManagement

enum LoginItem {
    /// Whether Swept is currently registered to launch at login.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Registers or unregisters the app as a login item. Idempotent — only acts when the
    /// current status differs — so redundant calls don't produce "not permitted" noise.
    /// Failures are logged, not fatal.
    static func setEnabled(_ enabled: Bool) {
        let status = SMAppService.mainApp.status
        do {
            if enabled {
                guard status != .enabled else { return }
                try SMAppService.mainApp.register()
            } else {
                guard status == .enabled else { return } // nothing registered → nothing to do
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Swept: login item \(enabled ? "register" : "unregister") failed — \(error.localizedDescription)")
        }
    }
}
