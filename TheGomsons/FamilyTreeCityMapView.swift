//
//  FamilyTreeCityMapView.swift
//  TheGomsons
//

import MapKit
import SwiftData
import SwiftUI
import UIKit

/// Map of family members by the city on each profile (geocoded from the city text).
struct FamilyTreeCityMapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyPerson.sortOrder) private var allPeople: [FamilyPerson]

    @State private var position: MapCameraPosition = .automatic

    private var mappablePeople: [FamilyPerson] {
        allPeople.filter {
            !$0.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.cityLatitude != nil
                && $0.cityLongitude != nil
        }
    }

    private var coordinateFingerprint: String {
        mappablePeople.map { p in
            "\(String(describing: p.persistentModelID))-\(p.cityLatitude ?? 0)-\(p.cityLongitude ?? 0)"
        }.joined(separator: "|")
    }

    var body: some View {
        Group {
            if mappablePeople.isEmpty {
                ContentUnavailableView(
                    String(localized: "family_tree.map_empty_title"),
                    systemImage: "map",
                    description: Text(String(localized: "family_tree.map_empty_detail"))
                )
                .frame(maxHeight: .infinity)
            } else {
                Map(position: $position) {
                    ForEach(mappablePeople, id: \.persistentModelID) { person in
                        if let lat = person.cityLatitude, let lon = person.cityLongitude {
                            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                            Annotation(person.displayName.isEmpty ? person.city : person.displayName, coordinate: coord) {
                                VStack(spacing: 4) {
                                    FamilyTreeMapAvatar(photoData: person.photoData, name: person.displayName)
                                        .frame(width: 40, height: 40)
                                    Text(person.displayName.isEmpty ? String(localized: "common.untitled") : person.displayName)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(maxWidth: 120)
                                    Text(person.city)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
            }
        }
        .task {
            await FamilyTreeGeocoding.refreshMissingCoordinates(for: allPeople, modelContext: modelContext)
            fitCamera()
        }
        .onChange(of: coordinateFingerprint) { _, _ in
            fitCamera()
        }
    }

    private func fitCamera() {
        let coords = mappablePeople.compactMap { p -> CLLocationCoordinate2D? in
            guard let la = p.cityLatitude, let lo = p.cityLongitude else { return nil }
            return CLLocationCoordinate2D(latitude: la, longitude: lo)
        }
        guard !coords.isEmpty else { return }
        let minLat = coords.map(\.latitude).min() ?? 0
        let maxLat = coords.map(\.latitude).max() ?? 0
        let minLon = coords.map(\.longitude).min() ?? 0
        let maxLon = coords.map(\.longitude).max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.8),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.8)
        )
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct FamilyTreeMapAvatar: View {
    var photoData: Data?
    var name: String

    var body: some View {
        Group {
            if let data = photoData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(SimpsonsTheme.orange.opacity(0.25))
                    Text(initials(from: name))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SimpsonsTheme.charcoal)
                }
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(SimpsonsTheme.charcoal.opacity(0.12), lineWidth: 1))
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
