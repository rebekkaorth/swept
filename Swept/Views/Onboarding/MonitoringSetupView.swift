//
//  MonitoringSetupView.swift
//  Swept
//
//  Three-step setup, shown after the first scan and from the sidebar ("Set up reminders"):
//    1. Set your limit                      ("Skip reminders" jumps to step 3)
//    2. Choose your reminders (how often + what time), then the notification permission
//    3. Open Swept at login? — always asked, even when reminders were skipped. "Add to Login
//       Items" registers Swept and opens System Settings so the user sees the result.
//  Each step explains the value BEFORE any system prompt. No networking.
//

import SwiftUI
import UserNotifications

struct MonitoringSetupView: View {
    @Bindable var monitor: MonitorSettings
    /// Called when the flow is finished or skipped (dismisses the sheet).
    var onFinish: () -> Void

    @State private var step = 1
    @State private var requesting = false
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var loginState: LoginItem.State = LoginItem.state
    /// True once the user pressed "Add to Login Items" here (switches step 3 to its confirmation).
    @State private var addedLoginItem = false

    private let stepCount = 3

    var body: some View {
        VStack(spacing: 20) {
            Text("Step \(step) of \(stepCount)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            content
                .frame(maxWidth: 380)
            footer
        }
        .padding(28)
        .frame(width: 460)
        .background(Theme.windowBackground)
        .animation(Theme.Motion.standard, value: step)
        .task { notificationStatus = await MonitorNotifications.authorizationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from System Settings: pick up a Login Items / notification change.
            loginState = LoginItem.state
            Task { notificationStatus = await MonitorNotifications.authorizationStatus() }
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case 1: limitStep
        case 2: remindersStep
        default: loginStep
        }
    }

    private var limitStep: some View {
        stepScaffold(
            symbol: "slider.horizontal.3",
            title: "Set your limit",
            body: "Swept can keep an eye on your Mac in the background and remind you once clutter piles up past a limit you choose. Everything stays on your Mac."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Remind me when Swept can reclaim more than")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Picker("Limit", selection: $monitor.thresholdBytes) {
                    ForEach(MonitorSettings.thresholdPresets, id: \.self) { bytes in
                        Text(bytes.fileSize).tag(bytes)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var remindersStep: some View {
        stepScaffold(
            symbol: "bell",
            title: "Choose your reminders",
            body: "While clutter stays over your limit, Swept sends one calm notification at the time you pick. If your Mac is asleep then, it comes shortly after it wakes. You can snooze reminders for a week any time."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("How often", selection: $monitor.reminderIntervalDays) {
                    ForEach(MonitorSettings.reminderIntervalOptions, id: \.days) { option in
                        Text(option.label).tag(option.days)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ReminderTimePicker(monitor: monitor)

                if notificationStatus == .denied {
                    deniedNote
                }
            }
        }
    }

    private var loginStep: some View {
        stepScaffold(
            symbol: "power",
            title: addedLoginItem ? "Swept opens at login" : "Open Swept at login?",
            body: addedLoginItem
                ? "Swept is now in System Settings › General › Login Items & Extensions, which just opened so you can see it. After a restart it starts quietly in the background. You can remove it there or switch it off in Swept's Settings any time."
                : "Swept can start by itself when you log in, quietly and without opening a window, so it keeps watching after a restart. It's added to your Mac's Login Items, where you can see and remove it any time."
        ) {
            switch loginState {
            case .needsApproval:
                VStack(spacing: 8) {
                    Label("macOS needs your OK: switch on Swept in Login Items.", systemImage: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.caution)
                    Button("Open Login Items Settings") { LoginItem.openSystemSettings() }
                        .controlSize(.small)
                }
            case .on:
                Label("Swept will open at login", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
            case .off:
                EmptyView()
            }
        }
    }

    private var deniedNote: some View {
        HStack(spacing: 8) {
            Text("Notifications for Swept are off, so reminders can't appear.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Button("Open System Settings") { MonitorNotifications.openSystemSettings() }
                .controlSize(.small)
        }
    }

    private func stepScaffold<Extra: View>(
        symbol: String,
        title: String,
        body: String,
        @ViewBuilder extra: () -> Extra
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.accent)
                .symbolRenderingMode(.hierarchical)
                .frame(height: 44)

            Text(title)
                .font(Typography.title)
                .foregroundStyle(Theme.textPrimary)

            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            extra()
                .padding(.top, 2)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step > 1 {
                Button("Back") { withAnimation(Theme.Motion.standard) { step -= 1 } }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Spacer()

            if !secondaryTitle.isEmpty {
                Button(secondaryTitle) { secondaryAction() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Button(primaryTitle) { primaryAction() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .disabled(requesting)
        }
        .frame(maxWidth: 400)
    }

    private var needsNotificationPrompt: Bool {
        notificationStatus == nil || notificationStatus == .notDetermined
    }

    private var primaryTitle: String {
        switch step {
        case 1: "Continue"
        case 2: needsNotificationPrompt ? "Allow notifications" : "Continue"
        default: loginState == .off ? "Add to Login Items" : "Done"
        }
    }

    private var secondaryTitle: String {
        switch step {
        case 1: "Skip reminders"
        case 2: needsNotificationPrompt ? "Skip notifications" : ""
        default: loginState == .off ? "Not now" : ""
        }
    }

    private func next() { go(to: step + 1) }
    private func go(to newStep: Int) { withAnimation(Theme.Motion.standard) { step = newStep } }

    private func primaryAction() {
        switch step {
        case 1:
            next()
        case 2:
            monitor.remindersEnabled = true
            guard needsNotificationPrompt else { return next() }
            // Explained first (this step), THEN the system prompt. Denial is fine:
            // the menu bar icon still shows when you're over the limit.
            requesting = true
            Task {
                await MonitorNotifications.requestAuthorization()
                notificationStatus = await MonitorNotifications.authorizationStatus()
                requesting = false
                next()
            }
        default:
            guard loginState == .off else { return onFinish() }
            // Add Swept, then show the user where it went.
            loginState = LoginItem.setEnabled(true)
            addedLoginItem = true
            LoginItem.openSystemSettings()
        }
    }

    private func secondaryAction() {
        switch step {
        case 1:
            go(to: 3) // skip reminders, but still ask about opening at login
        case 2:
            monitor.remindersEnabled = true // reminders on; notifications can be allowed later in Settings
            next()
        default:
            onFinish()
        }
    }
}

/// Hour + minute picker bound to `MonitorSettings.reminderMinutes`.
struct ReminderTimePicker: View {
    @Bindable var monitor: MonitorSettings

    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: monitor.reminderMinutes / 60,
                                  minute: monitor.reminderMinutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            monitor.reminderMinutes = (parts.hour ?? 10) * 60 + (parts.minute ?? 0)
        }
    }

    var body: some View {
        DatePicker("Remind me at", selection: time, displayedComponents: .hourAndMinute)
            .font(.system(size: 13))
    }
}

#Preview {
    MonitoringSetupView(
        monitor: MonitorSettings(defaults: UserDefaults(suiteName: "swept.preview.setup")!),
        onFinish: {}
    )
    .preferredColorScheme(.dark)
}
