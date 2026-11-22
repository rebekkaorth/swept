//
//  ActionBar.swift
//  Swept
//
//  Sits below the item list INSIDE the content column only (never under the
//  inspector). Shows the live selection tally and the Review & Delete action.
//

import SwiftUI

struct ActionBar: View {
    let model: ScanModel

    @State private var showReview = false

    private var isEmpty: Bool { model.checked.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            tally
            Spacer()
            Button {
                showReview = true
            } label: {
                Text("Review & Delete")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .disabled(isEmpty)
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: 58)
        .background(Theme.barBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .sheet(isPresented: $showReview) {
            ReviewDeleteSheet(model: model, isPresented: $showReview)
        }
    }

    @ViewBuilder
    private var tally: some View {
        if isEmpty {
            Text("0 selected")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
        } else {
            HStack(spacing: 0) {
                Text("\(model.checked.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(" selected · ")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Text(model.selectedBytes.fileSize)
                    .font(.system(size: 13, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
            }
        }
    }
}

#Preview {
    let model = ScanModel.mock
    return VStack(spacing: 20) {
        ActionBar(model: model)
        ActionBar(model: {
            let m = ScanModel.mock
            m.checked = Set(m.categories[0].items.prefix(3).map(\.id))
            return m
        }())
    }
    .frame(width: 620)
    .background(Theme.windowBackground)
    .preferredColorScheme(.dark)
}
