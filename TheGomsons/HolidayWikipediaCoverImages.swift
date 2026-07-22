//
//  HolidayWikipediaCoverImages.swift
//  TheGomsons
//
//  English Wikipedia / Wikimedia Commons images for trip covers (real photos, not map snapshots).
//

import Foundation

enum HolidayWikipediaCoverImages {
    private static let apiEndpoint = URL(string: "https://en.wikipedia.org/w/api.php")!

    private static var apiUserAgent: String {
        let id = Bundle.main.bundleIdentifier ?? "TheGomsons"
        return "TheGomsonsHolidayCover/1.0 (iOS; \(id))"
    }

    /// Image candidates from Wikipedia search. Empty if network fails or no illustrated articles—caller may fall back to satellite.
    static func fetchCoverChoices(for place: HolidayPlaceCandidate, limit: Int = 6) async -> [(pageTitle: String, label: String, thumbnailURL: URL)] {
        do {
            return try await fetchCoverChoicesImpl(for: place, limit: limit)
        } catch {
            return []
        }
    }

    private static func fetchCoverChoicesImpl(for place: HolidayPlaceCandidate, limit: Int) async throws -> [(pageTitle: String, label: String, thumbnailURL: URL)] {
        let search = wikipediaSearchQuery(from: place)
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HolidayGeocodingError.emptyQuery }

        var components = URLComponents(url: apiEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: trimmed),
            URLQueryItem(name: "gsrlimit", value: "\(min(max(limit, 1), 20))"),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "640"),
            URLQueryItem(name: "gsrnamespace", value: "0"),
        ]
        guard let url = components.url else { throw HolidayGeocodingError.noResults }

        var request = URLRequest(url: url)
        request.setValue(apiUserAgent, forHTTPHeaderField: "Api-User-Agent")
        request.setValue(apiUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw HolidayGeocodingError.noResults
        }

        return parsePagesJSON(data, limit: limit)
    }

    private static func parsePagesJSON(_ data: Data, limit: Int) -> [(pageTitle: String, label: String, thumbnailURL: URL)] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = obj["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any]
        else {
            return []
        }

        var out: [(String, String, URL)] = []
        for (_, pageVal) in pages {
            guard let page = pageVal as? [String: Any] else { continue }
            if page["missing"] != nil { continue }
            guard let title = page["title"] as? String,
                  let thumb = page["thumbnail"] as? [String: Any],
                  let source = thumb["source"] as? String,
                  let tURL = URL(string: source)
            else {
                continue
            }
            let label = title.replacingOccurrences(of: "_", with: " ")
            out.append((title, label, tURL))
            if out.count >= limit { break }
        }
        return out
    }

    private static func wikipediaSearchQuery(from place: HolidayPlaceCandidate) -> String {
        let t = place.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = place.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return t }
        return "\(t) \(s)"
    }

    /// Best available raster for saving as cover (Commons file). Falls back if `original` is missing.
    static func fetchImageDataForCover(pageTitle: String, thumbnailURL: URL) async throws -> Data {
        if let data = try? await fetchOriginalImageData(pageTitle: pageTitle) {
            return data
        }
        return try await downloadImageData(from: thumbnailURL)
    }

    private static func fetchOriginalImageData(pageTitle: String) async throws -> Data {
        var components = URLComponents(url: apiEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "titles", value: pageTitle),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "piprop", value: "original"),
        ]
        guard let url = components.url else { throw HolidayGeocodingError.noResults }

        var request = URLRequest(url: url)
        request.setValue(apiUserAgent, forHTTPHeaderField: "Api-User-Agent")
        request.setValue(apiUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw HolidayGeocodingError.noResults
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = obj["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any],
              let firstPage = pages.values.first as? [String: Any],
              let original = firstPage["original"] as? [String: Any],
              let source = original["source"] as? String,
              let imageURL = URL(string: source)
        else {
            throw HolidayGeocodingError.noResults
        }

        // Skip SVG originals (UIImage won't decode); caller will use thumbnail.
        if source.lowercased().hasSuffix(".svg") {
            throw HolidayGeocodingError.noResults
        }

        return try await downloadImageData(from: imageURL)
    }

    static func downloadImageData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(apiUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw HolidayGeocodingError.noResults
        }
        return data
    }
}
