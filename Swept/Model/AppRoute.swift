//
//  AppRoute.swift
//  Swept
//
//  Top-level screens the app switches between.
//

import Foundation

enum AppRoute {
    case welcome      // first launch: hello + "Scan My Mac", before any scan runs
    case onboarding   // Full Disk Access gate
    case scanning
    case main
    case empty
}
