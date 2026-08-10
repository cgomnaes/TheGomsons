//
//  PropertiesImportView.swift
//  TheGomsons
//
//  Share Google Sheets–ready CSV template and import filled exports into SwiftData.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PropertiesImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Property.name) private var properties: [Property]

    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var resultMessage: String?
    @State private var showResult = false

    var body: some View {
        Form {
            Section {
                Text(String(localized: "properties.import_intro"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(PropertiesCSVImport.googleSheetsInstructions)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "properties.import_how"))
            }

            Section {
                ShareLink(
                    item: templateFileURL(),
                    subject: Text(String(localized: "properties.import_template")),
                    message: Text(String(localized: "properties.import_template_message"))
                ) {
                    Label(String(localized: "properties.import_share_template"), systemImage: "square.and.arrow.up")
                }

                Button {
                    showFileImporter = true
                } label: {
                    if isImporting {
                        HStack {
                            ProgressView()
                            Text(String(localized: "properties.importing"))
                        }
                    } else {
                        Label(String(localized: "properties.import_csv"), systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isImporting)
            } header: {
                Text(String(localized: "properties.import_actions"))
            } footer: {
                Text(String(localized: "properties.import_footer"))
                    .font(.caption)
            }

            Section {
                Text(String(localized: "properties.import_kinds_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "properties.import_trades_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "properties.import_services_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "properties.import_allowed_values"))
            }
        }
        .navigationTitle(String(localized: "properties.import_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "common.done")) { dismiss() }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.importTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importCSV(from: url) }
            case .failure(let err):
                resultMessage = err.localizedDescription
                showResult = true
            }
        }
        .alert(
            String(localized: "properties.import_result_title"),
            isPresented: $showResult,
            actions: {
                Button(String(localized: "common.ok"), role: .cancel) { showResult = false }
            },
            message: {
                Text(resultMessage ?? "")
            }
        )
    }

    private static var importTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText, .text, .data]
        if let csv = UTType(filenameExtension: "csv") {
            types.insert(csv, at: 0)
        }
        return types
    }

    private func templateFileURL() -> URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PropertiesImportTemplate.csv")
        try? PropertiesCSVImport.templateFileContents.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    @MainActor
    private func importCSV(from url: URL) async {
        isImporting = true
        defer { isImporting = false }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let result = try PropertiesCSVImport.importCSV(
                data: data,
                modelContext: modelContext,
                existingProperties: Array(properties)
            )
            var lines: [String] = [
                String(
                    format: String(localized: "properties.import_summary_fmt"),
                    locale: .current,
                    result.added,
                    result.updated,
                    result.contactsAdded,
                    result.emergenciesAdded,
                    result.contractorsAdded,
                    result.servicesAdded
                )
            ]
            if !result.warnings.isEmpty {
                let preview = result.warnings.prefix(8).joined(separator: "\n")
                lines.append("")
                lines.append(String(localized: "properties.import_warnings_header"))
                lines.append(preview)
                if result.warnings.count > 8 {
                    lines.append(
                        String(
                            format: String(localized: "properties.import_warnings_more_fmt"),
                            locale: .current,
                            result.warnings.count - 8
                        )
                    )
                }
            }
            resultMessage = lines.joined(separator: "\n")
            showResult = true
        } catch {
            resultMessage = error.localizedDescription
            showResult = true
        }
    }
}
