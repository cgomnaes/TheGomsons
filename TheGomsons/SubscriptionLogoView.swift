//
//  SubscriptionLogoView.swift
//  TheGomsons
//
//  Provider logos: website domain → Google favicon service; else name keyword → domain; else bundled asset; else category icon.
//

import SwiftUI
import UIKit

// MARK: - Lookup

enum SubscriptionLogoLookup {
    /// Curated name fragments (lowercased) → brand domain for favicon lookup.
    /// Longer / more specific keys should appear first; we sort by key length when matching.
    private static let keywordToDomain: [String: String] = [
        "amazon prime": "amazon.com",
        "prime video": "amazon.com",
        "apple music": "apple.com",
        "apple tv": "tv.apple.com",
        "apple one": "apple.com",
        "icloud": "icloud.com",
        "audible": "audible.com",
        "chatgpt": "openai.com",
        "openai": "openai.com",
        "disney": "disneyplus.com",
        "disney+": "disneyplus.com",
        "hbo max": "max.com",
        "hbo": "max.com",
        "paramount": "paramountplus.com",
        "peacock": "peacocktv.com",
        "showtime": "showtime.com",
        "starz": "starz.com",
        "discovery": "discoveryplus.com",
        "hulu": "hulu.com",
        "netflix": "netflix.com",
        "youtube premium": "youtube.com",
        "youtube tv": "tv.youtube.com",
        "spotify": "spotify.com",
        "tidal": "tidal.com",
        "deezer": "deezer.com",
        "pandora": "pandora.com",
        "sirius": "siriusxm.com",
        "xm radio": "siriusxm.com",
        "dropbox": "dropbox.com",
        "google one": "one.google.com",
        "google storage": "google.com",
        "microsoft 365": "microsoft.com",
        "office 365": "microsoft.com",
        "xbox": "xbox.com",
        "playstation": "playstation.com",
        "nintendo": "nintendo.com",
        "steam": "steampowered.com",
        "adobe": "adobe.com",
        "canva": "canva.com",
        "notion": "notion.so",
        "slack": "slack.com",
        "zoom": "zoom.us",
        "github": "github.com",
        "gitlab": "gitlab.com",
        "jetbrains": "jetbrains.com",
        "nyt": "nytimes.com",
        "new york times": "nytimes.com",
        "washington post": "washingtonpost.com",
        "wsj": "wsj.com",
        "economist": "economist.com",
        "peloton": "onepeloton.com",
        "strava": "strava.com",
        "headspace": "headspace.com",
        "calm": "calm.com",
        "classpass": "classpass.com",
        "planet fitness": "planetfitness.com",
        "la fitness": "lafitness.com",
        "24 hour fitness": "24hourfitness.com",
        "verizon": "verizon.com",
        "at&t": "att.com",
        "t-mobile": "t-mobile.com",
        "comcast": "xfinity.com",
        "xfinity": "xfinity.com",
        "spectrum": "spectrum.com",
        "costco": "costco.com",
        "sam's club": "samsclub.com",
        "aaa": "aaa.com",
        "american express": "americanexpress.com",
        "geico": "geico.com",
        "state farm": "statefarm.com",
        "allstate": "allstate.com",
        "progressive": "progressive.com",
        "airbnb": "airbnb.com",
        "booking": "booking.com",
        "expedia": "expedia.com",
        "tripadvisor": "tripadvisor.com",
    ]

    private static let sortedKeywordPairs: [(String, String)] = {
        keywordToDomain.map { ($0.key, $0.value) }.sorted { $0.0.count > $1.0.count }
    }()

    /// Host only, e.g. `netflix.com` (no scheme).
    static func hostFromWebsite(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let withScheme = t.contains("://") ? t : "https://\(t)"
        guard let url = URL(string: withScheme), let host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    static func domainFromName(_ name: String) -> String? {
        let n = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        guard !n.isEmpty else { return nil }
        for (kw, domain) in sortedKeywordPairs {
            if n.contains(kw) {
                return domain
            }
        }
        return nil
    }

    /// Optional bundled image in Assets: `SubscriptionLogo_<sanitized>` — add PNGs if you want offline logos.
    static func bundledAssetName(forName name: String) -> String? {
        let key = name
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        guard key.count >= 3, key.count <= 32 else { return nil }
        let candidate = "SubscriptionLogo_\(key)"
        return UIImage(named: candidate) != nil ? candidate : nil
    }

    /// High-res favicon via Google’s public endpoint (Clearbit’s host often fails DNS in practice).
    static func faviconURL(host: String) -> URL? {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return nil }
        var c = URLComponents(string: "https://www.google.com/s2/favicons")
        c?.queryItems = [
            URLQueryItem(name: "domain", value: h),
            URLQueryItem(name: "sz", value: "128"),
        ]
        return c?.url
    }

    static func logoURL(name: String, websiteURL: String) -> URL? {
        if let host = hostFromWebsite(websiteURL), let u = faviconURL(host: host) {
            return u
        }
        if let domain = domainFromName(name), let u = faviconURL(host: domain) {
            return u
        }
        return nil
    }
}

// MARK: - Fallback (generic by category)

enum SubscriptionCategoryFallbackIcon {
    static func systemName(for category: SubscriptionCategory) -> String {
        switch category {
        case .streaming: "play.rectangle.fill"
        case .clubMembership: "person.3.fill"
        case .travelInsurance: "airplane.circle.fill"
        case .software: "app.badge.fill"
        case .newsMedia: "newspaper.fill"
        case .fitness: "figure.run"
        case .utilities: "iphone"
        case .other: "creditcard.fill"
        }
    }
}

// MARK: - View

struct SubscriptionLogoView: View {
    var name: String
    var websiteURL: String
    var category: SubscriptionCategory
    var size: CGFloat = 36

    init(subscription: Subscription, size: CGFloat = 36) {
        self.name = subscription.name
        self.websiteURL = subscription.websiteURL
        self.category = subscription.category
        self.size = size
    }

    init(name: String, websiteURL: String, category: SubscriptionCategory, size: CGFloat = 36) {
        self.name = name
        self.websiteURL = websiteURL
        self.category = category
        self.size = size
    }

    private var bundledName: String? {
        SubscriptionLogoLookup.bundledAssetName(forName: name)
    }

    private var remoteURL: URL? {
        SubscriptionLogoLookup.logoURL(name: name, websiteURL: websiteURL)
    }

    var body: some View {
        ZStack {
            // Generic category icon is always the floor; custom art overlays only when it loads.
            fallback
            if let asset = bundledName {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let url = remoteURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure, .empty:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
    }

    private var fallback: some View {
        Image(systemName: SubscriptionCategoryFallbackIcon.systemName(for: category))
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(SimpsonsTheme.purple)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.tertiarySystemFill))
    }
}
