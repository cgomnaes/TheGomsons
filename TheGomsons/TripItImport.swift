//
//  TripItImport.swift
//  TheGomsons
//
//  Imports travel plans from TripIt via:
//  - .ics / calendar file export (TripIt website → Export trip to calendar)
//  - TripIt calendar feed URL (Settings → Calendar Feed; webcal:// or https://)
//

import Foundation
import SwiftData

enum TripItImport {

    struct ParsedStop: Identifiable, Hashable, Sendable {
        var id: String { "\(locationName)-\(arrivalDate.timeIntervalSince1970)-\(departureDate.timeIntervalSince1970)" }
        var locationName: String
        var arrivalDate: Date
        var departureDate: Date
        var activities: String
        var kind: StopKind

        enum StopKind: String, Sendable {
            case flight
            case lodging
            case activity
            case transport
            case other
        }
    }

    struct ParsedTrip: Identifiable, Hashable, Sendable {
        var id: String
        var tripName: String
        var startDate: Date
        var endDate: Date
        var notes: String
        var airlineName: String
        var bookingReference: String
        var mainAccommodation: String
        var coverPlaceName: String
        var stops: [ParsedStop]
    }

    struct ImportResult: Sendable {
        var imported: Int
        var skippedDuplicates: Int
        var warnings: [String]
    }

