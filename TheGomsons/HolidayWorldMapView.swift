//
//  HolidayWorldMapView.swift
//  TheGomsons
//

import MapKit
import SwiftData
import SwiftUI

/// Shared base map look for holiday world + trip route maps.
enum HolidayMapBaseStyle: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: String(localized: "map.style.standard")
        case .satellite: String(localized: "map.style.satellite")
        case .hybrid: String(localized: "map.style.hybrid")
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard:
            .standard(
                elevation: .flat,
                emphasis: .muted,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            )
        case .satellite:
            .imagery(elevation: .flat)
        case .hybrid:
            .hybrid(
                elevation: .flat,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            )
        }
    }
}

/// What to show on the holiday world map (past trips, upcoming, ideas, or everything).
enum HolidayWorldMapFilter: String, CaseIterable, Identifiable {
    case all
    case pastTrips
    case upcoming
    case ideas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "map.filter.all")
        case .pastTrips: String(localized: "map.filter.past")
        case .upcoming: String(localized: "map.filter.upcoming")
        case .ideas: String(localized: "map.filter.ideas")
        }
    }
}

/// One pin per saved trip (cover city), plus proposed ideas (not `Location` / home map). Stops are for each trip’s route map only.
struct HolidayWorldMapView: View {
    @Query(sort: \HolidayTrip.startDate, order: .reverse) private var allTrips: [HolidayTrip]
    @Query(sort: \VacationIdea.proposedDestination, order: .forward) private var allIdeas: [VacationIdea]

    @AppStorage("holidayMapBaseStyle") private var mapStyleRaw: String = HolidayMapBaseStyle.standard.rawValue
    @State private var position: MapCameraPosition = .automatic
    @State private var mapFilter: HolidayWorldMapFilter = .all
    /// Geocoded coordinates when a trip has no stored cover coordinates (cover place name, else main stay / trip name).
    @State private var geocodedTripAnchors: [PersistentIdentifier: CLLocationCoordinate2D] = [:]
    /// Tap a trip pin to open that trip’s detail.
    @State private var selectedTripID: PersistentIdentifier?

    private var mapBaseStyle: HolidayMapBaseStyle {
        HolidayMapBaseStyle(rawValue: mapStyleRaw) ?? .standard
    }
    /// Trips that need async geocoding: no saved cover coordinates but we have text to look up.
    private var tripsEligibleForGeocodedPin: [(trip: HolidayTrip, query: String)] {
        allTrips.compactMap { trip in
            guard !trip.hasCoverMapCoordinate else { return nil }
            guard let query = Self.tripWorldMapGeocodeQuery(for: trip) else { return nil }
            return (trip, query)
        }
    }

    /// Changes when eligible trips or their lookup strings change — triggers a fresh geocode pass.
    private var anchorResolutionSignature: String {
        tripsEligibleForGeocodedPin
            .map { "\($0.trip.persistentModelID.hashValue)-\($0.query)" }
            .sorted()
            .joined(separator: "|")
    }

    private var pins: [WorldMapPin] {
        var result: [WorldMapPin] = []
        if mapFilter == .all || mapFilter == .pastTrips || mapFilter == .upcoming {
            for trip in allTrips {
                let endedPast = trip.isPastTrip
                switch mapFilter {
                case .all:
                    break
                case .pastTrips:
                    if !endedPast { continue }
                case .upcoming:
                    if endedPast { continue }
                case .ideas:
                    continue
                }
                let kind: WorldMapPin.Kind = endedPast ? .pastTrip : .plannedTrip
                if trip.hasCoverMapCoordinate {
                    result.append(
                        WorldMapPin(
                            id: "trip-cover-\(trip.persistentModelID)",
                            coordinate: trip.coverMapCoordinate,
                            title: Self.tripWorldMapPinTitle(trip),
                            kind: kind,
                            tripID: trip.persistentModelID
                        )
                    )
                } else if let coord = geocodedTripAnchors[trip.persistentModelID] {
                    result.append(
                        WorldMapPin(
                            id: "trip-geocoded-\(trip.persistentModelID)",
                            coordinate: coord,
                            title: Self.tripWorldMapPinTitle(trip),
                            kind: kind,
                            tripID: trip.persistentModelID
                        )
                    )
                }
            }
        }
        if mapFilter == .all || mapFilter == .ideas {
            for idea in allIdeas where idea.hasPlottableCoordinate {
                result.append(
                    WorldMapPin(
                        id: "idea-\(idea.persistentModelID)",
                        coordinate: idea.coordinate,
                        title: idea.mapAnnotationTitle,
                        kind: .proposedIdea,
                        tripID: nil
                    )
                )
            }
        }
        return result
    }

