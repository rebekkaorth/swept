//
//  _RealScanPreview.swift
//  Swept
//
//  TEMPORARY: renders the Main screen with a REAL read-only scan of this Mac
//  (runs synchronously at preview build time). Delete once no longer needed.
//

#if DEBUG
import SwiftUI

#Preview("Real scan · App Support") {
    let model = ScanModel(
        categories: FileSystemScanner().scanBlocking(),
        totalSystemData: VolumeInfo.approxSystemData()
    )
    // Focus the Application Support category so the Claude items are visible.
    if let appSupport = model.categories.first(where: { $0.kind == .applicationSupport }) {
        model.selectCategory(appSupport.id)
        if let vm = appSupport.items.first(where: { $0.badge == .virtualMachine }) {
            model.selectedItem = vm.id
        }
    }
    return MainSplitView(model: model)
        .frame(width: 1160, height: 762)
        .preferredColorScheme(.dark)
}

#Preview("Real scan · Downloads") {
    let model = ScanModel(
        categories: FileSystemScanner().scanBlocking(),
        totalSystemData: VolumeInfo.approxSystemData()
    )
    if let downloads = model.categories.first(where: { $0.kind == .downloads }) {
        model.selectCategory(downloads.id)
    }
    return MainSplitView(model: model)
        .frame(width: 1160, height: 762)
        .preferredColorScheme(.dark)
}
#endif