    enum ImportError: LocalizedError {
        case empty
        case notCalendar
        case noEvents
        case network(String)
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .empty: String(localized: "tripit.err.empty")
            case .notCalendar: String(localized: "tripit.err.not_calendar")
            case .noEvents: String(localized: "tripit.err.no_events")
            case .network(let message): message
            case .invalidURL: String(localized: "tripit.err.invalid_url")
            }
        }
    }

    // MARK: - Public entry points

    static func parseICS(data: Data) throws -> [ParsedTrip] {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else { throw ImportError.empty }
        return try parseICS(text: text)
    }

    static func parseICS(text: String) throws -> [ParsedTrip] {
        let unfolded = unfoldICSLines(text)
        guard unfolded.uppercased().contains("BEGIN:VCALENDAR") || unfolded.uppercased().contains("BEGIN:VEVENT") else {
            throw ImportError.notCalendar
        }
        let events = parseVEvents(from: unfolded)
        guard !events.isEmpty else { throw ImportError.noEvents }
        let trips = clusterIntoTrips(events)
        guard !trips.isEmpty else { throw ImportError.noEvents }
        return trips
    }

    /// Fetches a TripIt calendar feed. Accepts `webcal://` / `https://` URLs.
    static func fetchICS(from rawURL: String) async throws -> [ParsedTrip] {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.invalidURL }
        var normalized = trimmed
            .replacingOccurrences(of: "webcal://", with: "https://", options: .caseInsensitive)
            .replacingOccurrences(of: "webcals://", with: "https://", options: .caseInsensitive)
        if !normalized.lowercased().hasPrefix("http://"), !normalized.lowercased().hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        guard let url = URL(string: normalized) else { throw ImportError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue("text/calendar, text/plain, */*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                throw ImportError.network(String(format: String(localized: "tripit.err.http"), locale: .current, http.statusCode))
            }
            return try parseICS(data: data)
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.network(error.localizedDescription)
        }
    }

    /// Inserts trips that don’t already exist (same name + overlapping dates).
    @MainActor
    static func importTrips(
        _ trips: [ParsedTrip],
        selectedIDs: Set<String>,
        into modelContext: ModelContext,
        existing: [HolidayTrip]
    ) -> ImportResult {
        var imported = 0
        var skipped = 0
        var warnings: [String] = []
        let calendar = Calendar.current

        for trip in trips where selectedIDs.contains(trip.id) {
            let duplicate = existing.contains { existingTrip in
                existingTrip.tripName.caseInsensitiveCompare(trip.tripName) == .orderedSame
                    && calendar.isDate(existingTrip.startDate, inSameDayAs: trip.startDate)
                    && calendar.isDate(existingTrip.endDate, inSameDayAs: trip.endDate)
            }
            if duplicate {
                skipped += 1
                continue
            }

            let holiday = HolidayTrip(
                tripName: trip.tripName,
                startDate: trip.startDate,
                endDate: trip.endDate,
                notes: trip.notes,
                airlineName: trip.airlineName,
                bookingReference: trip.bookingReference,
                mainAccommodation: trip.mainAccommodation,
                coverPlaceName: trip.coverPlaceName
            )
            modelContext.insert(holiday)

            for stop in trip.stops {
                let destination = HolidayDestination(
                    locationName: stop.locationName,
                    latitude: 0,
                    longitude: 0,
                    arrivalDate: stop.arrivalDate,
                    departureDate: stop.departureDate,
                    activities: stop.activities.isEmpty ? stop.kind.rawValue.capitalized : stop.activities,
                    trip: holiday
                )
                modelContext.insert(destination)
            }
            imported += 1
        }

        if imported == 0, skipped > 0 {
            warnings.append(String(localized: "tripit.warn.all_duplicates"))
        }

        return ImportResult(imported: imported, skippedDuplicates: skipped, warnings: warnings)
    }

    // MARK: - ICS parsing

    private struct ICSEvent {
        var uid: String
        var summary: String
        var location: String
        var description: String
        var start: Date
        var end: Date
        var allDay: Bool
        var tripTitleHint: String?
    }

    private static func unfoldICSLines(_ text: String) -> String {
        // RFC 5545 line folding: CRLF + space/tab continues the previous line.
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
    }

    private static func parseVEvents(from text: String) -> [ICSEvent] {
        var events: [ICSEvent] = []
        var current: [String: String] = [:]
        var inEvent = false

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" {
                inEvent = true
                current = [:]
                continue
            }
            if upper == "END:VEVENT" {
                if inEvent, let event = makeEvent(from: current) {
                    events.append(event)
                }
                inEvent = false
                current = [:]
                continue
            }
            guard inEvent else { continue }

            guard let colon = line.firstIndex(of: ":") else { continue }
            let keyPart = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let key = keyPart.split(separator: ";").first.map(String.init)?.uppercased() ?? keyPart.uppercased()
            // Keep first occurrence for UID etc.; append DESCRIPTION continuations already unfolded.
            if current[key] == nil {
                current[key] = unescapeICS(value)
            } else if key == "DESCRIPTION" {
                current[key] = (current[key] ?? "") + "\n" + unescapeICS(value)
            }
        }
        return events
    }

    private static func unescapeICS(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
    }

    private static func makeEvent(from props: [String: String]) -> ICSEvent? {
        guard let startRaw = props["DTSTART"] else { return nil }
        let endRaw = props["DTEND"] ?? props["DTSTART"]
        guard let start = parseICSDate(startRaw),
              let endParsed = parseICSDate(endRaw ?? startRaw)
        else { return nil }

        var end = endParsed
        let allDay = !startRaw.contains("T")
        // All-day DTEND is exclusive in iCal — treat last included day as end-of-day of previous calendar day.
        if allDay, end > start {
            end = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        }
        if end < start { end = start }

        let summary = props["SUMMARY"] ?? "Trip"
        let description = props["DESCRIPTION"] ?? ""
        let location = props["LOCATION"] ?? ""
        let uid = props["UID"] ?? UUID().uuidString

        return ICSEvent(
            uid: uid,
            summary: summary,
            location: location,
            description: description,
            start: start,
            end: end,
            allDay: allDay,
            tripTitleHint: extractTripTitle(from: description) ?? props["X-TRIPIT-TRIP-NAME"]
        )
    }

    private static func parseICSDate(_ raw: String) -> Date? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        // Strip TZID=…: form — value may already be separated by earlier split; handle trailing Z.
        let value: String
        if let colon = cleaned.lastIndex(of: ":"), cleaned.uppercased().contains("TZID") {
            value = String(cleaned[cleaned.index(after: colon)...])
        } else {
            value = cleaned
        }

        let formatters: [DateFormatter] = {
            let f1 = DateFormatter()
            f1.locale = Locale(identifier: "en_US_POSIX")
            f1.timeZone = TimeZone(secondsFromGMT: 0)
            f1.dateFormat = "yyyyMMdd'T'HHmmss'Z'"

            let f2 = DateFormatter()
            f2.locale = Locale(identifier: "en_US_POSIX")
            f2.timeZone = .current
            f2.dateFormat = "yyyyMMdd'T'HHmmss"

            let f3 = DateFormatter()
            f3.locale = Locale(identifier: "en_US_POSIX")
            f3.timeZone = .current
            f3.dateFormat = "yyyyMMdd"

            return [f1, f2, f3]
        }()

        for formatter in formatters {
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func extractTripTitle(from description: String) -> String? {
        let patterns = [
            #"(?i)trip(?:\s+name)?\s*[:=]\s*(.+)"#,
            #"(?i)itinerary\s+for\s*[:=]?\s*(.+)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: description) {
                let title = String(description[range])
                    .components(separatedBy: .newlines).first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if title.count >= 2 { return title }
            }
        }
        return nil
    }

    // MARK: - Clustering events → trips

    private static func clusterIntoTrips(_ events: [ICSEvent]) -> [ParsedTrip] {
        let sorted = events.sorted { $0.start < $1.start }
        // Prefer explicit trip title when TripIt embeds it; otherwise group by proximity.
        var buckets: [[ICSEvent]] = []
        var currentBucket: [ICSEvent] = []
        var currentEnd = Date.distantPast

        for event in sorted {
            if currentBucket.isEmpty {
                currentBucket = [event]
                currentEnd = event.end
                continue
            }
            let gap = event.start.timeIntervalSince(currentEnd)
            // Same continuous trip if overlapping or within 2.5 days.
            if gap <= 60 * 60 * 24 * 2.5 {
                currentBucket.append(event)
                currentEnd = max(currentEnd, event.end)
            } else {
                buckets.append(currentBucket)
                currentBucket = [event]
                currentEnd = event.end
            }
        }
        if !currentBucket.isEmpty { buckets.append(currentBucket) }

        return buckets.compactMap { buildTrip(from: $0) }
    }

    private static func buildTrip(from events: [ICSEvent]) -> ParsedTrip? {
        guard let first = events.first else { return nil }
        let start = events.map(\.start).min() ?? first.start
        let end = events.map(\.end).max() ?? first.end

        let tripName = events.compactMap(\.tripTitleHint).first
            ?? pickTripName(from: events)
            ?? String(localized: "tripit.imported_trip")

        var airline = ""
        var booking = ""
        var lodging = ""
        var notesParts: [String] = [String(localized: "tripit.imported_from")]
        var stops: [ParsedStop] = []
        var placeCandidates: [String] = []

        for event in events {
            let kind = classify(summary: event.summary, description: event.description)
            let desc = event.description

            if airline.isEmpty {
                airline = extractField(from: desc, keys: ["airline", "carrier"])
                    ?? airlineFromFlightSummary(event.summary)
                    ?? ""
            }
            if booking.isEmpty {
                booking = extractField(from: desc, keys: [
                    "confirmation", "confirmation #", "confirmation number",
                    "record locator", "booking reference", "pnr", "conf #",
                ]) ?? ""
            }
            if kind == .lodging {
                let name = event.location.isEmpty ? stripPrefix(event.summary) : event.location
                if lodging.isEmpty { lodging = name }
                placeCandidates.append(name)
            } else if !event.location.isEmpty {
                placeCandidates.append(event.location)
            }

            let activityBits = [event.summary, shortDescription(desc)].filter { !$0.isEmpty }.joined(separator: "\n")
            let stopName: String
            if !event.location.isEmpty {
                stopName = event.location
            } else {
                stopName = stripPrefix(event.summary)
            }

            // Skip pure trip-span umbrella events that duplicate the trip itself when there are real segments.
            let spanDays = Calendar.current.dateComponents([.day], from: event.start, to: event.end).day ?? 0
            let isUmbrella = event.allDay && spanDays >= 2 && events.count > 1 && kind == .other
            if !isUmbrella {
                stops.append(
                    ParsedStop(
                        locationName: stopName.isEmpty ? tripName : stopName,
                        arrivalDate: event.start,
                        departureDate: event.end,
                        activities: activityBits,
                        kind: kind
                    )
                )
            }

            if let noteLine = usefulNoteLine(from: desc) {
                notesParts.append(noteLine)
            }
        }

        // Deduplicate nearly identical stops
        var uniqueStops: [ParsedStop] = []
        for stop in stops {
            if uniqueStops.contains(where: {
                $0.locationName.caseInsensitiveCompare(stop.locationName) == .orderedSame
                    && abs($0.arrivalDate.timeIntervalSince(stop.arrivalDate)) < 60
            }) { continue }
            uniqueStops.append(stop)
        }

        let cover = placeCandidates.first { !$0.isEmpty }
            ?? uniqueStops.first?.locationName
            ?? ""

        let id = "\(tripName.lowercased())-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"

        return ParsedTrip(
            id: id,
            tripName: tripName,
            startDate: Calendar.current.startOfDay(for: start),
            endDate: Calendar.current.startOfDay(for: end),
            notes: Array(NSOrderedSet(array: notesParts)).compactMap { $0 as? String }.joined(separator: "\n"),
            airlineName: airline,
            bookingReference: booking,
            mainAccommodation: lodging,
            coverPlaceName: cover,
            stops: uniqueStops
        )
    }

    private static func pickTripName(from events: [ICSEvent]) -> String? {
        // Prefer the longest all-day umbrella summary, else a city-like location, else first summary.
        if let umbrella = events
            .filter({ $0.allDay && (Calendar.current.dateComponents([.day], from: $0.start, to: $0.end).day ?? 0) >= 1 })
            .max(by: { ($0.summary.count) < ($1.summary.count) })?
            .summary,
           !umbrella.isEmpty {
            return stripPrefix(umbrella)
        }
        if let city = events.map(\.location).first(where: { !$0.isEmpty }) {
            return city.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return events.first.map { stripPrefix($0.summary) }
    }

    private static func classify(summary: String, description: String) -> ParsedStop.StopKind {
        let blob = (summary + " " + description).lowercased()
        if blob.contains("flight") || blob.contains("airline") || (blob.contains("depart") && blob.contains("arriv")) {
            return .flight
        }
        if blob.contains("hotel") || blob.contains("lodging") || blob.contains("check-in") || blob.contains("check in")
            || blob.contains("airbnb") || blob.contains("apartment") {
            return .lodging
        }
        if blob.contains("car rental") || blob.contains("rail") || blob.contains("train") || blob.contains("transfer")
            || blob.contains("taxi") || blob.contains("bus") {
            return .transport
        }
        if blob.contains("activity") || blob.contains("tour") || blob.contains("museum") || blob.contains("restaurant") {
            return .activity
        }
        return .other
    }

    private static func stripPrefix(_ summary: String) -> String {
        let patterns = [
            #"(?i)^(flight|hotel|lodging|car(?:\s+rental)?|rail|train|activity|restaurant|transport)\s*[:\-–]\s*"#,
        ]
        var result = summary
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func airlineFromFlightSummary(_ summary: String) -> String? {
        // e.g. "Flight: BA 123 LHR → JFK" or "UA 456"
        let pattern = #"(?i)flight\s*[:\-]?\s*([A-Z]{2})\s*\d+"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: summary, range: NSRange(summary.startIndex..., in: summary)),
           match.numberOfRanges >= 2,
           let range = Range(match.range(at: 1), in: summary) {
            return String(summary[range]).uppercased()
        }
        return nil
    }

    private static func extractField(from text: String, keys: [String]) -> String? {
        for key in keys {
            let pattern = "(?i)\(NSRegularExpression.escapedPattern(for: key))\\s*[#:]?\\s*([^\\n]+)"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: text) {
                let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if value.count >= 2, value.count <= 80 { return value }
            }
        }
        return nil
    }

    private static func shortDescription(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("http") }
        return lines.prefix(3).joined(separator: " · ")
    }

    private static func usefulNoteLine(from text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("confirmation") || lower.contains("record locator") || lower.contains("confirmation #") {
            return text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && $0.count < 120 }
        }
        return nil
    }
}
