//
//  DataBackupSettingsView.swift
//  TheGomsons
//

import CloudKit
import SwiftData
import SwiftUI
import UIKit

/// Export a full timestamped copy of local SwiftData data (share via Files, AirDrop, etc.).
struct DataBackupSettingsView: View {
    @EnvironmentObject private var cloud: CloudDataManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isExporting = false
    @State private var isRunningMonthly = false
    @State private var exportError: String?
    @State private var statusMessage: String?
    @State private var sharePayload: SharePayload?
    @State private var refreshToken = UUID()
    @State private var monthlyEnabled = AppDataBackup.monthlyICloudBackupsEnabled

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let status = cloud.cloudKitAccountStatus {
                        LabeledContent(String(localized: "icloud.label")) {
                            Text(cloud.cloudKitAccountStatusDescription(for: status))
                                .font(.subheadline)
                                .foregroundStyle(status == .available ? .primary : .secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        Button(String(localized: "icloud.refresh")) {
                            cloud.refreshCloudKitAccountStatus()
                        }
                        .font(.subheadline)
                    } else {
                        HStack {
                            ProgressView()
                            Text(String(localized: "icloud.checking"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(CloudDataManager.sharedFamilyDataFootnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CloudDataManager.syncBuildEnvironmentFootnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CloudDataManager.simulatorICloudFootnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if cloud.pendingDeferredSwiftDataReload {
                        Text(String(localized: "sync.pending_reload_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let syncError = cloud.lastCloudKitSyncErrorMessage {
                        Text(syncError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let detail = cloud.lastCloudKitSyncErrorDetail,
                       detail != cloud.lastCloudKitSyncErrorMessage {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Button(String(localized: "sync.reload_local")) {
                        cloud.refreshFamilyDataFromStore()
                        refreshToken = UUID()
                    }
                    .font(.subheadline)
                } header: {
                    Text(String(localized: "sync.family"))
                }

                Section {
                    Toggle(isOn: $monthlyEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "export.monthly_toggle"))
                            Text(String(localized: "export.monthly_toggle_detail"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: monthlyEnabled) { _, newValue in
                        AppDataBackup.monthlyICloudBackupsEnabled = newValue
                    }

                    LabeledContent(String(localized: "export.monthly_last")) {
                        Text(lastMonthlyText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    if let days = AppDataBackup.daysUntilNextMonthlyBackup, AppDataBackup.lastMonthlyBackupDate != nil {
                        LabeledContent(String(localized: "export.monthly_next")) {
                            Text(
                                days == 0
                                    ? String(localized: "export.monthly_due_now")
                                    : String(format: String(localized: "export.monthly_in_days_fmt"), locale: .current, days)
                            )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let err = AppDataBackup.lastMonthlyBackupError, !err.isEmpty {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text(
                        String(
                            format: String(localized: "export.monthly_files_footer_fmt"),
                            locale: .current,
                            AppDataBackup.monthlyRetentionCount
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await runMonthlyNow() }
                    } label: {
                        if isRunningMonthly {
                            HStack {
                                ProgressView()
                                Text(String(localized: "export.monthly_backing_up"))
                            }
                        } else {
                            Label(String(localized: "export.monthly_backup_now"), systemImage: "icloud.and.arrow.up")
                        }
                    }
                    .disabled(isRunningMonthly || isExporting || !AppDataBackup.iCloudDriveAvailable)
                } header: {
                    Text(String(localized: "export.automatic_section"))
                }

                Section {
                    Text(String(localized: "export.backup_description"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section(String(localized: "export.section")) {
                    Button {
                        Task { await exportBackup() }
                    } label: {
                        if isExporting {
                            HStack {
                                ProgressView()
                                Text(String(localized: "export.preparing"))
                            }
                        } else {
                            Label(String(localized: "export.backup_now"), systemImage: "arrow.down.doc.fill")
                        }
                    }
                    .disabled(isExporting || isRunningMonthly)
                }

                Section(String(localized: "export.monthly_list_section")) {
                    let items = AppDataBackup.listICloudMonthlyExports()
                    if items.isEmpty {
                        Text(String(localized: "export.monthly_none"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items, id: \.path) { url in
                            Button {
                                sharePayload = SharePayload(url: url)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(url.lastPathComponent)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if let date = modificationDate(of: url) {
                                        Text(date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section(String(localized: "export.recent")) {
                    let items = AppDataBackup.listExports()
                    if items.isEmpty {
                        Text(String(localized: "export.none"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items, id: \.path) { url in
                            Button {
                                sharePayload = SharePayload(url: url)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(url.lastPathComponent)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if let date = modificationDate(of: url) {
                                        Text(date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section(String(localized: "export.about_restore")) {
                    Text(String(localized: "export.restore_note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .id(refreshToken)
            .navigationTitle(String(localized: "data_backup.title"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                cloud.refreshCloudKitAccountStatus()
                monthlyEnabled = AppDataBackup.monthlyICloudBackupsEnabled
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
            .alert(String(localized: "data_backup.export_failed"), isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheetView(items: [payload.url])
            }
        }
    }

    private var lastMonthlyText: String {
        if let date = AppDataBackup.lastMonthlyBackupDate {
            var text = date.formatted(date: .abbreviated, time: .shortened)
            if let name = AppDataBackup.lastMonthlyBackupPath {
                text += " · \(name)"
            }
            return text
        }
        return String(localized: "export.monthly_never")
    }

    private func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func exportBackup() async {
        await MainActor.run {
            isExporting = true
            exportError = nil
            statusMessage = nil
        }
        do {
            let url = try AppDataBackup.createTimestampedExport(modelContext: modelContext)
            await MainActor.run {
                isExporting = false
                refreshToken = UUID()
                sharePayload = SharePayload(url: url)
            }
        } catch {
            await MainActor.run {
                isExporting = false
                exportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func runMonthlyNow() async {
        await MainActor.run {
            isRunningMonthly = true
            exportError = nil
            statusMessage = nil
        }
        do {
            let url = try AppDataBackup.createMonthlyICloudBackup(modelContext: modelContext)
            await MainActor.run {
                isRunningMonthly = false
                refreshToken = UUID()
                statusMessage = "Saved to iCloud Drive: \(url.lastPathComponent)"
            }
        } catch {
            await MainActor.run {
                isRunningMonthly = false
                exportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

private struct SharePayload: Identifiable {
    var id: String { url.path }
    let url: URL
}

private struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    DataBackupSettingsView()
        .environmentObject(CloudDataManager.shared)
        .modelContainer(for: [InventoryItem.self, Property.self], inMemory: true)
}
