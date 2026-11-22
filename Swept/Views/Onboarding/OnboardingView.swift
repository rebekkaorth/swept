//
//  OnboardingView.swift
//  Swept
//
//  The Full Disk Access gate. On macOS 26 (Tahoe) reading other apps' caches and
//  data requires FDA, so this screen is shown every launch until access is present.
//  It only guides the user to grant access — the router auto-advances once it is.
//

import SwiftUI
import AppKit

struct OnboardingView: View {
    /// Shown after the user has returned with FDA still off (Tahoe often needs a relaunch).
    var showRelaunchHint: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 82, height: 82)

            Text("Welcome to Swept")
                .font(Typography.titleXL)
                .foregroundStyle(Theme.textPrimary)

            Text("Swept finds leftover caches and data that other apps have piled up. To see them, macOS needs you to give Swept Full Disk Access.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)

            privacyBanner

            steps

            if showRelaunchHint {
                Text("Still not detected? Quit and reopen Swept.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.caution)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Text("Access is revocable anytime in System Settings › Privacy & Security › Full Disk Access. Swept only reads to show you sizes, and never sends anything anywhere.")
                .font(Typography.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
        .animation(Theme.Motion.standard, value: showRelaunchHint)
    }

    // MARK: - How-to-grant steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                stepBadge(1)
                Button {
                    openFullDiskAccess()
                } label: {
                    Text("Open Full Disk Access Settings")
                        .frame(maxWidth: 300)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            stepRow(2, "Turn on the switch next to Swept.")
            stepRow(3, "If prompted, quit and reopen Swept.")
        }
        .frame(maxWidth: 440, alignment: .leading)
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            stepBadge(number)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private func stepBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.accent)
            .frame(width: 24, height: 24)
            .background(Theme.accent.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }

    private var privacyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.safe)
            Text("Everything happens on your Mac. Nothing is ever sent anywhere.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 440)
        .background(Theme.safe.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.safe.opacity(0.22), lineWidth: 1)
        )
    }

    private func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview("Gate") {
    OnboardingView()
        .frame(width: 1000, height: 720)
        .preferredColorScheme(.dark)
}

#Preview("Gate · relaunch hint") {
    OnboardingView(showRelaunchHint: true)
        .frame(width: 1000, height: 720)
        .preferredColorScheme(.dark)
}
