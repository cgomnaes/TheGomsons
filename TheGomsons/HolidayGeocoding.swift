//
//  HolidayGeocoding.swift
//  TheGomsons
//

import CoreLocation
import MapKit

enum HolidayGeocodingError: LocalizedError {
    case emptyQuery
    case noResults

    var errorDescription: String? {
        switch self {
        case .emptyQuery: String(localized: "geocode.empty")
        case .noResults: String(localized: "geocode.no_results")
        }
    }
}

enum HolidayGeocoding {
    /// Resolves a free-text place name to coordinates using MapKit local search.
    static func coordinate(for query: String) async throws -> CLLocationCoordinate2D {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HolidayGeocodingError.emptyQuery }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]

        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        guard let item = response.mapItems.first else {
            throw HolidayGeocodingError.noResults
        }
        // iOS 26+: `placemark` is deprecated; `location` is the supported coordinate source.
        return item.location.coordinate
    }
}
