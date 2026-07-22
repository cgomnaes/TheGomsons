//
//  HolidaysView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

/// Holiday hub: proposals (ideas + chat), upcoming planned trips, past trips, and world map.
struct HolidaysView: View {
    @Environment(\.openFamilyLanding) private var openFamilyLanding

    private enum HubSection: Int, CaseIterable, Identifiable {
        case upcoming
        case proposals
        case pastTrips
        case worldMap

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .upcoming: String(localized: "holidays.hub.upcoming")
            case .proposals: String(localized: "holidays.hub.ideas")
            case .pastTrips: String(localized: "holidays.hub.past")
            case .worldMap: String(localized: "holidays.hub.map")
            }
        }
    }

    @State private var section: HubSection = .upcoming
    @State private var showNewTrip = false
    @State private var showTripItImport = false
    @State private var newTripDefaultsToFuture = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(String(localized: "common.section"), selection: $section) {
                    ForEach(HubSection.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .tint(SimpsonsTheme.blue)

                Group {
                    switch section {
                    case .upcoming:
                        HolidayTripsListContent(filter: .upcoming)
                    case .proposals:
                        HolidayPlanningView()
                    case .pastTrips:
                        HolidayTripsListContent(filter: .past)
                    case .worldMap:
                        HolidayWorldMapView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(section == .pastTrips || section == .upcoming ? Color.clear : Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "holidays.hub.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if section == .upcoming || section == .pastTrips {
                            Button {
                                newTripDefaultsToFuture = (section == .upcoming)
                                showNewTrip = true
                            } label: {
                                Label(
                                    section == .upcoming
                                        ? String(localized: "holidays.new_upcoming")
                                        : String(localized: "holidays.log_past"),
                                    systemImage: "suitcase.cart.fill"
                                )
                            }
                        } else {
                            Button {
                                section = .upcoming
                                newTripDefaultsToFuture = true
                                showNewTrip = true
                            } label: {
                                Label(String(localized: "holidays.new_upcoming"), systemImage: "suitcase.cart.fill")
                            }
                        }
                        Button {
                            showTripItImport = true
                        } label: {
                            Label(String(localized: "holidays.import_tripit"), systemImage: "square.and.arrow.down.on.square")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel(String(localized: "holidays.add_or_import_a11y"))
                }
            }
            .sheet(isPresented: $showNewTrip) {
                AddHolidayTripSheet(defaultsToFuture: newTripDefaultsToFuture)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showTripItImport) {
                TripItImportView()
                    .presentationDetents([.large])
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
