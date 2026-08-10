//
//  GeminiTripPlanner.swift
//  TheGomsons
//
//  Gemini suggestions for trip planning, with MapKit as a no-key fallback.
//

import CoreLocation
import Foundation
import MapKit

struct TripPlanSuggestion: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let detail: String
    let placeName: String
    let category: HolidayPlanCategory
    let source: Source

    enum Source: String, Sendable {
        case gemini
        case mapkit
    }

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        placeName: String,
        category: HolidayPlanCategory,
        source: Source
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.placeName = placeName
        self.category = category
        self.source = source
    }

    var mapsQuery: String {
        let place = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { return place }
        return title
    }
}

enum GeminiAPIKeyStore {
    private static let defaultsKey = "gemini.apiKey"

    static var apiKey: String? {
        get {
            if let plist = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String {
                let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != "YOUR_GEMINI_API_KEY" { return trimmed }
            }
            let stored = UserDefaults.standard.string(forKey: defaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (stored?.isEmpty == false) ? stored : nil
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: defaultsKey)
            }
        }
    }

    static var hasAPIKey: Bool { apiKey != nil }
}

enum GeminiTripPlanner {
    enum PlannerError: LocalizedError {
        case emptyDestination
        case badResponse
        case httpStatus(Int)
        case decoding

        var errorDescription: String? {
            switch self {
            case .emptyDestination: String(localized: "trip.plan.error.destination")
            case .badResponse: String(localized: "trip.plan.error.response")
            case .httpStatus(let code): String(format: String(localized: "trip.plan.error.http_fmt"), locale: .current, code)
            case .decoding: String(localized: "trip.plan.error.decode")
            }
        }
    }

    /// Prefer Gemini when a key exists; otherwise MapKit local search near trip places.
    static func suggest(
        category: HolidayPlanCategory,
        tripName: String,
        placeHints: [String],
        coordinateHints: [CLLocationCoordinate2D]
    ) async throws -> [TripPlanSuggestion] {
        if GeminiAPIKeyStore.hasAPIKey {
            do {
                return try await suggestWithGemini(
                    category: category,
                    tripName: tripName,
                    placeHints: placeHints
                )
            } catch {
                let mapkit = try await suggestWithMapKit(
                    category: category,
                    placeHints: placeHints,
                    coordinateHints: coordinateHints
                )
                if !mapkit.isEmpty { return mapkit }
                throw error
            }
        }
        return try await suggestWithMapKit(
            category: category,
            placeHints: placeHints,
            coordinateHints: coordinateHints
        )
    }

    // MARK: - Gemini

    private static func suggestWithGemini(
        category: HolidayPlanCategory,
        tripName: String,
        placeHints: [String]
    ) async throws -> [TripPlanSuggestion] {
        guard let key = GeminiAPIKeyStore.apiKey else {
            throw PlannerError.badResponse
        }
        let places = placeHints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !places.isEmpty || !tripName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlannerError.emptyDestination
        }

        let locale = Locale.current.identifier
        let destination = places.isEmpty ? tripName : places.joined(separator: "; ")
        let prompt = """
        You are a concise family trip planner. Suggest 6 concrete \(category.searchPhrase) ideas for: \(destination) (trip: \(tripName)).
        Reply ONLY with a JSON array of objects: [{"title":"…","detail":"…","placeName":"…"}]
        - title: short place or activity name
        - detail: one sentence why it fits a family trip
        - placeName: searchable place name including city
        Prefer real, well-known options. Language for title/detail: match locale \(locale).
        """

        let model = "gemini-2.0-flash"
        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        )!
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        guard let url = components.url else { throw PlannerError.badResponse }

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]],
            ],
            "generationConfig": [
                "temperature": 0.7,
                "responseMimeType": "application/json",
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw PlannerError.httpStatus(status) }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else {
            throw PlannerError.decoding
        }

        let jsonText = extractJSONArray(from: text)
        guard let jsonData = jsonText.data(using: .utf8),
              let rows = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
        else {
            throw PlannerError.decoding
        }

        return rows.compactMap { row in
            let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return nil }
            let detail = (row["detail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let place = (row["placeName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? title
            return TripPlanSuggestion(
                title: title,
                detail: detail,
                placeName: place,
                category: category,
                source: .gemini
            )
        }
    }

    private static func extractJSONArray(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") { return trimmed }
        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]"), start < end {
            return String(trimmed[start...end])
        }
        return trimmed
    }

    // MARK: - MapKit fallback

    private static func suggestWithMapKit(
        category: HolidayPlanCategory,
        placeHints: [String],
        coordinateHints: [CLLocationCoordinate2D]
    ) async throws -> [TripPlanSuggestion] {
        let places = placeHints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let queryCore = category.searchPhrase
        var results: [TripPlanSuggestion] = []
        var seen = Set<String>()

        func append(_ item: MKMapItem) {
            let title = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return }
            let key = title.lowercased()
            guard seen.insert(key).inserted else { return }
            let locality = item.address?.shortAddress?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            results.append(
                TripPlanSuggestion(
                    title: title,
                    detail: locality.isEmpty ? category.displayTitle : locality,
                    placeName: locality.isEmpty ? title : "\(title), \(locality)",
                    category: category,
                    source: .mapkit
                )
            )
        }

        if let coord = coordinateHints.first(where: { $0.latitude != 0 || $0.longitude != 0 }) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = queryCore
            request.resultTypes = [.pointOfInterest]
            request.region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
            )
            if let response = try? await MKLocalSearch(request: request).start() {
                for item in response.mapItems.prefix(8) {
                    append(item)
                }
            }
        }

        for place in places.prefix(2) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "\(queryCore) \(place)"
            request.resultTypes = [.pointOfInterest, .address]
            if let response = try? await MKLocalSearch(request: request).start() {
                for item in response.mapItems.prefix(6) {
                    append(item)
                }
            }
            if results.count >= 8 { break }
        }

        if results.isEmpty {
            throw PlannerError.emptyDestination
        }
        return Array(results.prefix(8))
    }
}
