//
//  ScanningView.swift
//  Swept
//
//  Calm, branded progress while a scan runs. No aggressive spinners.
//

import SwiftUI

struct ScanningView: View {
    let model: ScanModel
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            glow

            VStack(spacing: 8) {
                Text("Scanning…")
                    .font(Typography.title)
                    .foregroundStyle(Theme.textPrimary)

                Text(model.currentPath.isEmpty ? " " : model.currentPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 340)
            }

            progressBar
                .frame(width: 300)

            Button("Cancel") { onCancel() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction) // esc

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
        .onAppear { if !reduceMotion { pulse = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scanning. \(Int((model.scanProgress * 100).rounded())) percent complete.")
    }

    // Soft pulsing glow behind a sweeping icon. Honors Reduce Motion (stays still).
    private var glow: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.22))
                .frame(width: 120, height: 120)
                .blur(radius: 26)
                .scaleEffect(reduceMotion ? 1.0 : (pulse ? 1.15 : 0.85))
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                           value: pulse)

            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.accent)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(height: 120)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.trackFill)
                Capsule()
                    .fill(LinearGradient(
                        colors: [Theme.accent, Color(hex: 0x5EB4FF)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * max(0, min(model.scanProgress, 1)))
            }
        }
        .frame(height: 5)
    }
}

#Preview {
    let model = ScanModel()
    model.isScanning = true
    model.scanProgress = 0.45
    model.currentPath = "~/Library/Developer/Xcode/DerivedData"
    return ScanningView(model: model, onCancel: {})
        .frame(width: 1000, height: 700)
        .preferredColorScheme(.dark)
}
