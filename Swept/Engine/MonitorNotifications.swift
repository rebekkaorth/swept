//
//  MonitorNotifications.swift
//  Swept
//
//  Local threshold notifications (UserNotifications). Calm by design: active
//  interruption level so the daily reminder shows a banner, but no sound.
//  Permission is requested ONLY from onboarding or an explicit tap in Settings, never on
//  launch. No networking.
//

import Foundation
import UserNotifications
import AppKit

enum MonitorNotifications {
    /// Stable id so a new notification replaces any prior one (no stacking).
    private static let requestID = "swept.threshold"

    /// Requests notification permission. Call this ONLY from the onboarding step.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        } catch {
            return false
        }
    }

    /// Current notification permission (read-only; never prompts).
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Posts the calm threshold notification. Returns `true` only if macOS accepted it, so the
    /// caller doesn't spend the once-a-day reminder on a notification nobody could see.
    @discardableResult
    static func postThreshold(reclaimableBytes: Int64) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
              settings.alertSetting == .enabled else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Some clutter has piled up"
        content.body = "Swept found \(ByteFormat.string(reclaimableBytes)) it could reclaim, mostly rebuildable caches. Review whenever it suits you."
        content.interruptionLevel = .active // shows a banner; still no sound (content.sound stays nil)

        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
        center.removeDeliveredNotifications(withIdentifiers: [requestID])
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        do {
            try await center.add(request)
            return true
        } catch {
            NSLog("Swept: could not post threshold notification — \(error.localizedDescription)")
            return false
        }
    }

    /// Opens Swept's page in System Settings ▸ Notifications (for when permission was denied).
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.rebekkaorth.Swept"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}
