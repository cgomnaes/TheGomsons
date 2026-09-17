//
//  ContentView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var landingAcks = LandingAckStore()
    /// Survives SwiftData container reloads after CloudKit import (unlike `@State`).
    @SceneStorage("gomsons.activeSection") private var activeSectionRaw = ""
    /// Bumped when returning home so the next visit starts at the section root (fresh NavigationStack).
    @State private var sectionNavigationEpoch = 0

    @Query(sort: \FamilyPerson.sortOrder) private var familyPeople: [FamilyPerson]
    @Query(sort: \FamilyEvent.date) private var familyEvents: [FamilyEvent]
    @Query(sort: \InventoryItem.name) private var inventoryItems: [InventoryItem]
    @Query(sort: \HolidayTrip.startDate) private var holidayTrips: [HolidayTrip]
    @Query(sort: \Subscription.sortOrder) private var subscriptions: [Subscription]
    @Query private var maintenanceEntries: [PropertyMaintenanceEntry]

    private var activeSection: AppRootTab? {
        get { AppRootTab(rawValue: activeSectionRaw) }
        nonmutating set { activeSectionRaw = newValue?.rawValue ?? "" }
    }

    private var cockerNews: [CockerNewsItem] {
        CockerFamilyNews.makeItems(
            people: familyPeople,
            events: familyEvents,
            inventory: inventoryItems,
            trips: holidayTrips,
            subscriptions: subscriptions,
            maintenance: maintenanceEntries
        )
    }

    var body: some View {
        ZStack {
            Group {
                if let section = activeSection {
                    sectionRoot(for: section)
                        .id("\(section.rawValue)-\(sectionNavigationEpoch)")
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    LandingPageView(
                        ackStore: landingAcks,
                        onSelectSection: { tab in
                            landingAcks.markSeen(tab)
                            withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                                activeSection = tab
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .environment(\.openFamilyLanding) {
                withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                    activeSection = nil
                    sectionNavigationEpoch += 1
                }
            }

            // Only peek when there is news — no idle decorative pops.
            CockerSpanielPeekOverlay(
                isSuppressed: cockerNews.isEmpty,
                newsItems: cockerNews,
                onOpenNews: { item in
                    landingAcks.markSeen(item.section)
                    withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                        activeSection = item.section
                    }
                }
            )
            .zIndex(0.5)
        }
        .tint(SimpsonsTheme.blue)
        .task {
            PastHolidayHistorySeeder.seedIfNeeded(in: modelContext)
        }
    }

    @ViewBuilder
    private func sectionRoot(for section: AppRootTab) -> some View {
        switch section {
        case .holidays:
            HolidaysView()
        case .properties:
            PropertyListView()
        case .stash:
            InventoryListView()
        case .calendar:
            CalendarView()
        case .subs:
            SubscriptionsView()
        case .familyTree:
            FamilyTreeView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                Asset.self,
                InventoryItem.self,
                InventoryItemLink.self,
                InventoryItemDocument.self,
                Property.self,
                PropertyContact.self,
                PropertyEmergencyLine.self,
                Location.self,
                Recipe.self,
                FamilyEvent.self,
                HolidayTrip.self,
                HolidayDestination.self,
            HolidayTripParticipant.self,
            HolidayTripGuest.self,
            HolidayPlanItem.self,
                VacationIdea.self,
                HolidayChatMessage.self,
                FamilyPerson.self,
                FamilyGroupPhoto.self,
                Subscription.self,
                Recipe.self,
                PropertyMaintenanceEntry.self,
            ],
            inMemory: true
        )
}
