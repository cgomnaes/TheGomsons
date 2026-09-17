//
//  PropertyCabinVisitsView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

enum PropertyCabinVisitSchedule {
    static func upcomingTrips(for property: Property, from trips: [HolidayTrip]) -> [HolidayTrip] {
        let propertyID = property.persistentModelID
        return trips
            .filter { trip in
                !trip.isPastTrip
                    && trip.linkedProperty?.persistentModelID == propertyID
            }
            .sorted { $0.startDate < $1.startDate }
    }

    static func nextTrip(for familyMember: String, property: Property, trips: [HolidayTrip]) -> HolidayTrip? {
        let name = familyMember.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return upcomingTrips(for: property, from: trips).first { trip in
            (trip.participants ?? []).contains { participant in
                participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(name) == .orderedSame
            }
        }
    }

    static func participantNames(for trip: HolidayTrip) -> [String] {
        (trip.participants ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func dateRangePhrase(for trip: HolidayTrip) -> String {
        let a = trip.startDate.formatted(date: .abbreviated, time: .omitted)
        let b = trip.endDate.formatted(date: .abbreviated, time: .omitted)
        return "\(a) – \(b)"
    }
}

/// Upcoming cabin visits per family member for a vacation-home property.
struct PropertyCabinVisitsSection: View {
    let property: Property
    let upcomingTrips: [HolidayTrip]
    var compact: Bool = false
    var showsHeader: Bool = true

    private var scheduledVisits: [(member: String, trip: HolidayTrip)] {
        HolidayFamilyVoter.allCases.compactMap { voter in
            guard let trip = PropertyCabinVisitSchedule.nextTrip(for: voter.rawValue, property: property, trips: upcomingTrips) else {
                return nil
            }
            return (voter.rawValue, trip)
        }
    }

    var body: some View {
        if property.isVacationHome, !scheduledVisits.isEmpty {
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                if showsHeader {
                    Label(String(localized: "property.cabin.next_visits"), systemImage: "calendar.badge.clock")
                        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(compact ? .secondary : .primary)
                }

                VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                    ForEach(scheduledVisits, id: \.member) { visit in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(visit.member)
                                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                                .foregroundStyle(compact ? .secondary : .primary)
                            Text(PropertyCabinVisitSchedule.dateRangePhrase(for: visit.trip))
                                .font(compact ? .caption : .subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }

                        let others = PropertyCabinVisitSchedule.participantNames(for: visit.trip)
                            .filter { $0.localizedCaseInsensitiveCompare(visit.member) != .orderedSame }
                        if !others.isEmpty {
                            Text(
                                String(
                                    format: String(localized: "property.cabin.with_others"),
                                    locale: .current,
                                    others.joined(separator: ", ")
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
