//
//  PastHolidayHistorySeeder.swift
//  TheGomsons
//
//  One-time import of legacy family trip CSV into `HolidayTrip` (shows under Holidays → Past).
//

import Foundation
import SwiftData

enum PastHolidayHistorySeeder {
    /// Bumped when seed data is corrected so installs can re-apply (see `seedIfNeeded`).
    private static let seededKey = "TheGomsons.PastHolidayHistorySeeded.v3"
    private static let legacySeededKey = "TheGomsons.PastHolidayHistorySeeded.v1"
    private static let legacyV2Key = "TheGomsons.PastHolidayHistorySeeded.v2"

    /// Malaga-area trips use **Marbella** as the label. Alicante-area trips use **Mar Menor**.
    /// Standalone **Zurich** legs are omitted (not counted as Zermatt/Saas Fee holidays).
    private static let rows: [(String, String, String)] = [
        ("Canary Islands 2009", "Apr 27 – May 04, 2009", "Lanzarote (ACE)"),
        ("Nice Summer 2009", "Jun 14 – Jun 17, 2009", "Nice (NCE)"),
        ("Zermatt/Saas Fee Winter 2010", "Jan 28 – Feb 01, 2010", "Geneva (GVA)"),
        ("Zermatt/Saas Fee Spring 2010", "Apr 16 – Apr 18, 2010", "Geneva (GVA)"),
        ("Nice Summer 2010", "Jun 13 – Jun 16, 2010", "Nice (NCE)"),
        ("Marbella Winter 2011", "Feb 13, 2011", "Marbella"),
        ("Mar Menor Spring 2011", "Apr 28 – May 06, 2011", "Mar Menor"),
        ("Marbella Autumn 2011", "Sep 08 – Sep 11, 2011", "Marbella"),
        ("Mar Menor Oct 2011", "Oct 09, 2011", "Mar Menor"),
        ("Mar Menor Spring 2012", "Apr 05 – Apr 08, 2012", "Mar Menor"),
        ("Marbella April 2012", "Apr 12 – Apr 15, 2012", "Marbella"),
        ("Marbella August 2012", "Aug 02 – Aug 09, 2012", "Marbella"),
        ("Mar Menor Autumn 2012", "Sep 23 – Oct 07, 2012", "Mar Menor"),
        ("Mar Menor Summer 2013", "Jun 18 – Jul 02, 2013", "Mar Menor"),
        ("Mar Menor Autumn 2013", "Sep 27 – Oct 06, 2013", "Mar Menor"),
        ("Zermatt/Saas Fee Winter 2014", "Mar 06 – Mar 09, 2014", "Geneva (GVA)"),
        ("Los Angeles Spring 2014", "Apr 10 – Apr 20, 2014", "Los Angeles (LAX)"),
        ("Mar Menor Summer 2014", "Jun 22 – Jul 06, 2014", "Mar Menor"),
        ("Zermatt/Saas Fee Winter 2015", "Mar 06 – Mar 08, 2015", "Geneva (GVA)"),
        ("Mar Menor August 2015", "Aug 04 – Aug 15, 2015", "Mar Menor"),
        ("Miami Autumn 2015", "Oct 23 – Oct 31, 2015", "Miami (MIA)"),
        ("Thailand Winter 2016", "Feb 19 – Feb 28, 2016", "Bangkok (BKK) / Phuket (HKT)"),
        ("Zermatt/Saas Fee Winter 2016", "Mar 19 – Mar 26, 2016", "Geneva (GVA)"),
        ("Marbella Spring 2016", "May 06 – May 10, 2016", "Marbella"),
        ("Marbella Summer 2016", "Jun 18 – Jun 24, 2016", "Marbella"),
        ("Miami Spring 2017", "Mar 24 – Mar 28, 2017", "Miami (MIA)"),
        ("Marbella Spring 2017", "May 04 – May 08, 2017", "Marbella"),
        ("Mar Menor August 2017", "Aug 05 – Aug 19, 2017", "Mar Menor"),
        ("Marbella Autumn 2017", "Sep 29 – Oct 08, 2017", "Marbella"),
        ("Cancun Winter 2018", "Feb 16 – Feb 24, 2018", "Cancun (CUN)"),
        ("Marbella Summer 2018", "Jun 22 – Jul 06, 2018", "Marbella"),
        ("Marbella August 2018", "Aug 31 – Sep 02, 2018", "Marbella"),
        ("Marbella Oct 2018", "Sep 29 – Oct 08, 2018", "Marbella"),
        ("Zermatt/Saas Fee Summer 2019", "Jul 02, 2019", "Geneva (GVA)"),
        ("Nice Summer 2019", "Jul 16, 2019", "Nice (NCE)"),
        ("Zermatt/Saas Fee Winter 2020", "Feb 27 – Mar 02, 2020", "Geneva (GVA)"),
        ("Mar Menor Summer 2021", "Jul 21 – Aug 01, 2021", "Mar Menor"),
        ("Marbella Autumn 2021", "Oct 01 – Oct 10, 2021", "Marbella"),
        ("Zermatt/Saas Fee Jan 2022", "Jan 27 – Feb 03, 2022", "Geneva (GVA)"),
        ("Marbella Feb 2022", "Feb 06 – Feb 10, 2022", "Marbella"),
        ("Marbella July 2022", "Jul 04, 2022", "Marbella"),
        ("Zermatt/Saas Fee Winter 2023", "Feb 02 – Feb 06, 2023", "Geneva (GVA)"),
        ("Los Angeles Feb 2023", "Feb 18, 2023", "Los Angeles (LAX)"),
        ("Marbella Oct 2023", "Oct 13 – Oct 16, 2023", "Marbella"),
        ("Zermatt/Saas Fee Feb 2024", "Feb 01 – Feb 04, 2024", "Geneva (GVA)"),
        ("Nice Summer 2024", "Jun 22 – Jul 07, 2024", "Nice (NCE)"),
        ("Marbella Oct 2024", "Oct 25 – Oct 27, 2024", "Marbella"),
        ("Zermatt/Saas Fee Feb 2025", "Feb 06 – Feb 09, 2025", "Geneva (GVA)"),
        ("Los Angeles March 2025", "Mar 16, 2025", "Los Angeles (LAX)"),
        ("Canary Islands April 2025", "Apr 13 – Apr 21, 2025", "Las Palmas (LPA)"),
        ("Boston Summer 2025", "Jul 13, 2025", "Boston (BOS)"),
        ("Nice Oct 2025", "Oct 14 – Oct 16, 2025", "Nice (NCE)"),
        ("Los Angeles Feb 2026", "Feb 05 – Feb 10, 2026", "Los Angeles (LAX)"),
        ("Thailand March 2026", "Mar 03 – Mar 22, 2026", "Bangkok (BKK) / Phuket (HKT)"),
    ]

