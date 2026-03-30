//
//  HolidaysView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

/// Holiday hub: plan & vote, past trips, and world map.
struct HolidaysView: View {
    @Environment(\.openFamilyLanding) private var openFamilyLanding

    private enum HubSection: String, CaseIterable, Identifiable {
        case planNext = "Plan Next"
        case pastTrips = "Past Trips"
        case worldMap = "World Map"

        var id: String { rawValue }
    }

    @State private var section: HubSection = .planNext
    @State private var showNewTrip = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(HubSection.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .tint(SimpsonsTheme.blue)

                Group {
                    switch section {
                    case .planNext:
                        HolidayPlanningView()
                    case .pastTrips:
                        HolidaysPastTripsContent()
                    case .worldMap:
                        HolidayWorldMapView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(section == .pastTrips ? Color.clear : Color(.systemGroupedBackground))
            .navigationTitle("Holiday Hub")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                if section == .pastTrips {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showNewTrip = true
                        } label: {
                            Image(systemName: "suitcase.cart.fill")
                                .symbolRenderingMode(.multicolor)
                        }
                        .accessibilityLabel("New trip")
                    }
                }
            }
            .sheet(isPresented: $showNewTrip) {
                AddHolidayTripSheet()
            }
        }
    }
}

#Preview {
    HolidaysView()
        .modelContainer(
            for: [
                HolidayTrip.self,
                HolidayDestination.self,
                HolidayTripParticipant.self,
                VacationIdea.self,
                HolidayChatMessage.self,
            ],
            inMemory: true
        )
}
