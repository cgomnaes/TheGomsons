//
//  CockerFamilyNews.swift
//  TheGomsons
//
//  Short “woof” headlines the peek dog can bring from shared family data.
//

import Foundation
import SwiftData

/// One tip the cocker can surface; tapping opens the related app section.
struct CockerNewsItem: Identifiable, Equatable, Hashable {
    let id: String
    let message: String
    let section: AppRootTab
    /// Lower = more urgent (shown first).
    let priority: Int
}

enum CockerFamilyNews {
    private static let epoch = Date(timeIntervalSince1970: 0)

    /// Builds a priority-sorted list of timely family headlines.
    static func makeItems(
        people: [FamilyPerson],
        events: [FamilyEvent],
        inventory: [InventoryItem],
        trips: [HolidayTrip],
        subscriptions: [Subscription],
        maintenance: [PropertyMaintenanceEntry] = [],
        now: Date = Date()
    ) -> [CockerNewsItem] {
        var items: [CockerNewsItem] = []
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        for person in people where !person.isDeceased && person.includeBirthdayOnCalendar {
            guard let days = person.daysUntilNextBirthday(after: now), days <= 14 else { continue }
            let name = person.displayName
            guard !name.isEmpty else { continue }
            let message: String
            if days == 0 {
                message = String(format: String(localized: "cocker.news.birthday_today"), locale: .current, name)
            } else if days == 1 {
                message = String(format: String(localized: "cocker.news.birthday_tomorrow"), locale: .current, name)
            } else {
                message = String(format: String(localized: "cocker.news.birthday_soon"), locale: .current, name, days)
            }
            items.append(
                CockerNewsItem(
                    id: "bday-\(person.persistentModelID)",
                    message: message,
                    section: .familyTree,
                    priority: days
                )
            )
        }

        for event in events where event.dontForget {
            let day = cal.startOfDay(for: event.date)
            let days = cal.dateComponents([.day], from: today, to: day).day ?? 999
            guard days >= 0, days <= 14 else { continue }
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let message: String
            if days == 0 {
                message = String(format: String(localized: "cocker.news.dont_forget_today"), locale: .current, title)
            } else {
                message = String(format: String(localized: "cocker.news.dont_forget_soon"), locale: .current, title, days)
            }
            items.append(
                CockerNewsItem(
                    id: "forget-\(event.persistentModelID)",
                    message: message,
                    section: .calendar,
                    priority: 20 + days
                )
            )
        }

        for item in inventory {
            let expiry = item.warrantyExpiry
            guard expiry > epoch else { continue }
            let day = cal.startOfDay(for: expiry)
            let days = cal.dateComponents([.day], from: today, to: day).day ?? 999
            guard days >= 0, days <= 30 else { continue }
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let message: String
            if days == 0 {
                message = String(format: String(localized: "cocker.news.warranty_today"), locale: .current, name)
            } else {
                message = String(format: String(localized: "cocker.news.warranty_soon"), locale: .current, name, days)
            }
            items.append(
                CockerNewsItem(
                    id: "warranty-\(item.persistentModelID)",
                    message: message,
                    section: .stash,
                    priority: 40 + days
                )
            )
        }

        for trip in trips {
            guard trip.startDate > epoch else { continue }
            let start = cal.startOfDay(for: trip.startDate)
            let days = cal.dateComponents([.day], from: today, to: start).day ?? 999
            guard days >= 0, days <= 21 else { continue }
            let name = trip.tripName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let message: String
            if days == 0 {
                message = String(format: String(localized: "cocker.news.trip_today"), locale: .current, name)
            } else if days == 1 {
                message = String(format: String(localized: "cocker.news.trip_tomorrow"), locale: .current, name)
            } else {
                message = String(format: String(localized: "cocker.news.trip_soon"), locale: .current, name, days)
            }
            items.append(
                CockerNewsItem(
                    id: "trip-\(trip.persistentModelID)",
                    message: message,
                    section: .holidays,
                    priority: 10 + days
                )
            )
        }

        for sub in subscriptions {
            guard let renewal = sub.renewalDate else { continue }
            let day = cal.startOfDay(for: renewal)
            let days = cal.dateComponents([.day], from: today, to: day).day ?? 999
            guard days >= 0, days <= 30 else { continue }
            let name = sub.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let message: String
            if days == 0 {
                message = String(format: String(localized: "cocker.news.sub_today"), locale: .current, name)
            } else {
                message = String(format: String(localized: "cocker.news.sub_soon"), locale: .current, name, days)
            }
            items.append(
                CockerNewsItem(
                    id: "sub-\(sub.persistentModelID)",
                    message: message,
                    section: .subs,
                    priority: 50 + days
                )
            )
        }

        for entry in maintenance {
            guard let days = entry.daysUntilDue(after: now), days <= 30 else { continue }
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let place = entry.property?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let label = place.isEmpty ? title : "\(title) · \(place)"
            let message: String
            if days < 0 {
                message = String(format: String(localized: "cocker.news.maint_overdue"), locale: .current, label, abs(days))
            } else if days == 0 {
                message = String(format: String(localized: "cocker.news.maint_today"), locale: .current, label)
            } else {
                message = String(format: String(localized: "cocker.news.maint_soon"), locale: .current, label, days)
            }
            items.append(
                CockerNewsItem(
                    id: "maint-\(entry.persistentModelID)",
                    message: message,
                    section: .properties,
                    priority: max(0, 5 + days)
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.message.localizedCaseInsensitiveCompare(rhs.message) == .orderedAscending
        }
    }
}
