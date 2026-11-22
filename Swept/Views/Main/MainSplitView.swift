//
//  MainSplitView.swift
//  Swept
//
//  Three-column layout: sidebar · content · inspector.
//

import SwiftUI

struct MainSplitView: View {
    let model: ScanModel
    var onScanAgain: () -> Void = {}
    /// Non-nil only when background monitoring is off — shows the "turn it on" affordance.
    var onTurnOnMonitoring: (() -> Void)? = nil

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model, onScanAgain: onScanAgain, onTurnOnMonitoring: onTurnOnMonitoring)
                .navigationSplitViewColumnWidth(min: 240, ideal: 246, max: 300)
        } content: {
            ContentPaneView(model: model)
                .navigationSplitViewColumnWidth(min: 480, ideal: 560)
        } detail: {
            InspectorView(model: model)
                .navigationSplitViewColumnWidth(min: 280, ideal: 302, max: 360)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#Preview {
    MainSplitView(model: .mock)
        .frame(width: 1160, height: 762)
        .preferredColorScheme(.dark)
}
