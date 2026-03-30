//
//  AppRootTab.swift
//  TheGomsons
//

import Combine
import Foundation
import SwiftUI

/// Primary tab destinations. Order here = order on landing page and tab bar.
enum AppRootTab: String, CaseIterable, Identifiable, Hashable {
    case holidays
    case dashboard
    case properties
    case inventory
    case hub

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holidays: "Holidays"
        case .dashboard: "Dashboard"
        case .properties: "Properties"
        case .inventory: "Inventory"
        case .hub: "Hub"
        }
    }

    var systemImage: String {
        switch self {
        case .holidays: "airplane.circle.fill"
        case .dashboard: "chart.bar.fill"
        case .properties: "building.2.fill"
        case .inventory: "archivebox.fill"
        case .hub: "square.grid.2x2.fill"
        }
    }

    /// Bump when that area has noteworthy updates; stars clear after user opens that tab.
    var contentRevision: Int {
        switch self {
        case .holidays: 2
        case .dashboard: 1
        case .properties: 1
        case .inventory: 1
        case .hub: 1
        }
    }

    var tileColor: Color {
        switch self {
        case .holidays: SimpsonsTheme.blue
        case .dashboard: SimpsonsTheme.orange
        case .properties: SimpsonsTheme.brown
        case .inventory: SimpsonsTheme.pink
        case .hub: SimpsonsTheme.green
        }
    }
}

// MARK: - Simpsons colour palette (shared across app)

enum SimpsonsTheme {
    static let yellow = Color(red: 1.0, green: 0.82, blue: 0.0)
    static let blue = Color(red: 0.28, green: 0.56, blue: 0.92)
    static let skyBlue = Color(red: 0.45, green: 0.75, blue: 1.0)
    static let orange = Color(red: 0.98, green: 0.55, blue: 0.14)
    static let pink = Color(red: 0.96, green: 0.42, blue: 0.58)
    static let green = Color(red: 0.30, green: 0.78, blue: 0.38)
    static let brown = Color(red: 0.64, green: 0.42, blue: 0.24)
    static let white = Color.white
    static let charcoal = Color(red: 0.15, green: 0.15, blue: 0.18)
}

// MARK: - "New / updated" acknowledgements

private let landingAckUserDefaultsKey = "landingSectionAckRevisions"

@MainActor
final class LandingAckStore: ObservableObject {
    @Published private(set) var ackRevisionByTab: [String: Int] = [:]

    init() {
        reloadFromDefaults()
    }

    func reloadFromDefaults() {
        if let data = UserDefaults.standard.data(forKey: landingAckUserDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            ackRevisionByTab = decoded
        } else {
            ackRevisionByTab = [:]
        }
    }

    func acknowledgedRevision(for tab: AppRootTab) -> Int {
        ackRevisionByTab[tab.rawValue] ?? 0
    }

    func hasHighlight(for tab: AppRootTab) -> Bool {
        acknowledgedRevision(for: tab) < tab.contentRevision
    }

    func markSeen(_ tab: AppRootTab) {
        ackRevisionByTab[tab.rawValue] = tab.contentRevision
        persist()
    }

    func markAllCurrent() {
        for tab in AppRootTab.allCases {
            ackRevisionByTab[tab.rawValue] = tab.contentRevision
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(ackRevisionByTab) {
            UserDefaults.standard.set(data, forKey: landingAckUserDefaultsKey)
        }
    }
}

// MARK: - Shared home button

/// Yellow "G" home button used in every section's toolbar to return to the landing page.
func homeButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        ZStack {
            Circle()
                .fill(SimpsonsTheme.yellow)
                .frame(width: 32, height: 32)
            Text("G")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(SimpsonsTheme.charcoal)
        }
    }
    .accessibilityLabel("Home")
}

// MARK: - Open landing from tabs

private struct OpenLandingKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openFamilyLanding: () -> Void {
        get { self[OpenLandingKey.self] }
        set { self[OpenLandingKey.self] = newValue }
    }
}
