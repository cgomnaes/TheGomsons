//
//  AppDataBackup.swift
//  TheGomsons
//

import Foundation
import SwiftData

/// Copies the on-device SwiftData store folder (same layout as `CloudDataManager`) into Documents with a timestamped name and manifest.
enum AppDataBackup {
    /// Matches `CloudDataManager`’s Application Support subfolder.
    private static let storeFolderName = "TheGomsons"

    static var sourceFolderURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent(storeFolderName, isDirectory: true)
    }

    static func exportsDirectoryURL() throws -> URL {
        let url = URL.documentsDirectory.appendingPathComponent("TheGomsonsBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Flushes SwiftData, then copies the whole store directory and writes `backup_manifest.json` with ISO-8601 timestamps.
    static func createTimestampedExport(modelContext: ModelContext) throws -> URL {
        try modelContext.save()

        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceFolderURL.path) else {
            throw AppDataBackupError.sourceMissing
        }

        let stamp = backupTimestampString()
        let dest = try exportsDirectoryURL().appendingPathComponent("TheGomsons_backup_\(stamp)", isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: sourceFolderURL, to: dest)

        let exportedAt = ISO8601DateFormatter().string(from: Date())
        let manifest: [String: Any] = [
            "app": "TheGomsons",
            "exportedAt": exportedAt,
            "format": "swiftdata-store-copy",
            "sourceFolder": storeFolderName,
            "note": "Full local data snapshot. Restore only on a copy of the app with the same schema; quit the app first for the safest replace.",
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try manifestData.write(to: dest.appendingPathComponent("backup_manifest.json"), options: .atomic)

        return dest
    }

    static func listExports(newestFirst: Bool = true) -> [URL] {
        guard let dir = try? exportsDirectoryURL(),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: dir,
                  includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        let dirs = urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        return dirs.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return newestFirst ? (da > db) : (da < db)
        }
    }

    private static func backupTimestampString() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }
}

enum AppDataBackupError: LocalizedError {
    case sourceMissing

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            return "The local data folder was not found yet. Open the app once, then try again."
        }
    }
}
