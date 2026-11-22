//
//  MenuBarPopoverView.swift
//  Swept
//
//  Menu-bar popover. Two mutually exclusive states: scanning vs. idle.
//  Review-first: there is deliberately NO delete/clean action here.
//

import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    let monitor: MonitorSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if monitor.isChecking {
                scanningState
            } else {
                idleState
            }
            Divider().overlay(Theme.hairline)
            HStack {
                Spacer()
                Button("Quit Swept") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }

    // MARK: - Scanning

    private var scanningState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning your files…")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            if !monitor.currentPath.isEmpty {
                Text(monitor.currentPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .truncationTooltip(monitor.currentPath)
            }
        }
    }

    // MARK: - Idle

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 14) {
            thresholdSummary
            if !monitor.topCategories.isEmpty {
                Divider().overlay(Theme.hairline)
                topCategories
            }
            Divider().overlay(Theme.hairline)
            footer
        }
    }

    private var fraction: Double {
        guard monitor.thresholdBytes > 0 else { return 0 }
        return min(1, Double(monitor.lastReclaimableBytes) / Double(monitor.thresholdBytes))
    }

    private var thresholdSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: fraction)
                .tint(Theme.accent)
            Text("\(monitor.lastReclaimableBytes.fileSize) of your \(monitor.thresholdBytes.fileSize) limit piled up")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var topCategories: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Biggest culprits")
                .uppercaseLabelStyle()
            ForEach(monitor.topCategories, id: \.kind) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.kind.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 18)
                    Text(entry.kind.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationTooltip(entry.kind.title)
                    Spacer(minLength: 8)
                    Text(entry.bytes.fileSize)
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lastCheckedLine)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)

            HStack(spacing: 8) {
                Button("Snooze for a week") {
                    monitor.snoozeForAWeek(from: Date())
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer(minLength: 0)

                Button("Review in Swept") {
                    reviewInSwept()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.regular)
            }
        }
    }

    // MARK: - Actions

    private func reviewInSwept() {
        AppWindow.showMain()    // restore Dock icon + main window
        monitor.requestReview() // main window observes this to start a full scan
    }

    private var lastCheckedLine: String {
        guard let lastCheck = monitor.lastCheck else { return "Not checked yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last checked \(formatter.localizedString(for: lastCheck, relativeTo: Date()))"
    }
}

// MARK: - Previews

private func previewMonitor(configure: (MonitorSettings) -> Void) -> MonitorSettings {
    let m = MonitorSettings(defaults: UserDefaults(suiteName: "swept.preview.popover")!)
    configure(m)
    return m
}

#Preview("Idle") {
    MenuBarPopoverView(monitor: previewMonitor { m in
        m.thresholdBytes = 25_000_000_000
        m.lastReclaimableBytes = 14_200_000_000
        m.lastCheck = Date(timeIntervalSinceNow: -2 * 60 * 60)
        m.topCategories = [
            CategorySize(kind: .applicationSupport, bytes: 8_100_000_000),
            CategorySize(kind: .xcodeSimulators, bytes: 4_300_000_000),
            CategorySize(kind: .appCaches, bytes: 1_800_000_000),
        ]
    })
    .preferredColorScheme(.dark)
}

#Preview("Scanning") {
    MenuBarPopoverView(monitor: previewMonitor { m in
        m.isChecking = true
        m.currentPath = "~/Library/Application Support/Claude/vm_bundles/claudevm.bundle"
    })
    .preferredColorScheme(.dark)
}
