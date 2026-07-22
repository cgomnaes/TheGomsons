//
//  FamilyTreeGeocoding.swift
//  TheGomsons
//

import CoreLocation
import Foundation
import MapKit
import SwiftData

enum FamilyTreeGeocoding {
    /// Forward-geocode a city string; does not require user location permission.
    static func coordinate(forCity city: String) async -> CLLocationCoordinate2D? {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let request = MKGeocodingRequest(addressString: trimmed) {
            do {
                let mapItems = try await request.mapItems
                if let coordinate = mapItems.first?.location.coordinate {
                    return coordinate
                }
            } catch {
                // Fall through to local search.
            }
        }

        // Fallback when geocoding request is unavailable or returns nothing.
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = trimmed
        searchRequest.resultTypes = [.address, .pointOfInterest]
        do {
            let response = try await MKLocalSearch(request: searchRequest).start()
            return response.mapItems.first?.location.coordinate
        } catch {
            return nil
        }
    }

    /// Updates stored coordinates from `person.city`. Clears coords when city is empty.
    @MainActor
    static func refreshCoordinates(for person: FamilyPerson, modelContext: ModelContext) async {
        let trimmed = person.city.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            person.cityLatitude = nil
            person.cityLongitude = nil
            try? modelContext.save()
            return
        }
        guard let coord = await coordinate(forCity: trimmed) else {
            person.cityLatitude = nil
            person.cityLongitude = nil
            try? modelContext.save()
            return
        }
        person.cityLatitude = coord.latitude
        person.cityLongitude = coord.longitude
        try? modelContext.save()
    }

    /// Geocode everyone who has a city but no coordinates yet (e.g. after import).
    @MainActor
    static func refreshMissingCoordinates(for people: [FamilyPerson], modelContext: ModelContext) async {
        for p in people {
            let city = p.city.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !city.isEmpty, p.cityLatitude == nil || p.cityLongitude == nil else { continue }
            await refreshCoordinates(for: p, modelContext: modelContext)
        }
    }
}
