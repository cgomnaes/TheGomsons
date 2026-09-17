//
//  AppDataBackup.swift
//  TheGomsons
//

import Foundation
import SwiftData

/// Copies the on-device SwiftData store folder into Documents and/or iCloud Drive.
enum AppDataBackup {
    /// Matches `CloudDataManager`’s Application Support subfolder.
    private static let storeFolderName = "TheGomsons"
    private static let cloudKitContainerID = "iCloud.com.gomnaes.TheGomsons"
    private static let localBackupsFolderName = "TheGomsonsBackups"
    private static let iCloudBackupsFolderName = "MonthlyBackups"

    private static let lastMonthlyBackupKey = "appDataBackup.lastMonthlyBackupAt"
    private static let monthlyEnabledKey = "appDataBackup.monthlyICloudEnabled"
    private static let lastMonthlyErrorKey = "appDataBackup.lastMonthlyError"
    private static let lastMonthlyDestinationKey = "appDataBackup.lastMonthlyDestination"

    /// Keep this many monthly iCloud snapshots (oldest pruned).
    static let monthlyRetentionCount = 6
    /// Run a new monthly backup when at least this many days have passed.
    static let monthlyIntervalDays = 30

    enum Destination: String, Sendable {
        case localDocuments
        case iCloudDrive
    }

    static var sourceFolderURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent(storeFolderName, isDirectory: true)
    }

    // MARK: - Preferences

    static var monthlyICloudBackupsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: monthlyEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: monthlyEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: monthlyEnabledKey) }
    }

    static var lastMonthlyBackupDate: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: lastMonthlyBackupKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: lastMonthlyBackupKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastMonthlyBackupKey)
            }
        }
    }

    static var lastMonthlyBackupError: String? {
        get { UserDefaults.standard.string(forKey: lastMonthlyErrorKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: lastMonthlyErrorKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastMonthlyErrorKey)
            }
        }
    }

    static var lastMonthlyBackupPath: String? {
        get { UserDefaults.standard.string(forKey: lastMonthlyDestinationKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: lastMonthlyDestinationKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastMonthlyDestinationKey)
            }
        }
    }

    static var isMonthlyBackupDue: Bool {
        guard monthlyICloudBackupsEnabled else { return false }
        guard let last = lastMonthlyBackupDate else { return true }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return days >= monthlyIntervalDays
    }

    static var daysUntilNextMonthlyBackup: Int? {
        guard let last = lastMonthlyBackupDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return max(0, monthlyIntervalDays - days)
    }

    // MARK: - Directories

    static func exportsDirectoryURL() throws -> URL {
        let url = URL.documentsDirectory.appendingPathComponent(localBackupsFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// iCloud Drive container Documents folder (appears under Files → iCloud Drive → The Gomsons).
    static func iCloudBackupsDirectoryURL() throws -> URL {
        let fm = FileManager.default
        guard let container = fm.url(forUbiquityContainerIdentifier: cloudKitContainerID) else {
            throw AppDataBackupError.iCloudUnavailable
        }
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        let backups = documents.appendingPathComponent(iCloudBackupsFolderName, isDirectory: true)
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
        return backups
    }

    static var iCloudDriveAvailable: Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: cloudKitContainerID) != nil
    }

    // MARK: - Export

    /// Manual export to On My iPhone → The Gomsons → TheGomsonsBackups.
    static func createTimestampedExport(modelContext: ModelContext) throws -> URL {
        try createBackup(modelContext: modelContext, destination: .localDocuments, kind: "manual")
    }

    /// Monthly snapshot into iCloud Drive (also records success timestamp).
    @discardableResult
    static func createMonthlyICloudBackup(modelContext: ModelContext) throws -> URL {
        let url = try createBackup(modelContext: modelContext, destination: .iCloudDrive, kind: "monthly")
        lastMonthlyBackupDate = Date()
        lastMonthlyBackupError = nil
        lastMonthlyBackupPath = url.lastPathComponent
        try pruneICloudMonthlyBackups(keeping: monthlyRetentionCount)
        return url
    }

    /// If monthly backups are enabled and due, write one to iCloud Drive. Returns the folder URL when a backup ran.
    @discardableResult
    static func performMonthlyBackupIfNeeded(modelContext: ModelContext) -> URL? {
        guard monthlyICloudBackupsEnabled, isMonthlyBackupDue else { return nil }
        do {
            return try createMonthlyICloudBackup(modelContext: modelContext)
        } catch {
            lastMonthlyBackupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("[TheGomsons] Monthly iCloud backup failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func createBackup(
        modelContext: ModelContext,
        destination: Destination,
        kind: String
    ) throws -> URL {
        try modelContext.save()

        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceFolderURL.path) else {
            throw AppDataBackupError.sourceMissing
        }

        let parent: URL
        switch destination {
        case .localDocuments:
            parent = try exportsDirectoryURL()
        case .iCloudDrive:
            parent = try iCloudBackupsDirectoryURL()
        }

        let stamp = backupTimestampString()
        let folderName = destination == .iCloudDrive
            ? "TheGomsons_monthly_\(stamp)"
            : "TheGomsons_backup_\(stamp)"
        let dest = parent.appendingPathComponent(folderName, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: sourceFolderURL, to: dest)

        let exportedAt = ISO8601DateFormatter().string(from: Date())
        let manifest: [String: Any] = [
            "app": "TheGomsons",
            "exportedAt": exportedAt,
            "format": "swiftdata-store-copy",
            "kind": kind,
            "destination": destination.rawValue,
            "sourceFolder": storeFolderName,
            "note": destination == .iCloudDrive
                ? "Monthly full-data snapshot in iCloud Drive. Restore only with matching app schema; quit the app before replacing local data."
                : "Full local data snapshot. Restore only on a copy of the app with the same schema; quit the app first for the safest replace.",
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try manifestData.write(to: dest.appendingPathComponent("backup_manifest.json"), options: .atomic)

        // Hint iCloud to upload promptly for Drive copies.
        if destination == .iCloudDrive {
            var values = URLResourceValues()
            values.isExcludedFromBackup = false
            var destVar = dest
            try? destVar.setResourceValues(values)
            try? fm.startDownloadingUbiquitousItem(at: dest)
        }

        return dest
    }

    // MARK: - Listing / pruning

    static func listExports(newestFirst: Bool = true) -> [URL] {
        listBackupFolders(in: (try? exportsDirectoryURL()), newestFirst: newestFirst)
    }

    static func listICloudMonthlyExports(newestFirst: Bool = true) -> [URL] {
        listBackupFolders(in: (try? iCloudBackupsDirectoryURL()), newestFirst: newestFirst)
    }

    private static func listBackupFolders(in dir: URL?, newestFirst: Bool) -> [URL] {
        guard let dir,
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: dir,
                  includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                  options: [.skipsHiddenFiles]
              )
        else { return [] }

        let dirs = urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        return dirs.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return newestFirst ? (da > db) : (da < db)
        }
    }

    static func pruneICloudMonthlyBackups(keeping limit: Int) throws {
        let items = listICloudMonthlyExports(newestFirst: true)
        guard items.count > limit else { return }
        for url in items.dropFirst(limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private nonisolated static func backupTimestampString() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }
}

enum AppDataBackupError: LocalizedError {
    case sourceMissing
    case iCloudUnavailable

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            return "The local data folder was not found yet. Open the app once, then try again."
        case .iCloudUnavailable:
            return "iCloud Drive is not available. Sign in to iCloud in Settings and enable iCloud Drive."
        }
    }
}
