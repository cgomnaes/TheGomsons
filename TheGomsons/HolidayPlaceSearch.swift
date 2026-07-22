//
//  HolidayPlaceSearch.swift
//  TheGomsons
//

import CoreLocation
import MapKit
import SwiftUI

/// One row from `MKLocalSearch` (cities, regions, POIs) for picking a trip stop.
struct HolidayPlaceCandidate: Identifiable {
    let id = UUID()
    /// Primary line in the list.
    let title: String
    /// Secondary line (area, country).
    let subtitle: String
    /// Stored on the stop (`HolidayDestination.locationName`).
    let resolvedName: String
    let coordinate: CLLocationCoordinate2D
}

/// One trip cover option: **Wikipedia / Commons** photo (preferred) or **satellite** map fallback.
struct HolidayCoverChoice: Identifiable {
    let id: UUID
    let label: String
    let kind: Kind

    enum Kind {
        case wikipedia(pageTitle: String, thumbnailURL: URL)
        case satellite(center: CLLocationCoordinate2D, spanLatitudeDelta: Double, spanLongitudeDelta: Double)
    }
}

enum HolidayPlaceSearch {
    /// Search Apple’s map index for places matching `query` (e.g. city name). Requires network.
    static func searchPlaces(query: String, limit: Int = 14) async throws -> [HolidayPlaceCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HolidayGeocodingError.emptyQuery }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]

        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        let items = Array(response.mapItems.prefix(limit))
        guard !items.isEmpty else { throw HolidayGeocodingError.noResults }

        return items.map { item in
            let title = item.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? trimmed
            let subtitle = subtitleLines(for: item)
            let resolved = resolvedStopName(item: item, fallback: trimmed)
            return HolidayPlaceCandidate(
                title: title,
                subtitle: subtitle,
                resolvedName: resolved,
                coordinate: item.location.coordinate
            )
        }
    }

    /// Prefer **Wikipedia / Wikimedia** photos for the place; if none, fall back to satellite map snapshots (overview + POIs).
    static func coverImageChoices(for place: HolidayPlaceCandidate, limit: Int = 6) async throws -> [HolidayCoverChoice] {
        let wiki = await HolidayWikipediaCoverImages.fetchCoverChoices(for: place, limit: limit)
        if !wiki.isEmpty {
            return wiki.map { w in
                HolidayCoverChoice(
                    id: UUID(),
                    label: w.label,
                    kind: .wikipedia(pageTitle: w.pageTitle, thumbnailURL: w.thumbnailURL)
                )
            }
        }
        return try await satelliteCoverImageChoices(for: place, limit: limit)
    }

    /// Satellite-only options when Wikipedia has no matching illustrated articles.
    private static func satelliteCoverImageChoices(for place: HolidayPlaceCandidate, limit: Int = 6) async throws -> [HolidayCoverChoice] {
        let center = place.coordinate
        let city = place.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { throw HolidayGeocodingError.emptyQuery }

        let searchRegion = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.45, longitudeDelta: 0.45)
        )
        let queries = [
            "\(city) landmark",
            "\(city) historic",
            "\(city) downtown",
            "\(city) cathedral",
            "\(city) viewpoint",
            "\(city) square",
        ]

        var allItems: [MKMapItem] = []
        await withTaskGroup(of: [MKMapItem].self) { group in
            for q in queries {
                group.addTask {
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = q
                    request.resultTypes = .pointOfInterest
                    request.region = searchRegion
                    do {
                        let response = try await MKLocalSearch(request: request).start()
                        return Array(response.mapItems.prefix(8))
                    } catch {
                        return []
                    }
                }
            }
            for await items in group {
                allItems.append(contentsOf: items)
            }
        }

        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var seenCoords: [CLLocationCoordinate2D] = []
        var candidates: [(name: String, coord: CLLocationCoordinate2D)] = []

        for item in allItems {
            let coord = item.location.coordinate
            guard let rawName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty else { continue }
            guard centerLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) < 75_000 else { continue }

            var duplicate = false
            for s in seenCoords {
                if CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    .distance(from: CLLocation(latitude: s.latitude, longitude: s.longitude)) < 420
                {
                    duplicate = true
                    break
                }
            }
            if duplicate { continue }
            seenCoords.append(coord)
            candidates.append((rawName, coord))
        }

        candidates.sort {
            centerLoc.distance(from: CLLocation(latitude: $0.coord.latitude, longitude: $0.coord.longitude)) <
                centerLoc.distance(from: CLLocation(latitude: $1.coord.latitude, longitude: $1.coord.longitude))
        }

        var choices: [HolidayCoverChoice] = [
            HolidayCoverChoice(
                id: UUID(),
                label: String(localized: "cover.satellite_overview"),
                kind: .satellite(center: center, spanLatitudeDelta: 0.11, spanLongitudeDelta: 0.11)
            ),
        ]

        for c in candidates.prefix(max(0, limit - 1)) {
            choices.append(
                HolidayCoverChoice(
                    id: UUID(),
                    label: String(format: String(localized: "cover.satellite_named"), locale: .current, c.name),
                    kind: .satellite(center: c.coord, spanLatitudeDelta: 0.038, spanLongitudeDelta: 0.038)
                )
            )
        }

        return Array(choices.prefix(limit))
    }

    private static func subtitleLines(for item: MKMapItem) -> String {
        guard let addr = item.address else { return "" }
        let short = trim(addr.shortAddress)
        if !short.isEmpty { return short }
        return trim(addr.fullAddress)
    }

    private static func resolvedStopName(item: MKMapItem, fallback: String) -> String {
        if let name = item.name?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !name.isEmpty {
            if let addr = item.address {
                let full = trim(addr.fullAddress)
                if !full.isEmpty {
                    let segments = full.split(separator: ",").map { segment in
                        trim(String(segment))
                    }.filter { !$0.isEmpty }
                    if let last = segments.last, segments.count > 1 {
                        return "\(name), \(last)"
                    }
                }
                let short = trim(addr.shortAddress)
                if !short.isEmpty {
                    return "\(name), \(short)"
                }
            }
            return name
        }
        if let addr = item.address {
            let s = trim(addr.shortAddress)
            if !s.isEmpty { return s }
            let f = trim(addr.fullAddress)
            if !f.isEmpty { return f }
        }
        return fallback
    }

    private static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private static func trim(_ s: String?) -> String {
        guard let s else { return "" }
        return trim(s)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Shared UI (new trip, stops, ideas)

/// Map search tied to the adjacent text field: type a city, search, tap a row. `onPick` receives the full candidate (name + coordinates).
struct HolidayMapPlaceSearchBlock: View {
    @Binding var searchQuery: String
    var buttonTitle: String = String(localized: "planning.search_places")
    /// Called when the user selects a search result; typically set your fields from `candidate`.
    let onPick: (HolidayPlaceCandidate) -> Void
    /// e.g. disable while parent sheet is saving.
    var isDisabled: Bool = false

    @State private var results: [HolidayPlaceCandidate] = []
    @State private var isSearching = false
    @State private var alertMessage: String?

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            Button {
                Task { await runSearch() }
            } label: {
                if isSearching {
                    HStack {
                        ProgressView()
                        Text(String(localized: "map.searching"))
                    }
                } else {
                    Label(buttonTitle, systemImage: "globe")
                }
            }
            .disabled(trimmedQuery.isEmpty || isSearching || isDisabled)

            if !results.isEmpty {
                ForEach(results) { candidate in
                    Button {
                        onPick(candidate)
                        results = []
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            if !candidate.subtitle.isEmpty {
                                Text(candidate.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .alert(String(localized: "map.search"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func runSearch() async {
        await MainActor.run {
            isSearching = true
            results = []
        }
        do {
            let found = try await HolidayPlaceSearch.searchPlaces(query: trimmedQuery)
            await MainActor.run { results = found }
        } catch {
            await MainActor.run {
                alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { isSearching = false }
    }
}