    private var emptyDescription: Text {
        switch mapFilter {
        case .all:
            Text(String(localized: "map.empty.all_detail"))
        case .pastTrips:
            Text(String(localized: "map.empty.past_detail"))
        case .upcoming:
            Text(String(localized: "map.empty.upcoming_detail"))
        case .ideas:
            Text(String(localized: "map.empty.ideas_detail"))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker(String(localized: "map.content"), selection: $mapFilter) {
                    ForEach(HolidayWorldMapFilter.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker(String(localized: "map.style"), selection: $mapStyleRaw) {
                    ForEach(HolidayMapBaseStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Group {
                if pins.isEmpty {
                    ContentUnavailableView(
                        mapFilter == .all
                            ? String(localized: "map.empty.all_title")
                            : String(localized: "map.empty.filter_title"),
                        systemImage: "map.circle",
                        description: emptyDescription
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Map(position: $position) {
                        ForEach(pins) { pin in
                            Annotation(pin.title, coordinate: pin.coordinate) {
                                if let tripID = pin.tripID {
                                    Button {
                                        selectedTripID = tripID
                                    } label: {
                                        HolidayMapPinView(kind: pin.kind, seed: pin.id.hashValue)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint(String(localized: "map.a11y.open_trip"))
                                } else {
                                    HolidayMapPinView(kind: pin.kind, seed: pin.id.hashValue)
                                }
                            }
                        }
                    }
                    .mapStyle(mapBaseStyle.mapStyle)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationDestination(item: $selectedTripID) { tripID in
            if let trip = allTrips.first(where: { $0.persistentModelID == tripID }) {
                HolidayTripDetailView(trip: trip)
            } else {
                ContentUnavailableView(
                    String(localized: "map.trip_missing_title"),
                    systemImage: "suitcase",
                    description: Text(String(localized: "map.trip_missing_detail"))
                )
            }
        }
        .onAppear {
            fitCameraIfPossible()
        }
        .onChange(of: pins.count) { _, _ in
            fitCameraIfPossible()
        }
        .onChange(of: mapFilter) { _, _ in
            fitCameraIfPossible()
        }
        .task(id: anchorResolutionSignature) {
            await resolveTripAnchorCoordinates()
        }
    }

    /// Free-text to geocode when a trip has no saved cover coordinates: cover search label (if any), else main stay, else trip name.
    private static func tripWorldMapGeocodeQuery(for trip: HolidayTrip) -> String? {
        let cover = trip.coverPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cover.isEmpty { return cover }
        return anchorGeocodeQuery(for: trip)
    }

    private static func anchorGeocodeQuery(for trip: HolidayTrip) -> String? {
        let acc = trip.mainAccommodation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !acc.isEmpty { return acc }
        let name = trip.tripName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return nil
    }

    private static func tripWorldMapPinTitle(_ trip: HolidayTrip) -> String {
        let cover = trip.coverPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trip.tripName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cover.isEmpty {
            if name.isEmpty || name == cover { return cover }
            return "\(cover) · \(name)"
        }
        let acc = trip.mainAccommodation.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = acc.isEmpty ? (name.isEmpty ? String(localized: "map.pin.trip_fallback") : name) : acc
        if name.isEmpty || name == place {
            return place
        }
        return "\(place) · \(name)"
    }

    private func resolveTripAnchorCoordinates() async {
        let idAndQueries: [(PersistentIdentifier, String)] = await MainActor.run {
            tripsEligibleForGeocodedPin.map { ($0.trip.persistentModelID, $0.query) }
        }
        guard !idAndQueries.isEmpty else {
            await MainActor.run { geocodedTripAnchors = [:] }
            return
        }
        var updated: [PersistentIdentifier: CLLocationCoordinate2D] = [:]
        for (id, query) in idAndQueries {
            if let c = try? await HolidayGeocoding.coordinate(for: query), !(c.latitude == 0 && c.longitude == 0) {
                updated[id] = c
            }
        }
        await MainActor.run { geocodedTripAnchors = updated }
    }

    private func fitCameraIfPossible() {
        guard !pins.isEmpty else { return }
        let coords = pins.map(\.coordinate)
        let minLat = coords.map(\.latitude).min() ?? 0
        let maxLat = coords.map(\.latitude).max() ?? 0
        let minLon = coords.map(\.longitude).min() ?? 0
        let maxLon = coords.map(\.longitude).max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latSpan = max((maxLat - minLat) * 1.5, 1.2)
        let lonSpan = max((maxLon - minLon) * 1.5, 1.2)
        position = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)))
    }
}

// MARK: - Single-trip map (detail screen)

/// Geographic view of one trip’s stops: pins in visit order and a path when there are multiple pins.
struct HolidayTripStopsMapView: View {
    let trip: HolidayTrip

    @AppStorage("holidayMapBaseStyle") private var mapStyleRaw: String = HolidayMapBaseStyle.standard.rawValue
    @State private var position: MapCameraPosition = .automatic

    private var mapBaseStyle: HolidayMapBaseStyle {
        HolidayMapBaseStyle(rawValue: mapStyleRaw) ?? .standard
    }

    private var sortedPlottable: [HolidayDestination] {
        (trip.destinations ?? [])
            .filter(\.hasPlottableCoordinate)
            .sorted { $0.arrivalDate < $1.arrivalDate }
    }

    private var pinKind: WorldMapPin.Kind {
        trip.isPastTrip ? .pastTrip : .plannedTrip
    }

    var body: some View {
        VStack(spacing: 8) {
            if !sortedPlottable.isEmpty {
                Picker(String(localized: "map.style"), selection: $mapStyleRaw) {
                    ForEach(HolidayMapBaseStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Group {
                if sortedPlottable.isEmpty {
                    ContentUnavailableView(
                        String(localized: "map.trip.empty_title"),
                        systemImage: "mappin.slash",
                        description: Text(String(localized: "map.trip.empty_detail"))
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                } else {
                    Map(position: $position) {
                        ForEach(sortedPlottable) { dest in
                            Annotation(dest.annotationTitle, coordinate: dest.coordinate) {
                                HolidayMapPinView(kind: pinKind, seed: dest.persistentModelID.hashValue)
                            }
                        }
                        if sortedPlottable.count >= 2 {
                            MapPolyline(coordinates: sortedPlottable.map(\.coordinate))
                                .stroke(SimpsonsTheme.blue.opacity(0.9), lineWidth: 3)
                        }
                    }
                    .mapStyle(mapBaseStyle.mapStyle)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .onAppear {
            fitTripCamera()
        }
        .onChange(of: sortedPlottable.count) { _, _ in
            fitTripCamera()
        }
    }

    private func fitTripCamera() {
        let coords = sortedPlottable.map(\.coordinate)
        guard !coords.isEmpty else { return }
        if coords.count == 1, let c = coords.first {
            position = .region(
                MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8))
            )
            return
        }
        let minLat = coords.map(\.latitude).min() ?? 0
        let maxLat = coords.map(\.latitude).max() ?? 0
        let minLon = coords.map(\.longitude).min() ?? 0
        let maxLon = coords.map(\.longitude).max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latSpan = max((maxLat - minLat) * 1.45, 0.35)
        let lonSpan = max((maxLon - minLon) * 1.45, 0.35)
        position = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)))
    }
}

// MARK: - Pin model

private struct WorldMapPin: Identifiable {
    enum Kind {
        /// Completed trip stops (suitcase-style).
        case pastTrip
        /// Trip still ongoing or in the future.
        case plannedTrip
        /// From Ideas / proposals (not a saved trip yet).
        case proposedIdea
    }

    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let kind: Kind
    /// Set for past/upcoming trip pins so a tap can open the trip.
    let tripID: PersistentIdentifier?
}

// MARK: - Pin visuals

private struct HolidayMapPinView: View {
    let kind: WorldMapPin.Kind
    let seed: Int

    private var symbolName: String {
        switch kind {
        case .pastTrip:
            "suitcase.fill"
        case .plannedTrip:
            "calendar.circle.fill"
        case .proposedIdea:
            "lightbulb.max.fill"
        }
    }

    private var accentHue: Double {
        let base: Double
        switch kind {
        case .pastTrip: base = 0.58
        case .plannedTrip: base = 0.52
        case .proposedIdea: base = 0.12
        }
        let jitter = Double(abs(seed % 40)) / 400.0
        return (base + jitter).truncatingRemainder(dividingBy: 1)
    }

    private var accessibilityLabel: String {
        switch kind {
        case .pastTrip: String(localized: "map.a11y.past")
        case .plannedTrip: String(localized: "map.a11y.planned")
        case .proposedIdea: String(localized: "map.a11y.idea")
        }
    }

    var body: some View {
        ZStack {
            if kind == .proposedIdea {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(hue: accentHue, saturation: 0.65, brightness: 0.95),
                                Color(hue: (accentHue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.88),
                            ],
                            center: .center
                        )
                    )
                    .frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
            } else {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(hue: accentHue, saturation: 0.55, brightness: 0.95),
                                Color(hue: (accentHue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.5, brightness: 0.88),
                                Color(hue: (accentHue + 0.16).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.9),
                            ],
                            center: .center
                        )
                    )
                    .frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
            }

            Image(systemName: symbolName)
                .font(.system(size: kind == .proposedIdea ? 22 : 20, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - HolidayDestination + map

extension HolidayDestination {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Excludes unset (0,0) stops so the map stays meaningful.
    var hasPlottableCoordinate: Bool {
        !(latitude == 0 && longitude == 0)
    }

    var annotationTitle: String {
        let place = locationName.isEmpty ? String(localized: "map.pin.stop_fallback") : locationName
        if let tripName = trip?.tripName, !tripName.isEmpty {
            return "\(place) · \(tripName)"
        }
        return place
    }
}

extension VacationIdea {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasPlottableCoordinate: Bool {
        !(latitude == 0 && longitude == 0)
    }

    var mapAnnotationTitle: String {
        let place = proposedDestination.isEmpty ? String(localized: "map.pin.idea_fallback") : proposedDestination
        return "\(place) · idea"
    }
}

#Preview {
    HolidayWorldMapView()
        .modelContainer(
            for: [HolidayTrip.self, HolidayDestination.self, VacationIdea.self],
            inMemory: true
        )
}

// MARK: - HolidayTrip + world map

extension HolidayTrip {
    /// Non-zero coordinates from the cover-photo city search.
    fileprivate var hasCoverMapCoordinate: Bool {
        !(coverLatitude == 0 && coverLongitude == 0)
    }

    fileprivate var coverMapCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coverLatitude, longitude: coverLongitude)
    }
}
