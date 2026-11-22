//
//  ByteFormatting.swift
//  Swept
//
//  Central file-size formatting so numbers read consistently everywhere.
//

import Foundation

enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    /// e.g. "18.4 GB".
    static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }

    /// Splits a formatted size into its numeric value and unit, e.g. ("87.4", "GB").
    static func parts(_ bytes: Int64) -> (value: String, unit: String) {
        let formatted = string(bytes)
        let pieces = formatted.split(separator: " ", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { return (formatted, "") }
        return (pieces[0], pieces[1])
    }
}

extension Int64 {
    /// Convenience: this byte count as a formatted file size (e.g. "24.4 GB").
    var fileSize: String { ByteFormat.string(self) }
}
