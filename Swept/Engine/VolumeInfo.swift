//
//  VolumeInfo.swift
//  Swept
//
//  Cheap volume facts. READ-ONLY.
//

import Foundation

enum VolumeInfo {
    /// Total / free / used bytes for the home volume.
    struct Usage {
        let total: Int64
        let free: Int64
        var used: Int64 { max(0, total - free) }
        var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    /// Reads the home volume's total and free capacity. READ-ONLY.
    static func usage() -> Usage? {
        let url = FileManager.default.homeDirectoryForCurrentUser
        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey, .volumeAvailableCapacityKey
            ]),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacity
        else { return nil }
        return Usage(total: Int64(total), free: Int64(max(0, available)))
    }

    /// Denominator for the summary bar. A precise "System Data" figure isn't cheaply
    /// available, so we APPROXIMATE it as the total space used on the home volume
    /// (capacity − available). Documented as an approximation per spec §6.
    static func approxSystemData() -> Int64? {
        usage().map(\.used)
    }
}
