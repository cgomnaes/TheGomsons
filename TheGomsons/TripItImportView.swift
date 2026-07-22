//
//  TripItImportView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TripItImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HolidayTrip.startDate, order: .reverse) private var existingTrips: [HolidayTrip]

    @State private var feedURL = ""
    @State private var isLoading = false
    @State private var parsedTrips: [TripItImport.ParsedTrip] = []
    @State private var selectedIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(String(localized: "tripit.intro"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(String(localized: "tripit.import_file")) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label(String(localized: "tripit.choose_ics"), systemImage: "doc.badge.arrow.up")
                    }
                    .disabled(isLoading)
                }

                Section {
                    TextField(String(localized: "tripit.feed_placeholder"), text: $feedURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        Task { await fetchFeed() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(String(localized: "tripit.fetch_feed"), systemImage: "link.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text(String(localized: "tripit.feed_header"))
                } footer: {
                    Text(String(localized: "tripit.feed_footer"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }

                if !parsedTrips.isEmpty {
                    Section {
                        Button(selectedIDs.count == parsedTrips.count ? String(localized: "tripit.deselect_all") : String(localized: "tripit.select_all")) {
                            if selectedIDs.count == parsedTrips.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(parsedTrips.map(\.id))
                            }
                        }
                        ForEach(parsedTrips) { trip in
                            Toggle(isOn: binding(for: trip.id)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(trip.tripName)
                                        .font(.headline)
                                    Text(dateRangeText(trip))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !trip.stops.isEmpty {
                                        Text({
                                        let c = trip.stops.count
                                        let key = c == 1 ? "tripit.segment_count" : "tripit.segment_count_plural"
                                        return String(format: String(localized: String.LocalizationValue(key)), locale: .current, c)
                                    }())
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    if !trip.airlineName.isEmpty || !trip.mainAccommodation.isEmpty {
                                        Text([trip.airlineName, trip.mainAccommodation].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(String(format: String(localized: "tripit.trips_found"), locale: .current, parsedTrips.count))
                    }

                    Section {
                        Button {
                            commitImport()
                        } label: {
                            Label({
                                let c = selectedIDs.count
                                let key = c == 1 ? "tripit.import_n" : "tripit.import_n_plural"
                                return String(format: String(localized: String.LocalizationValue(key)), locale: .current, c)
                            }(), systemImage: "square.and.arrow.down.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(selectedIDs.isEmpty || isLoading)
                    }
                }
            }
            .navigationTitle(String(localized: "tripit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close")) { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: Self.importTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
        }
    }

    private static var importTypes: [UTType] {
        var types: [UTType] = [.text, .plainText, .data, .item]
        if let ics = UTType(filenameExtension: "ics") {
            types.insert(ics, at: 0)
        }
        if let cal = UTType("public.calendar-event") {
            types.insert(cal, at: 0)
        }
        return types
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { on in
                if on { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
            }
        )
    }

    private func dateRangeText(_ trip: TripItImport.ParsedTrip) -> String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        return "\(trip.startDate.formatted(style)) – \(trip.endDate.formatted(style))"
    }

    private func applyParsed(_ trips: [TripItImport.ParsedTrip], source: String) {
        parsedTrips = trips
        selectedIDs = Set(trips.map(\.id))
        errorMessage = nil
        statusMessage = {
            let key = trips.count == 1 ? "tripit.loaded" : "tripit.loaded_plural"
            return String(format: String(localized: String.LocalizationValue(key)), locale: .current, trips.count, source)
        }()
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let trips = try TripItImport.parseICS(data: data)
                applyParsed(trips, source: url.lastPathComponent)
            } catch {
                errorMessage = error.localizedDescription
                parsedTrips = []
                selectedIDs = []
            }
        }
    }

    private func fetchFeed() async {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoading = false }
        do {
            let trips = try await TripItImport.fetchICS(from: feedURL)
            applyParsed(trips, source: String(localized: "tripit.source_feed"))
        } catch {
            errorMessage = error.localizedDescription
            parsedTrips = []
            selectedIDs = []
        }
    }

    private func commitImport() {
        let result = TripItImport.importTrips(
            parsedTrips,
            selectedIDs: selectedIDs,
            into: modelContext,
            existing: Array(existingTrips)
        )
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if result.imported > 0 {
            dismiss()
        } else {
            statusMessage = [
                result.imported > 0 ? String(format: String(localized: "tripit.imported"), locale: .current, result.imported) : nil,
                result.skippedDuplicates > 0 ? String(format: String(localized: "tripit.skipped_duplicates"), locale: .current, result.skippedDuplicates) : nil,
            ].compactMap { $0 }.joined(separator: " ")
            if let first = result.warnings.first {
                statusMessage = (statusMessage ?? "") + " " + first
            }
        }
    }
}

#Preview {
    TripItImportView()
        .modelContainer(for: [HolidayTrip.self, HolidayDestination.self, HolidayTripParticipant.self], inMemory: true)
}
