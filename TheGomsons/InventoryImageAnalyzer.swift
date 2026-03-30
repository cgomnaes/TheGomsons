//
//  InventoryImageAnalyzer.swift
//  TheGomsons
//

import Foundation
import UIKit
import Vision

/// On-device photo analysis: Vision classification for item type + OCR for prices.
enum InventoryImageAnalyzer {

    struct Suggestion: Sendable {
        var suggestedName: String
        var category: InventoryCategory
        var estimatedValue: Double
        var currentRetailPrice: Double
        /// Short explanation for the UI (e.g. top Vision labels).
        var analysisSummary: String
    }

    /// Runs Vision off the main actor; returns best-effort suggestions (zeros when unknown).
    static func analyze(image: UIImage) async -> Suggestion {
        let cgImageOpt: CGImage? = await MainActor.run {
            if let cg = image.cgImage { return cg }
            let renderer = UIGraphicsImageRenderer(size: image.size)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }.cgImage
        }

        return await Task.detached(priority: .userInitiated) {
            guard let cgImage = cgImageOpt else {
                return Suggestion(
                    suggestedName: "",
                    category: .other,
                    estimatedValue: 0,
                    currentRetailPrice: 0,
                    analysisSummary: "Could not read the image."
                )
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            let classifyRequest = VNClassifyImageRequest()
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true

            do {
                try handler.perform([classifyRequest, textRequest])
            } catch {
                return Suggestion(
                    suggestedName: "",
                    category: .other,
                    estimatedValue: 0,
                    currentRetailPrice: 0,
                    analysisSummary: "Analysis failed: \(error.localizedDescription)"
                )
            }

            let classifications = classifyRequest.results ?? []
            let topLabels = classifications
                .filter { $0.confidence > 0.05 }
                .prefix(8)
                .map { ($0.identifier, $0.confidence) }

            let identifiers = topLabels.map(\.0)
            let category = mapCategory(identifiers: identifiers)

            let name: String
            if let best = topLabels.first {
                name = humanizedIdentifier(best.0)
            } else {
                name = ""
            }

            let textObservations = textRequest.results ?? []
            let allStrings = textObservations.compactMap { $0.topCandidates(1).first?.string }
            let mergedText = allStrings.joined(separator: "\n")
            let moneyValues = extractMoneyValues(from: mergedText)

            let (retail, value) = splitRetailAndEstimated(from: moneyValues)

            let summary: String
            if topLabels.isEmpty, allStrings.isEmpty {
                summary = "No clear item or price text found. Try a closer, well-lit photo."
            } else {
                let labelPart = topLabels.prefix(3).map { humanizedIdentifier($0.0) }.joined(separator: " · ")
                let pricePart = moneyValues.isEmpty ? "" : " · Found \(moneyValues.count) price-like value(s) in text."
                summary = labelPart + pricePart
            }

            return Suggestion(
                suggestedName: name,
                category: category,
                estimatedValue: value,
                currentRetailPrice: retail,
                analysisSummary: summary
            )
        }.value
    }

    // MARK: - Category mapping

    private nonisolated static func mapCategory(identifiers: [String]) -> InventoryCategory {
        let blob = identifiers.joined(separator: " ").lowercased()
        guard !blob.isEmpty else { return .other }

        if blob.contains("ski") || blob.contains("snowboard") || blob.contains("binding") {
            if blob.contains("cross") || blob.contains("nordic") || blob.contains("country") { return .crossCountrySkis }
            if blob.contains("telemark") { return .telemarkSkis }
            if blob.contains("alpine") || blob.contains("downhill") || blob.contains("ski") { return .downhillSkis }
            return .downhillSkis
        }
        if blob.contains("tennis") || blob.contains("racket") || blob.contains("racquet") { return .tennis }
        if blob.contains("golf") || (blob.contains("club") && blob.contains("golf")) || blob.contains("putter") || blob.contains("driver") {
            return .golf
        }
        if blob.contains("hammer") || blob.contains("drill") || blob.contains("saw") || blob.contains("wrench")
            || blob.contains("screwdriver") || blob.contains("pliers") || blob.contains("tool")
            || blob.contains("ladder") || blob.contains("socket") || blob.contains("vise") {
            return .diyTools
        }
        return .other
    }

    private nonisolated static func humanizedIdentifier(_ id: String) -> String {
        id
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map(\.capitalized)
            .joined(separator: " ")
    }

    // MARK: - Money from OCR

    private nonisolated static func extractMoneyValues(from text: String) -> [Double] {
        guard !text.isEmpty else { return [] }

        var values: [Double] = []
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        let withSymbol = #"(?:\$|€|£)\s*(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{2}))?\b"#
        if let regex = try? NSRegularExpression(pattern: withSymbol, options: []) {
            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 2 else { return }
                let intPart = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
                let frac: String
                if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound {
                    frac = "." + ns.substring(with: match.range(at: 2))
                } else {
                    frac = ""
                }
                if let v = Double(intPart + frac), v >= 0.5, v < 1_000_000 {
                    values.append(v)
                }
            }
        }

        let bareCents = #"\b(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})\b"#
        if let regex2 = try? NSRegularExpression(pattern: bareCents, options: []) {
            regex2.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 3 else { return }
                let intPart = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
                let frac = "." + ns.substring(with: match.range(at: 2))
                if let v = Double(intPart + frac), v >= 0.5, v < 1_000_000 {
                    values.append(v)
                }
            }
        }

        return Array(Set(values.map { ($0 * 100).rounded() / 100 })).sorted()
    }

    /// If two+ distinct amounts: treat smaller as shelf/list price, larger as replacement/insured-style value. One amount fills both.
    private nonisolated static func splitRetailAndEstimated(from values: [Double]) -> (retail: Double, estimated: Double) {
        guard !values.isEmpty else { return (0, 0) }
        if values.count == 1 {
            let v = values[0]
            return (v, v)
        }
        let sorted = values.sorted()
        return (sorted.first!, sorted.last!)
    }
}
