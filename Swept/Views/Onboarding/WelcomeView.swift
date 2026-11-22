//
//  WelcomeView.swift
//  Swept
//
//  First-launch welcome. Explains what Swept does and waits for the user to start the first
//  scan themselves — nothing is read before they press the button. If Full Disk Access is
//  still missing, the router shows the access gate next. No networking.
//

import SwiftUI
import AppKit

struct WelcomeView: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)

            Text("Welcome to Swept")
                .font(Typography.titleXL)
                .foregroundStyle(Theme.textPrimary)

            Text("Over time, apps leave caches, logs and leftovers in hidden corners of your Mac. Swept finds them, explains each one, and only cleans what you choose.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                point("magnifyingglass", "The first scan only looks. Nothing is deleted.")
                point("trash", "What you clean goes to the Trash, so you can put it back.")
                point("checkmark.shield", "Everything happens on your Mac. Nothing is ever sent anywhere.")
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(.vertical, 4)

            Button(action: onStart) {
                Text("Scan My Mac")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Text("Swept will ask for Full Disk Access if it doesn't have it yet.")
                .font(Typography.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

#Preview {
    WelcomeView(onStart: {})
        .frame(width: 1000, height: 720)
        .preferredColorScheme(.dark)
}
