//
//  AppRootTab.swift
//  TheGomsons
//

import Combine
import Foundation
import SwiftUI

/// Primary app sections. Order here = order of tiles on the family landing page.
enum AppRootTab: String, CaseIterable, Identifiable, Hashable {
    case holidays
    case properties
    case stash
    case calendar
    case subs
    case familyTree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holidays: String(localized: "tab.holidays")
        case .properties: String(localized: "tab.properties")
        case .stash: String(localized: "tab.stash")
        case .calendar: String(localized: "tab.calendar")
        case .subs: String(localized: "tab.subs")
        case .familyTree: String(localized: "tab.family_tree")
        }
    }

    var systemImage: String {
        switch self {
        case .holidays: "airplane.circle.fill"
        case .properties: "building.2.fill"
        case .stash: "archivebox.fill"
        case .calendar: "calendar.circle.fill"
        case .subs: "creditcard.fill"
        case .familyTree: "person.3.sequence.fill"
        }
    }

    /// Bump when that area has noteworthy updates; stars clear after the user opens that section.
    var contentRevision: Int {
        switch self {
        case .holidays: 2
        case .properties: 1
        case .stash: 3
        case .calendar: 2
        case .subs: 1
        case .familyTree: 3
        }
    }

    var tileColor: Color {
        switch self {
        case .holidays: SimpsonsTheme.blue
        case .properties: SimpsonsTheme.brown
        case .stash: SimpsonsTheme.pink
        case .calendar: SimpsonsTheme.green
        case .subs: SimpsonsTheme.purple
        case .familyTree: SimpsonsTheme.orange
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
    static let purple = Color(red: 0.45, green: 0.38, blue: 0.82)
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
    .accessibilityLabel(String(localized: "home.accessibility"))
}

// MARK: - Return to family landing

private struct OpenLandingKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Leaves the current section and returns to the landing hub (resets that section’s stack).
    var openFamilyLanding: () -> Void {
        get { self[OpenLandingKey.self] }
        set { self[OpenLandingKey.self] = newValue }
    }
}
