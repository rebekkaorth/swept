//
//  SettingsView.swift
//  Swept
//
//  Preferences (⌘,). For now: the menu-bar monitoring toggle + threshold.
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Bindable var monitor: MonitorSettings
    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        Form {
            Section {
                Toggle("Show Swept in the menu bar", isOn: $monitor.isEnabled)

                if monitor.isEnabled {
                    Picker("Notify me past", selection: $monitor.thresholdBytes) {
                        ForEach(MonitorSettings.thresholdPresets, id: \.self) { bytes in
                            Text(bytes.fileSize).tag(bytes)
                        }
                    }
                    notificationRow
                }
            } header: {
                Text("Menu Bar Monitoring")
            } footer: {
                Text("When on, Swept adds a menu bar item and launches at login to keep an eye on reclaimable storage. Everything stays on your Mac — nothing is ever sent anywhere.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .task { await refreshNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may have just changed the permission in System Settings.
            Task { await refreshNotificationStatus() }
        }
        .onChange(of: monitor.isEnabled) { _, enabled in
            // Turning monitoring off removes the menu bar icon — make sure the app never ends
            // up with neither a Dock icon nor a menu bar icon: restore the window + Dock.
            if !enabled { AppWindow.showMain() }
        }
    }

    /// Reminders need notification permission; make a missing one visible instead of silent.
    @ViewBuilder
    private var notificationRow: some View {
        switch notificationStatus {
        case .notDetermined:
            LabeledContent("Reminders") {
                Button("Allow Notifications") {
                    Task {
                        await MonitorNotifications.requestAuthorization()
                        await refreshNotificationStatus()
                    }
                }
            }
        case .denied:
            LabeledContent("Reminders are off") {
                Button("Open System Settings") { MonitorNotifications.openSystemSettings() }
            }
        default:
            EmptyView()
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await MonitorNotifications.authorizationStatus()
    }
}

#Preview {
    SettingsView(monitor: MonitorSettings(defaults: UserDefaults(suiteName: "swept.preview.settings")!))
        .preferredColorScheme(.dark)
}
