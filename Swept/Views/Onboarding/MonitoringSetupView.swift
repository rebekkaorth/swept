//
//  MonitoringSetupView.swift
//  Swept
//
//  Three-step, value-first setup for background monitoring. Reachable from first-run
//  onboarding (optional, skippable) and from the main window. Each step explains the
//  value BEFORE any system prompt. No networking.
//

import SwiftUI

struct MonitoringSetupView: View {
    @Bindable var monitor: MonitorSettings
    /// Called when the flow is finished or skipped (dismisses the sheet).
    var onFinish: () -> Void

    @State private var step = 1
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 20) {
            content
                .frame(maxWidth: 380)
            footer
        }
        .padding(28)
        .frame(width: 440)
        .background(Theme.windowBackground)
        .animation(Theme.Motion.standard, value: step)
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case 1: keepAnEyeStep
        case 2: setYourLimitStep
        default: oneCalmNotificationStep
        }
    }

    private var keepAnEyeStep: some View {
        stepScaffold(
            symbol: "menubar.rectangle",
            title: "Keep an eye on things",
            body: "Swept can watch your reclaimable storage in the background and show a calm icon in your menu bar. It adds itself to Login Items — visible anytime in System Settings › General › Login Items — so it keeps watch after you restart. Everything stays on your Mac.\n\nWhen you close the window, Swept keeps watching quietly from the menu bar. Quit anytime from the menu bar icon."
        ) {
            EmptyView()
        }
    }

    private var setYourLimitStep: some View {
        stepScaffold(
            symbol: "slider.horizontal.3",
            title: "Set your limit",
            body: "Swept will only nudge you once things really pile up."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notify me when Swept can reclaim more than")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Picker("", selection: $monitor.thresholdBytes) {
                    ForEach(MonitorSettings.thresholdPresets, id: \.self) { bytes in
                        Text(bytes.fileSize).tag(bytes)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var oneCalmNotificationStep: some View {
        stepScaffold(
            symbol: "bell",
            title: "Get one calm notification",
            body: "While clutter stays over your limit, Swept reminds you at most once a day. You can snooze it for a week whenever you like. Swept never sends anything anywhere."
        ) {
            EmptyView()
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

            Button(secondaryTitle) { onFinish() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Button(primaryTitle) { primaryAction() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .disabled(requesting)
        }
        .frame(maxWidth: 380)
    }

    private var primaryTitle: String {
        switch step {
        case 1: "Turn on monitoring"
        case 2: "Continue"
        default: "Enable notifications"
        }
    }

    private var secondaryTitle: String {
        step == 3 ? "Skip notifications" : "Not now"
    }

    private func primaryAction() {
        switch step {
        case 1:
            monitor.isEnabled = true // adds the menu-bar item and registers the login item
            withAnimation(Theme.Motion.standard) { step = 2 }
        case 2:
            withAnimation(Theme.Motion.standard) { step = 3 }
        default:
            // Explain first (this step), THEN trigger the system prompt. Denial is fine —
            // monitoring stays on in menu-bar-only mode.
            requesting = true
            Task {
                await MonitorNotifications.requestAuthorization()
                requesting = false
                onFinish()
            }
        }
    }
}

#Preview {
    MonitoringSetupView(
        monitor: MonitorSettings(defaults: UserDefaults(suiteName: "swept.preview.setup")!),
        onFinish: {}
    )
    .preferredColorScheme(.dark)
}
