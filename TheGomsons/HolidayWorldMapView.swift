//
//  HolidayWorldMapView.swift
//  TheGomsons
//

import MapKit
import SwiftData
import SwiftUI

/// Trip stops and proposed ideas (not `Location` / home map). Simpler map look + distinct pin styles.
struct HolidayWorldMapView: View {
    @Query(sort: \HolidayDestination.arrivalDate, order: .reverse) private var allDestinations: [HolidayDestination]
    @Query(sort: \VacationIdea.upvotes, order: .reverse) private var allIdeas: [VacationIdea]

    @State private var position: MapCameraPosition = .automatic

    private var pins: [WorldMapPin] {
        var result: [WorldMapPin] = []
        for dest in allDestinations where dest.hasPlottableCoordinate {
            let kind: WorldMapPin.Kind
            if let trip = dest.trip, !isTripEndedBeforeToday(trip) {
                kind = .plannedTrip
            } else {
                kind = .pastTrip
            }
            result.append(
                WorldMapPin(
                    id: "dest-\(dest.persistentModelID)",
                    coordinate: dest.coordinate,
                    title: dest.annotationTitle,
                    kind: kind
                )
            )
        }
        for idea in allIdeas where idea.hasPlottableCoordinate {
            result.append(
                WorldMapPin(
                    id: "idea-\(idea.persistentModelID)",
                    coordinate: idea.coordinate,
                    title: idea.mapAnnotationTitle,
                    kind: .proposedIdea
                )
            )
        }
        return result
    }

    var body: some View {
        Group {
            if pins.isEmpty {
                ContentUnavailableView(
                    "No holiday pins yet",
                    systemImage: "map.circle",
                    description: Text(
                        "Add stops to a trip and use “Look up place” to set coordinates, or propose a destination in Plan Next—the map shows past trips, upcoming trips, and ideas with different pins."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Map(position: $position) {
                    ForEach(pins) { pin in
                        Annotation(pin.title, coordinate: pin.coordinate) {
                            HolidayMapPinView(kind: pin.kind, seed: pin.id.hashValue)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            }
        }
        .onAppear {
            fitCameraIfPossible()
        }
        .onChange(of: pins.count) { _, _ in
            fitCameraIfPossible()
        }
    }

    private func isTripEndedBeforeToday(_ trip: HolidayTrip) -> Bool {
        let endDay = Calendar.current.startOfDay(for: trip.endDate)
        let today = Calendar.current.startOfDay(for: Date())
        return endDay < today
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

// MARK: - Pin model

private struct WorldMapPin: Identifiable {
    enum Kind {
        /// Completed trip stops (suitcase-style).
        case pastTrip
        /// Trip still ongoing or in the future.
        case plannedTrip
        /// From Plan Next vacation ideas.
        case proposedIdea
    }

    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let kind: Kind
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
        case .pastTrip: "Past trip stop"
        case .plannedTrip: "Upcoming or current trip stop"
        case .proposedIdea: "Proposed vacation idea"
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
        let place = locationName.isEmpty ? "Stop" : locationName
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
        let place = proposedDestination.isEmpty ? "Idea" : proposedDestination
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
