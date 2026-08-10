//
//  HolidayTripPlanningView.swift
//  TheGomsons
//
//  Upcoming-trip planning: category chips + Gemini/MapKit suggestions.
//

import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct HolidayTripPlanningSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: HolidayTrip

    @State private var selectedCategory: HolidayPlanCategory = .restaurants
    @State private var suggestions: [TripPlanSuggestion] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAPIKeySheet = false
    @State private var usedGemini = false

    private var sortedPlanItems: [HolidayPlanItem] {
        (trip.planItems ?? []).sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt > $1.createdAt
        }
    }

    private var placeHints: [String] {
        var hints: [String] = []
        for dest in (trip.destinations ?? []) {
            let name = dest.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { hints.append(name) }
        }
        let cover = trip.coverPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cover.isEmpty { hints.append(cover) }
        let stay = trip.mainAccommodation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stay.isEmpty { hints.append(stay) }
        let name = trip.tripName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { hints.append(name) }
        return hints
    }

    private var coordinateHints: [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        for dest in trip.destinations ?? [] where dest.latitude != 0 || dest.longitude != 0 {
            coords.append(CLLocationCoordinate2D(latitude: dest.latitude, longitude: dest.longitude))
        }
        if trip.coverLatitude != 0 || trip.coverLongitude != 0 {
            coords.append(CLLocationCoordinate2D(latitude: trip.coverLatitude, longitude: trip.coverLongitude))
        }
        return coords
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "trip.plan.title"))
                        .font(.title2.weight(.bold))
                    Text(String(localized: "trip.plan.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    showAPIKeySheet = true
                } label: {
                    Image(systemName: GeminiAPIKeyStore.hasAPIKey ? "sparkles" : "key.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(String(localized: "trip.plan.gemini_key.a11y"))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HolidayPlanCategory.allCases) { category in
                        Button {
                            selectedCategory = category
                            Task { await loadSuggestions(for: category) }
                        } label: {
                            Label(category.displayTitle, systemImage: category.systemImage)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedCategory == category
                                        ? SimpsonsTheme.orange.opacity(0.9)
                                        : Color(.secondarySystemGroupedBackground),
                                    in: Capsule()
                                )
                                .foregroundStyle(selectedCategory == category ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(String(localized: "trip.plan.loading"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        usedGemini
                            ? String(localized: "trip.plan.suggestions_gemini")
                            : String(localized: "trip.plan.suggestions_maps")
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                    ForEach(suggestions) { suggestion in
                        suggestionRow(suggestion)
                    }
                }
            } else {
                Text(String(localized: "trip.plan.pick_category"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !sortedPlanItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "trip.plan.saved"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(sortedPlanItems, id: \.persistentModelID) { item in
                        savedItemRow(item)
                    }
                }
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showAPIKeySheet) {
            GeminiAPIKeySheet()
        }
        .task {
            await loadSuggestions(for: selectedCategory)
        }
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: TripPlanSuggestion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: suggestion.category.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(SimpsonsTheme.orange)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                if !suggestion.detail.isEmpty {
                    Text(suggestion.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Button {
                addSuggestion(suggestion)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(SimpsonsTheme.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "trip.plan.add"))
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func savedItemRow(_ item: HolidayPlanItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.category.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.category.displayTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if let url = mapsURL(for: item) {
                Link(destination: url) {
                    Image(systemName: "map")
                        .foregroundStyle(SimpsonsTheme.blue)
                }
                .accessibilityLabel(String(localized: "trip.plan.open_maps"))
            }

            Button(role: .destructive) {
                modelContext.delete(item)
                try? modelContext.save()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "common.delete"))
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func mapsURL(for item: HolidayPlanItem) -> URL? {
        let query = item.mapsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://maps.apple.com/?q=\(encoded)")
    }

    private func addSuggestion(_ suggestion: TripPlanSuggestion) {
        let already = (trip.planItems ?? []).contains {
            $0.title.caseInsensitiveCompare(suggestion.title) == .orderedSame
        }
        guard !already else { return }
        let next = ((trip.planItems ?? []).map(\.sortOrder).max() ?? -1) + 1
        let item = HolidayPlanItem(
            title: suggestion.title,
            detail: suggestion.detail,
            category: suggestion.category,
            placeName: suggestion.placeName,
            mapsQuery: suggestion.mapsQuery,
            sortOrder: next,
            sourceRaw: suggestion.source.rawValue,
            trip: trip
        )
        modelContext.insert(item)
        if trip.planItems == nil { trip.planItems = [] }
        trip.planItems?.append(item)
        try? modelContext.save()
    }

    @MainActor
    private func loadSuggestions(for category: HolidayPlanCategory) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let results = try await GeminiTripPlanner.suggest(
                category: category,
                tripName: trip.tripName,
                placeHints: placeHints,
                coordinateHints: coordinateHints
            )
            suggestions = results
            usedGemini = results.contains { $0.source == .gemini }
        } catch {
            suggestions = []
            errorMessage = error.localizedDescription
            usedGemini = false
        }
    }
}

// MARK: - Gemini API key sheet

private struct GeminiAPIKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keyText = GeminiAPIKeyStore.apiKey ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(String(localized: "trip.plan.gemini_key"), text: $keyText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(String(localized: "trip.plan.gemini_key"))
                } footer: {
                    Text(String(localized: "trip.plan.gemini_key_footer"))
                }

                if GeminiAPIKeyStore.hasAPIKey {
                    Section {
                        Button(String(localized: "trip.plan.gemini_key_clear"), role: .destructive) {
                            keyText = ""
                            GeminiAPIKeyStore.apiKey = nil
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "trip.plan.gemini_key_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) {
                        GeminiAPIKeyStore.apiKey = keyText
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