    /// Inserts the legacy family trip list once per seed version; replaces prior imported rows when upgrading from v1/v2.
    static func seedIfNeeded(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        let importedNote = "Imported family trip history"
        let descriptor = FetchDescriptor<HolidayTrip>(
            predicate: #Predicate<HolidayTrip> { $0.notes == importedNote }
        )
        if let old = try? context.fetch(descriptor) {
            for t in old {
                context.delete(t)
            }
        }
        UserDefaults.standard.removeObject(forKey: legacySeededKey)
        UserDefaults.standard.removeObject(forKey: legacyV2Key)
        try? context.save()

        let cal = Calendar.current
        for row in rows {
            let (title, dateColumn, destination) = row
            guard let range = parseTravelDates(dateColumn) else { continue }
            let start = cal.startOfDay(for: range.start)
            let end = cal.startOfDay(for: range.end)

            let dest = HolidayDestination(
                locationName: destination,
                latitude: 0,
                longitude: 0,
                arrivalDate: start,
                departureDate: end,
                activities: ""
            )

            let trip = HolidayTrip(
                tripName: title,
                startDate: start,
                endDate: end,
                notes: "Imported family trip history",
                mainAccommodation: destination,
                coverPlaceName: destination,
                destinations: [dest]
            )
            dest.trip = trip
            context.insert(trip)
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: seededKey)
        } catch {
            print("[TheGomsons] PastHolidayHistorySeeder seed failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Date parsing (CSV uses en-dash “–” between range ends)

    private static func parseTravelDates(_ raw: String) -> (start: Date, end: Date)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts: [String]
        if trimmed.contains(" – ") {
            parts = trimmed.components(separatedBy: " – ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else if trimmed.contains(" - ") {
            parts = trimmed.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            parts = [trimmed]
        }

        if parts.count == 1 {
            guard let d = parseMonthDayCommaYear(parts[0]) else { return nil }
            return (d, d)
        }

        guard parts.count == 2 else { return nil }
        let left = parts[0]
        let right = parts[1]

        guard let endDate = parseMonthDayCommaYear(right) else { return nil }
        let year = Calendar.current.component(.year, from: endDate)
        let startDate: Date
        if left.contains(",") {
            startDate = parseMonthDayCommaYear(left) ?? endDate
        } else {
            startDate = parseMonthDayYear(left, year: year) ?? endDate
        }
        return (startDate, endDate)
    }

    private static func parseMonthDayCommaYear(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "MMM d, yyyy"
        return f.date(from: s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parseMonthDayYear(_ monthDay: String, year: Int) -> Date? {
        let combined = "\(monthDay.trimmingCharacters(in: .whitespacesAndNewlines)) \(year)"
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "MMM d yyyy"
        return f.date(from: combined)
    }
}
