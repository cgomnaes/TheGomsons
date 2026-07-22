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
    @State private var exportError: String?
    @State private var sharePayload: SharePayload?
    @State private var refreshToken = UUID()

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
                    Button(String(localized: "sync.reload_local")) {
                        cloud.refreshFamilyDataFromStore()
                        refreshToken = UUID()
                    }
                    .font(.subheadline)
                } header: {
                    Text(String(localized: "sync.family"))
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
                    .disabled(isExporting)
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
            }
            .id(refreshToken)
            .navigationTitle(String(localized: "data_backup.title"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                cloud.refreshCloudKitAccountStatus()
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

    private func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func exportBackup() async {
        await MainActor.run {
            isExporting = true
            exportError = nil
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
