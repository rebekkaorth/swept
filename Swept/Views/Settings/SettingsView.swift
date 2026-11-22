//
//  SettingsView.swift
//  Swept
//
//  Preferences (⌘,): menu bar icon, opening at login, reminders — each on its own — and a
//  status section that shows what Swept will actually do (so you can check it's set up right).
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Bindable var monitor: MonitorSettings
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var loginState: LoginItem.State = LoginItem.state
    @State private var testResult: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show Swept in the menu bar", isOn: $monitor.showInMenuBar)
                loginRow
            } header: {
                Text("General")
            } footer: {
                footnote("While the menu bar icon or reminders are on, Swept keeps running after you close its window: it measures every 6 hours and looks for a due reminder every hour. Everything stays on your Mac — nothing is ever sent anywhere.")
            }

            Section {
                Toggle("Remind me when clutter piles up", isOn: $monitor.remindersEnabled)
                Group {
                    Picker("Remind me past", selection: $monitor.thresholdBytes) {
                        ForEach(MonitorSettings.thresholdPresets, id: \.self) { bytes in
                            Text(bytes.fileSize).tag(bytes)
                        }
                    }
                    Picker("How often", selection: $monitor.reminderIntervalDays) {
                        ForEach(MonitorSettings.reminderIntervalOptions, id: \.days) { option in
                            Text(option.label).tag(option.days)
                        }
                    }
                    ReminderTimePicker(monitor: monitor)
                }
                .disabled(!monitor.remindersEnabled)
                if monitor.remindersEnabled { notificationRow }
            } header: {
                Text("Reminders")
            }

            Section("Status") {
                LabeledContent("Last checked", value: monitor.lastCheck.map { Self.dateText($0) } ?? "Not yet")
                LabeledContent("Reclaimable", value: "\(monitor.lastReclaimableBytes.fileSize) of \(monitor.thresholdBytes.fileSize)")
                LabeledContent("Last reminder", value: monitor.lastNotified.map { Self.dateText($0) } ?? "None yet")
                LabeledContent("Next reminder", value: nextReminderText)
                LabeledContent("Test") {
                    Button("Send Test Reminder") { sendTest() }
                        .disabled(notificationStatus != .authorized && notificationStatus != .provisional)
                }
                if let testResult { footnote(testResult) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .task { await refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may have just changed a permission or Login Items in System Settings.
            Task { await refreshStatus() }
        }
        .onChange(of: monitor.showInMenuBar) { _, shown in
            // Hiding the menu bar icon must never leave Swept running with no way to reach it:
            // bring back the window and the Dock icon.
            if !shown { AppWindow.showMain() }
        }
        .onChange(of: monitor.remindersEnabled) { _, on in
            if on { Task { await refreshStatus() } }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
    }

    // MARK: - Rows

    /// Opening at login, as macOS actually reports it (it can be switched off in System Settings).
    @ViewBuilder
    private var loginRow: some View {
        Toggle("Open at login", isOn: Binding(
            get: { loginState != .off },
            set: { loginState = LoginItem.setEnabled($0) }
        ))
        if loginState == .needsApproval {
            LabeledContent("Switched off in Login Items") {
                Button("Open Login Items Settings") { LoginItem.openSystemSettings() }
            }
        }
    }

    /// Reminders need notification permission; make a missing one visible instead of silent.
    @ViewBuilder
    private var notificationRow: some View {
        switch notificationStatus {
        case .notDetermined:
            LabeledContent("Notifications") {
                Button("Allow Notifications") {
                    Task {
                        await MonitorNotifications.requestAuthorization()
                        await refreshStatus()
                    }
                }
            }
        case .denied:
            LabeledContent("Notifications are off") {
                Button("Open System Settings") { MonitorNotifications.openSystemSettings() }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Status text

    private var nextReminderText: String {
        let now = Date()
        guard monitor.remindersEnabled else { return "Reminders are off" }
        if notificationStatus == .denied || notificationStatus == .notDetermined {
            return "Off — notifications not allowed"
        }
        if monitor.lastReclaimableBytes < monitor.thresholdBytes {
            return "When you pass your limit"
        }
        if monitor.isSnoozed(now: now), let until = monitor.snoozedUntil {
            return "Snoozed until \(Self.dateText(until))"
        }
        guard let next = monitor.nextReminderDate(now: now) else { return "At the next check" }
        return next <= now ? "At the next check" : Self.dateText(next)
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    private func refreshStatus() async {
        notificationStatus = await MonitorNotifications.authorizationStatus()
        loginState = LoginItem.state
    }

    /// Posts the real reminder right now, without touching the daily schedule.
    private func sendTest() {
        Task {
            let ok = await MonitorNotifications.postThreshold(reclaimableBytes: monitor.lastReclaimableBytes)
            testResult = ok
                ? "Sent. If no banner appeared, check Focus and System Settings › Notifications › Swept."
                : "macOS didn't accept it. Check System Settings › Notifications › Swept."
        }
    }
}

#Preview {
    SettingsView(monitor: MonitorSettings(defaults: UserDefaults(suiteName: "swept.preview.settings")!))
        .preferredColorScheme(.dark)
}
