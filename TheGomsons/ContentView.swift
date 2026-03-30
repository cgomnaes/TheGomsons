//
//  ContentView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @StateObject private var landingAcks = LandingAckStore()
    @State private var showLanding = true
    @State private var selectedTab: AppRootTab = .holidays

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HolidaysView()
                    .tabItem { Label(AppRootTab.holidays.title, systemImage: AppRootTab.holidays.systemImage) }
                    .tag(AppRootTab.holidays)

                DashboardView()
                    .tabItem { Label(AppRootTab.dashboard.title, systemImage: AppRootTab.dashboard.systemImage) }
                    .tag(AppRootTab.dashboard)

                PropertyListView()
                    .tabItem { Label(AppRootTab.properties.title, systemImage: AppRootTab.properties.systemImage) }
                    .tag(AppRootTab.properties)

                InventoryListView()
                    .tabItem { Label(AppRootTab.inventory.title, systemImage: AppRootTab.inventory.systemImage) }
                    .tag(AppRootTab.inventory)

                HubView()
                    .tabItem { Label(AppRootTab.hub.title, systemImage: AppRootTab.hub.systemImage) }
                    .tag(AppRootTab.hub)
            }
            .tint(SimpsonsTheme.blue)
            .environment(\.openFamilyLanding) {
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                    showLanding = true
                }
            }
            .onChange(of: selectedTab) { _, new in
                landingAcks.markSeen(new)
            }
            .toolbar(showLanding ? .hidden : .automatic, for: .tabBar)

            if showLanding {
                LandingPageView(
                    ackStore: landingAcks,
                    onSelectSection: { tab in
                        selectedTab = tab
                        landingAcks.markSeen(tab)
                        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                            showLanding = false
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                Asset.self,
                InventoryItem.self,
                Property.self,
                PropertyContact.self,
                PropertyEmergencyLine.self,
                Location.self,
                Recipe.self,
                FamilyEvent.self,
                HolidayTrip.self,
                HolidayDestination.self,
                HolidayTripParticipant.self,
                VacationIdea.self,
                HolidayChatMessage.self,
            ],
            inMemory: true
        )
}
