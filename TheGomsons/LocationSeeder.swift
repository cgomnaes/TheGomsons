//
//  LocationSeeder.swift
//  TheGomsons
//

import Foundation
import SwiftData

enum LocationSeeder {
    private struct SeedCity {
        let name: String
        let latitude: Double
        let longitude: Double
        let kind: LocationKind
    }

    private static let defaults: [SeedCity] = [
        SeedCity(name: "New Jersey", latitude: 40.0583, longitude: -74.4057, kind: LocationKind.visited),
        SeedCity(name: "New York City", latitude: 40.7128, longitude: -74.0060, kind: LocationKind.visited),
        SeedCity(name: "Charlottesville", latitude: 38.0293, longitude: -78.4767, kind: LocationKind.visited),
        SeedCity(name: "London", latitude: 51.5074, longitude: -0.1278, kind: LocationKind.visited),
        SeedCity(name: "Oslo", latitude: 59.9139, longitude: 10.7522, kind: LocationKind.visited),
    ]

    /// Inserts the default family map pins once, when there are no `Location` rows yet.
    static func populateDefaultLocationsIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<Location>()
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        for city in defaults {
            let location = Location(
                cityName: city.name,
                latitude: city.latitude,
                longitude: city.longitude,
                type: city.kind
            )
            context.insert(location)
        }

        try? context.save()
    }
}
