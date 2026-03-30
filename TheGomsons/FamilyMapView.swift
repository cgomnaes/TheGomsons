//
//  FamilyMapView.swift
//  TheGomsons
//

import MapKit
import SwiftData
import SwiftUI

/// Map without navigation chrome; used inside `HolidaysView` (World Map tab) and by `FamilyMapView`.
struct FamilyMapContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var locations: [Location]

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(locations) { location in
                Annotation(location.cityName, coordinate: location.coordinate) {
                    Image(systemName: location.type == LocationKind.lived ? "house.fill" : "mappin.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(location.type == LocationKind.lived ? .teal : .red)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onAppear {
            LocationSeeder.populateDefaultLocationsIfNeeded(in: modelContext)
            fitCameraIfPossible()
        }
        .onChange(of: locations.count) { _, _ in
            fitCameraIfPossible()
        }
    }

    private func fitCameraIfPossible() {
        guard !locations.isEmpty else { return }
        let coords = locations.map(\.coordinate)
        let minLat = coords.map(\.latitude).min() ?? 0
        let maxLat = coords.map(\.latitude).max() ?? 0
        let minLon = coords.map(\.longitude).min() ?? 0
        let maxLon = coords.map(\.longitude).max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 2),
            longitudeDelta: max((maxLon - minLon) * 1.4, 2)
        )
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

struct FamilyMapView: View {
    var body: some View {
        NavigationStack {
            FamilyMapContentView()
                .navigationTitle("Map")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension Location {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

#Preview {
    FamilyMapView()
        .modelContainer(for: Location.self, inMemory: true)
}
