//
//  HolidaysView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

/// Holiday hub: celebrations and trips (each with upcoming/past), ideas, map.
struct HolidaysView: View {
    @Environment(\.openFamilyLanding) private var openFamilyLanding

    private enum HubSection: Int, CaseIterable, Identifiable {
        case celebrations
        case trips
        case proposals
        case worldMap

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .celebrations: String(localized: "holidays.hub.celebrations")
            case .trips: String(localized: "holidays.hub.trips")
            case .proposals: String(localized: "holidays.hub.ideas")
            case .worldMap: String(localized: "holidays.hub.map")
            }
        }

        var systemImage: String {
            switch self {
            case .celebrations: "party.popper.fill"
            case .trips: "suitcase.fill"
            case .proposals: "lightbulb.fill"
            case .worldMap: "map.fill"
            }
        }
    }

    private enum TimeFilter: Int, CaseIterable, Identifiable {
        case upcoming
        case past

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .upcoming: String(localized: "holidays.time.upcoming")
            case .past: String(localized: "holidays.time.past")
            }
        }
    }

    @State private var section: HubSection = .celebrations
    @State private var celebrationFilter: TimeFilter = .upcoming
    @State private var tripFilter: TimeFilter = .upcoming
    @State private var showNewTrip = false
    @State private var showNewCelebration = false
    @State private var showTripItImport = false
    @State private var newTripDefaultsToFuture = true
    @State private var newCelebrationDefaultsToFuture = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                hubSectionPicker
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                if section == .celebrations || section == .trips {
                    Picker(String(localized: "celebration.time_filter"), selection: timeFilterBinding) {
                        ForEach(TimeFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .tint(section == .celebrations ? SimpsonsTheme.pink : SimpsonsTheme.blue)
                }

                Group {
                    switch section {
                    case .celebrations:
                        HolidayCelebrationsListContent(
                            timeFilter: celebrationFilter == .upcoming ? .upcoming : .past
                        )
                    case .trips:
                        HolidayTripsListContent(
                            filter: tripFilter == .upcoming ? .upcoming : .past
                        )
                    case .proposals:
                        HolidayPlanningView()
                    case .worldMap:
                        HolidayWorldMapView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(backgroundForSection)
            .navigationTitle(String(localized: "holidays.hub.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if section == .celebrations {
                            Button {
                                newCelebrationDefaultsToFuture = (celebrationFilter == .upcoming)
                                showNewCelebration = true
                            } label: {
                                Label(
                                    celebrationFilter == .upcoming
                                        ? String(localized: "holidays.new_celebration")
                                        : String(localized: "celebration.log_past"),
                                    systemImage: "party.popper.fill"
                                )
                            }
                        }
                        if section == .trips {
                            Button {
                                newTripDefaultsToFuture = (tripFilter == .upcoming)
                                showNewTrip = true
                            } label: {
                                Label(
                                    tripFilter == .upcoming
                                        ? String(localized: "holidays.new_upcoming")
                                        : String(localized: "holidays.log_past"),
                                    systemImage: "suitcase.cart.fill"
                                )
                            }
                        }
                        if section == .proposals || section == .worldMap {
                            Button {
                                section = .celebrations
                                celebrationFilter = .upcoming
                                newCelebrationDefaultsToFuture = true
                                showNewCelebration = true
                            } label: {
                                Label(String(localized: "holidays.new_celebration"), systemImage: "party.popper.fill")
                            }
                            Button {
                                section = .trips
                                tripFilter = .upcoming
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
                AddHolidayTripSheet(defaultsToFuture: newTripDefaultsToFuture, defaultKind: .trip)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showNewCelebration) {
                AddHolidayCelebrationSheet(defaultsToFuture: newCelebrationDefaultsToFuture)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showTripItImport) {
                TripItImportView()
                    .presentationDetents([.large])
            }
        }
    }

    private var timeFilterBinding: Binding<TimeFilter> {
        Binding(
            get: { section == .celebrations ? celebrationFilter : tripFilter },
            set: { newValue in
                if section == .celebrations {
                    celebrationFilter = newValue
                } else {
                    tripFilter = newValue
                }
            }
        )
    }

    private var backgroundForSection: Color {
        switch section {
        case .celebrations, .trips:
            Color.clear
        default:
            Color(.systemGroupedBackground)
        }
    }

    /// Menu avoids cramped segmented labels (Norwegian + several sections on iPhone).
    private var hubSectionPicker: some View {
        Menu {
            Picker(String(localized: "common.section"), selection: $section) {
                ForEach(HubSection.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .foregroundStyle(section == .celebrations ? SimpsonsTheme.purple : SimpsonsTheme.blue)
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
        }
        .tint(section == .celebrations ? SimpsonsTheme.purple : SimpsonsTheme.blue)
    }
}

#Preview {
    HolidaysView()
        .modelContainer(
            for: [
                HolidayTrip.self,
                HolidayDestination.self,
                HolidayTripParticipant.self,
                HolidayTripGuest.self,
                HolidayPlanItem.self,
                VacationIdea.self,
                HolidayChatMessage.self,
            ],
            inMemory: true
        )
}
