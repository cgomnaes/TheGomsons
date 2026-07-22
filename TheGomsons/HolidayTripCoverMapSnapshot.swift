//
//  HolidayTripCoverMapSnapshot.swift
//  TheGomsons
//

import CoreLocation
import MapKit
import UIKit

/// Trip cover images from **satellite** map snapshots (aerial), framed by coordinate + span—no street-level Look Around, so results read like postcard overviews or landmarks rather than random streets.
enum HolidayTripCoverPlaceImage {
    static func satelliteJPEG(
        center: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        pixelWidth: CGFloat = 1600,
        pixelHeight: CGFloat = 900
    ) async throws -> Data {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: pixelWidth, height: pixelHeight)
        options.mapType = .satellite

        let snapshotter = MKMapSnapshotter(options: options)
        return try await withCheckedThrowingContinuation { continuation in
            snapshotter.start { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image = snapshot?.image,
                      let data = image.jpegData(compressionQuality: 0.86)
                else {
                    continuation.resume(throwing: HolidayGeocodingError.noResults)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}
