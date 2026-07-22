//
//  InventoryImageAnalyzer.swift
//  TheGomsons
//

import Foundation
import UIKit
import Vision

/// On-device photo analysis: Vision classification for item type + OCR for prices.
enum InventoryImageAnalyzer {

    /// One ranked interpretation of the photo (Vision label + mapped stash category).
    struct RankedOption: Sendable, Identifiable {
        var id: String { identifier }
        /// Raw Vision taxonomy string (e.g. `laptop_computer`).
        var identifier: String
        /// Display name for pickers.
        var title: String
        var confidence: Float
        /// Score after boosting valuables and demoting cables/adapters etc.
        var adjustedScore: Float
        var category: InventoryCategory
    }

    struct Suggestion: Sendable {
        var suggestedName: String
        var category: InventoryCategory
        var estimatedValue: Double
        var currentRetailPrice: Double
        /// Short explanation for the UI (e.g. top Vision labels).
        var analysisSummary: String
        /// Best-first list so the user can pick the main subject when Vision returns several things (e.g. laptop + cable).
        var rankedOptions: [RankedOption]
        /// OCR-derived serial / model hints for the notes field.
        var suggestedNotes: String
    }

    /// Runs Vision off the main actor; returns best-effort suggestions (zeros when unknown).
    static func analyze(image: UIImage) async -> Suggestion {
        let cgImageOpt: CGImage? = await MainActor.run {
            normalizedCGImage(from: image)
        }

        return await Task.detached(priority: .userInitiated) {
            guard let cgImage = cgImageOpt else {
                return emptySuggestion(summary: "Could not read the image.")
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            let classifyRequest = VNClassifyImageRequest()
            let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            textRequest.regionOfInterest = centerNormalizedRect(fraction: 0.78)

            do {
                try handler.perform([classifyRequest, saliencyRequest, textRequest])
            } catch {
                return emptySuggestion(summary: "Analysis failed: \(error.localizedDescription)")
            }

            let fullLabels = extractLabels(from: classifyRequest.results ?? [])
                .map { ($0.0, $0.1 * 0.42) }

            let centerLabels = classifyCenterRegion(cgImage: cgImage)
            let salientLabels = classifySalientRegion(
                cgImage: cgImage,
                saliencyObservation: saliencyRequest.results?.first
            )
            let mergedLabels = mergeLabelSets(
                center: centerLabels,
                salient: salientLabels,
                full: fullLabels
            )

            let textObservations = textRequest.results ?? []
            let allStrings = textObservations.compactMap { $0.topCandidates(1).first?.string }
            let mergedText = allStrings.joined(separator: "\n")
            let ocrHints = extractOCRHints(from: mergedText)

            let rankedOptions = rankLabelsForMainSubject(mergedLabels, ocrHints: ocrHints)
            let best = rankedOptions.first

            let identifiers = mergedLabels.map(\.0)
            let category = best.map { mapCategory(primaryIdentifier: $0.identifier, allIdentifiers: identifiers, ocrHints: ocrHints) }
                ?? mapCategory(identifiers: identifiers, ocrHints: ocrHints)

            let name = buildSuggestedName(
                bestOption: best,
                ocrHints: ocrHints,
                identifiers: identifiers
            )

            let moneyValues = extractMoneyValues(from: mergedText)
            let (retail, value) = splitRetailAndEstimated(from: moneyValues)

            let summary = buildAnalysisSummary(
                rankedOptions: rankedOptions,
                ocrHints: ocrHints,
                moneyCount: moneyValues.count,
                hadText: !allStrings.isEmpty
            )

            return Suggestion(
                suggestedName: name,
                category: category,
                estimatedValue: value,
                currentRetailPrice: retail,
                analysisSummary: summary,
                rankedOptions: rankedOptions,
                suggestedNotes: ocrHints.notesSnippet
            )
        }.value
    }

    /// Crops to the center of the frame — used when capturing so analysis matches what the user framed.
    static func prepareCapturedImage(_ image: UIImage) -> UIImage {
        guard let cg = normalizedCGImage(from: image),
              let cropped = cropCGImage(cg, normalizedRect: centerNormalizedRect(fraction: 0.72), padding: 0)
        else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    /// Normalized square in the middle of the frame (Vision coordinates: origin bottom-left).
    nonisolated static func centerNormalizedRect(fraction: CGFloat) -> CGRect {
        let size = min(max(fraction, 0.45), 0.92)
        let origin = (1 - size) / 2
        return CGRect(x: origin, y: origin, width: size, height: size)
    }

    private static func normalizedCGImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }

    // MARK: - Vision label extraction

    private nonisolated static func extractLabels(from observations: [VNClassificationObservation]) -> [(String, Float)] {
        observations
            .filter { $0.confidence > 0.015 }
            .prefix(32)
            .map { ($0.identifier, $0.confidence) }
    }

    /// Classify only the center crop — primary signal for “what’s in the middle of the photo”.
    private nonisolated static func classifyCenterRegion(cgImage: CGImage) -> [(String, Float)] {
        guard let cropped = cropCGImage(cgImage, normalizedRect: centerNormalizedRect(fraction: 0.68), padding: 0)
        else { return [] }

        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        let request = VNClassifyImageRequest()
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return extractLabels(from: request.results ?? [])
            .map { ($0.0, $0.1 * 2.15) }
    }

    /// Re-classify the most salient crop when it overlaps the center framing zone.
    private nonisolated static func classifySalientRegion(
        cgImage: CGImage,
        saliencyObservation: VNSaliencyImageObservation?
    ) -> [(String, Float)] {
        guard let saliencyObservation,
              let salientObject = saliencyObservation.salientObjects?.max(by: { $0.confidence < $1.confidence }),
              salientObject.confidence > 0.2,
              salientObjectOverlapsCenter(salientObject.boundingBox),
              let cropped = cropCGImage(cgImage, normalizedRect: salientObject.boundingBox, padding: 0.08)
        else { return [] }

        let cropHandler = VNImageRequestHandler(cgImage: cropped, options: [:])
        let cropClassify = VNClassifyImageRequest()
        do {
            try cropHandler.perform([cropClassify])
        } catch {
            return []
        }

        return extractLabels(from: cropClassify.results ?? [])
            .map { ($0.0, $0.1 * 1.35) }
    }

    private nonisolated static func salientObjectOverlapsCenter(_ box: CGRect) -> Bool {
        let centerZone = centerNormalizedRect(fraction: 0.62)
        if box.contains(CGPoint(x: 0.5, y: 0.5)) { return true }
        let intersection = box.intersection(centerZone)
        guard intersection.width > 0, intersection.height > 0 else { return false }
        let overlapArea = intersection.width * intersection.height
        let boxArea = max(box.width * box.height, 0.001)
        return overlapArea / boxArea >= 0.28
    }

    private nonisolated static func mergeLabelSets(
        center: [(String, Float)],
        salient: [(String, Float)],
        full: [(String, Float)]
    ) -> [(String, Float)] {
        var merged: [String: Float] = [:]
        for (id, conf) in full {
            merged[id] = max(merged[id] ?? 0, conf)
        }
        for (id, conf) in salient {
            let synergy: Float = merged[id] != nil ? 1.35 : 1.0
            merged[id] = max(merged[id] ?? 0, conf * synergy)
        }
        for (id, conf) in center {
            let synergy: Float = merged[id] != nil ? 1.55 : 1.0
            merged[id] = max(merged[id] ?? 0, conf * synergy)
        }
        return merged
            .map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
            .prefix(28)
            .map { ($0.0, $0.1) }
    }

    private nonisolated static func cropCGImage(
        _ cgImage: CGImage,
        normalizedRect: CGRect,
        padding: CGFloat
    ) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        var rect = normalizedRect
        rect = rect.insetBy(dx: -padding * rect.width, dy: -padding * rect.height)
        rect.origin.x = max(0, rect.origin.x)
        rect.origin.y = max(0, rect.origin.y)
        rect.size.width = min(1 - rect.origin.x, rect.size.width)
        rect.size.height = min(1 - rect.origin.y, rect.size.height)

        let cropRect = CGRect(
            x: rect.origin.x * width,
            y: (1 - rect.origin.y - rect.size.height) * height,
            width: rect.size.width * width,
            height: rect.size.height * height
        ).integral

        guard cropRect.width > 32, cropRect.height > 32 else { return nil }
        return cgImage.cropping(to: cropRect)
    }

    // MARK: - OCR hints (brand, model, serial)

    private struct OCRHints: Sendable {
        var brand: String?
        var productLine: String?
        var serialOrModel: String?
        var notesSnippet: String
    }

    private nonisolated static let brandKeywords: [(term: String, display: String, category: InventoryCategory)] = [
        ("macbook", "Apple", .computers),
        ("imac", "Apple", .computers),
        ("ipad", "Apple", .phoneTablet),
        ("iphone", "Apple", .phoneTablet),
        ("apple watch", "Apple", .watch),
        ("apple", "Apple", .computers),
        ("rolex", "Rolex", .watch),
        ("omega", "Omega", .watch),
        ("tag heuer", "TAG Heuer", .watch),
        ("seiko", "Seiko", .watch),
        ("fender", "Fender", .musicalInstrument),
        ("gibson", "Gibson", .musicalInstrument),
        ("yamaha", "Yamaha", .musicalInstrument),
        ("steinway", "Steinway", .musicalInstrument),
        ("dell", "Dell", .computers),
        ("lenovo", "Lenovo", .computers),
        ("thinkpad", "Lenovo", .computers),
        ("hp ", "HP", .computers),
        ("hewlett", "HP", .computers),
        ("asus", "ASUS", .computers),
        ("acer", "Acer", .computers),
        ("microsoft surface", "Microsoft", .phoneTablet),
        ("surface pro", "Microsoft", .phoneTablet),
        ("pixel", "Google", .phoneTablet),
        ("galaxy", "Samsung", .phoneTablet),
        ("samsung", "Samsung", .tvHomeTheater),
        ("lg ", "LG", .tvHomeTheater),
        ("sony", "Sony", .tvHomeTheater),
        ("playstation", "Sony", .tvHomeTheater),
        ("xbox", "Microsoft", .tvHomeTheater),
        ("nintendo", "Nintendo", .tvHomeTheater),
        ("weber", "Weber", .outdoorCooking),
        ("traeger", "Traeger", .outdoorCooking),
        ("big green egg", "Big Green Egg", .outdoorCooking),
        ("ryobi", "Ryobi", .diyTools),
        ("dewalt", "DeWalt", .diyTools),
        ("milwaukee", "Milwaukee", .diyTools),
        ("makita", "Makita", .diyTools),
        ("bosch", "Bosch", .diyTools),
        ("stihl", "Stihl", .diyTools),
        ("husqvarna", "Husqvarna", .diyTools),
        ("burton", "Burton", .downhillSkis),
        ("rossignol", "Rossignol", .downhillSkis),
        ("salomon", "Salomon", .downhillSkis),
        ("atomic", "Atomic", .downhillSkis),
        ("head ", "Head", .downhillSkis),
        ("k2 ", "K2", .downhillSkis),
        ("fischer", "Fischer", .crossCountrySkis),
        ("peloton", "Peloton", .other),
        ("garmin", "Garmin", .other),
        ("canon", "Canon", .computers),
        ("nikon", "Nikon", .computers),
        ("gopro", "GoPro", .computers),
        ("dji", "DJI", .computers),
        ("volvo", "Volvo", .car),
        ("toyota", "Toyota", .car),
        ("tesla", "Tesla", .car),
        ("bmw", "BMW", .car),
        ("mercedes", "Mercedes-Benz", .car),
        ("audi", "Audi", .car),
        ("ford", "Ford", .car),
        ("honda", "Honda", .car),
        ("hyundai", "Hyundai", .car),
        ("kia", "Kia", .car),
        ("nissan", "Nissan", .car),
        ("mazda", "Mazda", .car),
        ("subaru", "Subaru", .car),
        ("volkswagen", "Volkswagen", .car),
        ("trek", "Trek", .bicycle),
        ("specialized", "Specialized", .bicycle),
        ("giant", "Giant", .bicycle),
        ("cannondale", "Cannondale", .bicycle),
        ("dyson", "Dyson", .household),
        ("kitchenaid", "KitchenAid", .household),
        ("miele", "Miele", .household),
        ("philips", "Philips", .household),
        ("ikea", "IKEA", .household),
    ]

    private nonisolated static func extractOCRHints(from text: String) -> OCRHints {
        guard !text.isEmpty else {
            return OCRHints(brand: nil, productLine: nil, serialOrModel: nil, notesSnippet: "")
        }

        let lower = text.lowercased()
        var brand: String?
        var brandCategory: InventoryCategory?
        for entry in brandKeywords {
            if lower.contains(entry.term) {
                brand = entry.display
                brandCategory = entry.category
                break
            }
        }

        let productLine = extractProductLine(from: text)
        let serial = extractSerialOrModel(from: text)

        var notesParts: [String] = []
        if let serial, !serial.isEmpty {
            notesParts.append("Serial/model: \(serial)")
        }
        if let productLine, productLine != brand {
            notesParts.append("Label text: \(productLine)")
        }
        if brandCategory != nil, brand != nil {
            // category hint consumed downstream; nothing to add to notes
        }

        return OCRHints(
            brand: brand,
            productLine: productLine,
            serialOrModel: serial,
            notesSnippet: notesParts.joined(separator: "\n")
        )
    }

    private nonisolated static func extractProductLine(from text: String) -> String? {
        let patterns = [
            #"(?i)\b(macbook\s+(?:pro|air)(?:\s+\d{2})?(?:\s*(?:inch|in))?|\d{4}\s*macbook\s+(?:pro|air)?)"#,
            #"(?i)\b(iphone\s*(?:\d{1,2})?\s*(?:pro|max|plus|mini)?)"#,
            #"(?i)\b(ipad\s*(?:pro|air|mini)?(?:\s+\d{1,2})?)"#,
            #"(?i)\b(playstation\s*\d|ps\s*\d|xbox\s*(?:series\s*)?[sx\d]+|nintendo\s*switch)"#,
            #"(?i)\b(galaxy\s*(?:s|z|note|tab)\s*\d+)"#,
            #"(?i)\b(volvo\s*[a-z0-9\- ]+|tesla\s*model\s*[0-9sx]|bmw\s*[0-9]{3}[a-z]?|mercedes[\-\s]?benz\s*[a-z0-9]+)"#,
            #"(?i)\b(model\s*(?:no\.?|#|number)?\s*[:\-]?\s*[A-Z0-9][A-Z0-9\-\/]{3,})"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
                let found = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if found.count >= 3 { return found }
            }
        }
        return nil
    }

    private nonisolated static func extractSerialOrModel(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if lower.contains("serial") || lower.contains("s/n") || lower.contains("model") {
                let cleaned = trimmed
                    .replacingOccurrences(of: #"(?i)(serial|s/n|model\s*(?:no\.?|#|number)?)\s*[:\-]?\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.count >= 4, cleaned.count <= 40 {
                    return cleaned
                }
            }
        }

        let alnumPattern = #"\b[A-Z0-9]{2,4}[- ]?[A-Z0-9]{4,}[- ]?[A-Z0-9]{2,}\b"#
        if let regex = try? NSRegularExpression(pattern: alnumPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            return String(text[range])
        }
        return nil
    }

    private nonisolated static func buildSuggestedName(
        bestOption: RankedOption?,
        ocrHints: OCRHints,
        identifiers: [String]
    ) -> String {
        if let productLine = ocrHints.productLine, !productLine.isEmpty {
            return productLine.capitalizedProductPhrase
        }

        let visionTitle = bestOption?.title ?? ""
        if let brand = ocrHints.brand {
            if visionTitle.isEmpty {
                return brand
            }
            let visionLower = visionTitle.lowercased()
            if visionLower.contains(brand.lowercased()) {
                return visionTitle
            }
            // "Apple" + "Laptop" → "Apple Laptop"
            if isGenericDescriptor(visionTitle) {
                return "\(brand) \(visionTitle)"
            }
            return "\(brand) \(visionTitle)"
        }

        return visionTitle
    }

    private nonisolated static func isGenericDescriptor(_ title: String) -> Bool {
        let generic = ["laptop", "computer", "tablet", "phone", "smartphone", "television", "tv", "monitor",
                       "camera", "drill", "grill", "bicycle", "bike", "skis", "snowboard", "tools"]
        let lower = title.lowercased()
        return generic.contains { lower == $0 || lower.hasSuffix(" \($0)") }
    }

    // MARK: - Rank labels (main subject vs. cable / small accessories)

    /// Terms that are usually background clutter when a laptop, bike, etc. is in frame.
    private nonisolated static let accessoryNoiseTerms: [String] = [
        "cable", "cord", "wire", "wires", "wiring", "adapter", "charg", "charger", "plug", "socket", "connector",
        "usb", "hdmi", "thunderbolt", "dongle", "strap", "tie", "rope", "chain", "duct", "tape", "rubber_band",
        "paper_clip", "clip", "staple", "eraser", "pencil", "pen", "marker",
    ]

    /// Scene / background labels that rarely describe the insured item.
    private nonisolated static let sceneNoiseTerms: [String] = [
        "floor", "wall", "ceiling", "carpet", "table", "desk", "shelf", "drawer", "counter",
        "person", "hand", "finger", "face", "human", "selfie", "packaging", "cardboard",
        "paper", "document", "receipt", "sticker", "background", "indoor", "outdoor",
        "room", "kitchen", "garage", "bedroom", "living", "furniture", "wood", "metal", "plastic",
        "textile", "fabric", "glass", "ceramic",
    ]

    /// Factory, commercial, and oversized things a home inventory rarely tracks.
    private nonisolated static let industrialNoiseTerms: [String] = [
        "forklift", "crane", "bulldozer", "excavator", "backhoe", "grader", "loader",
        "factory", "warehouse", "industrial", "machinery", "assembly", "conveyor", "refinery",
        "pallet", "shipping_container", "container_ship", "freighter", "cargo_ship",
        "locomotive", "train", "aircraft", "airplane", "helicopter", "jetliner",
        "semi_trailer", "tractor_trailer", "dump_truck", "cement_mixer", "tanker",
        "skyscraper", "building", "stadium", "hangar", "bridge", "construction",
        "oil_rig", "mining", "smokestack", "turbine", "power_plant",
    ]

    private nonisolated static func isIndustrialNoise(_ identifier: String) -> Bool {
        let s = identifier.lowercased()
        if industrialNoiseTerms.contains(where: { s.contains($0) }) { return true }
        // Commercial trucks / buses — not personal cars.
        if (s.contains("truck") || s.contains("bus") || s.contains("lorry")) &&
            !s.contains("pickup") && !s.contains("suv") && !s.contains("automobile") {
            return true
        }
        return false
    }

    private nonisolated static func isAccessoryNoise(_ identifier: String) -> Bool {
        let s = identifier.lowercased()
        return accessoryNoiseTerms.contains { s.contains($0) }
    }

    private nonisolated static func isSceneNoise(_ identifier: String) -> Bool {
        let s = identifier.lowercased()
        return sceneNoiseTerms.contains { s.contains($0) }
    }

    /// Boost identifiers that match typical home & personal property (not factory gear).
    private nonisolated static func mainSubjectWeight(_ identifier: String) -> Float {
        let s = identifier.lowercased()
        if isIndustrialNoise(s) { return 0.08 }

        if s.contains("sedan") || s.contains("suv") || s.contains("automobile") || s.contains("passenger_car")
            || s.contains("sports_car") || s.contains("convertible") || s.contains("hatchback") || s.contains("minivan")
            || (s.contains("car") && !s.contains("rail") && !s.contains("motor") && !s.contains("subway"))
        {
            return 3.5
        }
        if s.contains("pickup") || s.contains("pickup_truck") { return 2.8 }
        if s.contains("bicycle") || s.contains("mountain_bike") || s.contains("road_bike") || s.contains("bike") {
            return 3.2
        }
        if s.contains("macbook") || s.contains("imac")
            || s.contains("laptop")
        {
            return 3.2
        }
        if s.contains("iphone") || s.contains("ipad") || s.contains("tablet") || s.contains("smartphone") || s.contains("mobile_phone") {
            return 3.3
        }
        if s.contains("wristwatch") || s.contains("pocket_watch") || s.contains("smartwatch")
            || (s.contains("watch") && (s.contains("digital") || s.contains("smart") || s.contains("apple") || s.contains("wrist")))
        {
            return 3.1
        }
        if s.contains("guitar") || s.contains("piano") || s.contains("violin") || s.contains("saxophone")
            || s.contains("trumpet") || s.contains("flute") || s.contains("cello") || s.contains("ukulele")
            || s.contains("drum") || s.contains("musical")
        {
            return 2.8
        }
        if s.contains("computer") && !s.contains("television") { return 2.4 }
        if s.contains("television") || s.contains("oled") || s.contains("qled") || (s.contains("tv") && s.contains("screen")) {
            return 2.6
        }
        if s.contains("game") || s.contains("console") || s.contains("playstation") || s.contains("xbox") {
            return 2.3
        }
        if s.contains("refrigerator") || s.contains("microwave") || s.contains("oven") || s.contains("washer")
            || s.contains("dryer") || s.contains("dishwasher") || s.contains("vacuum") || s.contains("coffee")
            || s.contains("blender") || s.contains("toaster") || s.contains("kettle") || s.contains("sofa")
            || s.contains("couch") || s.contains("chair") || s.contains("lamp") || s.contains("mattress")
            || s.contains("appliance") || s.contains("cookware") || s.contains("pot") || s.contains("pan")
        {
            return 2.5
        }
        if s.contains("ski") || s.contains("snowboard") || s.contains("binding") { return 2.4 }
        if s.contains("tennis") || s.contains("golf") { return 1.9 }
        if s.contains("grill") || s.contains("barbecue") || s.contains("smoker") { return 2.2 }
        if s.contains("drill") || s.contains("saw") || s.contains("mower") || s.contains("chainsaw") { return 2.0 }
        if s.contains("boat") || s.contains("kayak") || s.contains("canoe") { return 2.2 }
        if s.contains("trailer") || s.contains("caravan") { return 2.0 }
        if s.contains("monitor") || s.contains("keyboard") || (s.contains("camera") && !s.contains("security")) {
            return 1.7
        }
        if s.contains("headphone") || s.contains("earphone") || s.contains("airpods") || s.contains("speaker") {
            return 1.8
        }
        return 1.0
    }

    private nonisolated static func rankLabelsForMainSubject(
        _ raw: [(String, Float)],
        ocrHints: OCRHints
    ) -> [RankedOption] {
        guard !raw.isEmpty else { return [] }
        let hasMainCandidate = raw.contains { !isAccessoryNoise($0.0) && !isSceneNoise($0.0) && !isIndustrialNoise($0.0) }
        var scored: [(String, Float, Float)] = []
        for (id, conf) in raw {
            if isIndustrialNoise(id) { continue }
            var w = mainSubjectWeight(id)
            if hasMainCandidate && isAccessoryNoise(id) {
                w *= 0.04
            } else if isAccessoryNoise(id) {
                w *= 0.25
            }
            if hasMainCandidate && isSceneNoise(id) {
                w *= 0.1
            } else if isSceneNoise(id) {
                w *= 0.35
            }
            if let brand = ocrHints.brand?.lowercased(), id.lowercased().contains(brand) {
                w *= 1.25
            }
            let adjusted = conf * w
            scored.append((id, conf, adjusted))
        }
        scored.sort { $0.2 > $1.2 }
        let deduped: [(String, Float, Float)] = Dictionary(grouping: scored, by: { $0.0 })
            .values
            .compactMap { $0.max(by: { $0.2 < $1.2 }) }
            .sorted { $0.2 > $1.2 }

        return deduped.prefix(8).map { id, conf, adj in
            let cat = mapCategory(primaryIdentifier: id, allIdentifiers: raw.map(\.0), ocrHints: ocrHints)
            return RankedOption(
                identifier: id,
                title: displayTitle(for: id),
                confidence: conf,
                adjustedScore: adj,
                category: cat
            )
        }
    }

    // MARK: - Category mapping (weighted scoring)

    private struct CategoryRule {
        let category: InventoryCategory
        let terms: [String]
        let weight: Float
        let exclude: [String]
    }

    private nonisolated static let categoryRules: [CategoryRule] = [
        CategoryRule(category: .car, terms: [
            "sedan", "suv", "automobile", "passenger_car", "sports_car", "convertible", "hatchback",
            "minivan", "pickup", "pickup_truck", "wheel", "license_plate",
        ], weight: 1.0, exclude: ["forklift", "truck", "bus", "train", "motorcycle"]),
        CategoryRule(category: .bicycle, terms: [
            "bicycle", "mountain_bike", "road_bike", "bike", "cycling", "helmet",
        ], weight: 1.0, exclude: ["motor", "motorcycle", "motorbike"]),
        CategoryRule(category: .household, terms: [
            "refrigerator", "microwave", "oven", "stove", "washer", "dryer", "dishwasher",
            "vacuum", "coffee", "blender", "toaster", "kettle", "iron", "mixer",
            "sofa", "couch", "chair", "table", "lamp", "bed", "mattress", "dresser",
            "cabinet", "bookshelf", "mirror", "clock", "vase", "cookware", "pot", "pan",
            "knife", "plate", "mug", "glass", "appliance", "kitchenware", "utensil",
            "rug", "curtain", "pillow", "blanket", "fan", "heater", "humidifier",
        ], weight: 1.0, exclude: []),
        CategoryRule(category: .computers, terms: [
            "macbook", "imac", "laptop", "computer", "desktop", "monitor", "keyboard", "webcam", "printer", "scanner",
            "camera", "dslr", "mirrorless", "gopro", "drone", "headphone", "earphone", "airpods",
        ], weight: 1.0, exclude: ["television", "security_camera", "iphone", "ipad", "smartphone", "mobile_phone", "tablet"]),
        CategoryRule(category: .phoneTablet, terms: [
            "iphone", "ipad", "smartphone", "mobile_phone", "tablet", "pixel", "galaxy",
        ], weight: 1.15, exclude: ["macbook", "imac", "laptop"]),
        CategoryRule(category: .watch, terms: [
            "wristwatch", "pocket_watch", "digital_watch", "smartwatch", "apple watch", "watch",
        ], weight: 1.2, exclude: ["stopwatch"]),
        CategoryRule(category: .musicalInstrument, terms: [
            "guitar", "piano", "violin", "drum", "saxophone", "trumpet", "flute", "cello",
            "ukulele", "keyboard instrument", "musical instrument", "bass guitar",
        ], weight: 1.2, exclude: []),
        CategoryRule(category: .tvHomeTheater, terms: [
            "television", "oled", "qled", "home theater", "soundbar", "projector", "receiver",
            "game console", "playstation", "xbox", "nintendo", "tv", "flatscreen",
        ], weight: 1.0, exclude: []),
        CategoryRule(category: .boat, terms: [
            "boat", "yacht", "kayak", "canoe", "watercraft", "marine", "outboard", "sailboat", "jet ski",
        ], weight: 1.0, exclude: []),
        CategoryRule(category: .trailer, terms: [
            "trailer", "tow hitch", "caravan", "camper", "rv", "travel trailer",
        ], weight: 1.0, exclude: []),
        CategoryRule(category: .snowRemoval, terms: [
            "snow blower", "snowblower", "snow thrower", "snow plow", "snowplow", "snowmobile",
        ], weight: 1.0, exclude: []),
        CategoryRule(category: .outdoorCooking, terms: [
            "grill", "barbecue", "bbq", "weber", "smoker", "pizza oven", "outdoor oven", "fire pit",
        ], weight: 1.0, exclude: []),
        CategoryRule(category: .downhillSkis, terms: [
            "alpine ski", "downhill", "ski boot", "ski pole", "snowboard", "binding",
        ], weight: 1.0, exclude: ["cross country", "nordic", "telemark"]),
        CategoryRule(category: .crossCountrySkis, terms: [
            "cross country", "nordic", "xc ski", "langlauf",
        ], weight: 1.1, exclude: []),
        CategoryRule(category: .telemarkSkis, terms: ["telemark"], weight: 1.2, exclude: []),
        CategoryRule(category: .tennis, terms: ["tennis", "racket", "racquet"], weight: 1.0, exclude: []),
        CategoryRule(category: .golf, terms: ["golf", "putter", "driver", "iron", "wedge", "fairway"], weight: 1.0, exclude: []),
        CategoryRule(category: .diyTools, terms: [
            "ryobi", "dewalt", "milwaukee", "makita", "stihl", "husqvarna",
            "hammer", "drill", "saw", "wrench", "screwdriver", "pliers", "tool", "ladder",
            "mower", "trimmer", "chainsaw", "leaf blower", "pressure washer",
        ], weight: 1.0, exclude: ["kitchen", "cooking", "factory", "industrial"]),
    ]

    private nonisolated static func scoreCategories(
        identifiers: [String],
        ocrHints: OCRHints
    ) -> [InventoryCategory: Float] {
        let blob = identifiers.joined(separator: " ").lowercased()
        guard !blob.isEmpty else { return [:] }

        var scores: [InventoryCategory: Float] = [:]
        for rule in categoryRules {
            var ruleScore: Float = 0
            for term in rule.terms where blob.contains(term) {
                if rule.exclude.contains(where: { blob.contains($0) }) { continue }
                ruleScore += rule.weight
            }
            if ruleScore > 0 {
                scores[rule.category, default: 0] += ruleScore
            }
        }

        if let brandEntry = brandKeywords.first(where: { entry in
            ocrHints.brand.map { $0.lowercased() == entry.display.lowercased() || blob.contains(entry.term) } ?? false
        }) {
            scores[brandEntry.category, default: 0] += 1.8
        }

        // Generic ski fallback when subtype unclear
        if blob.contains("ski") && scores[.downhillSkis] == nil && scores[.crossCountrySkis] == nil && scores[.telemarkSkis] == nil {
            scores[.downhillSkis, default: 0] += 0.8
        }

        return scores
    }

    private nonisolated static func mapCategory(
        primaryIdentifier: String,
        allIdentifiers: [String],
        ocrHints: OCRHints
    ) -> InventoryCategory {
        mapCategory(identifiers: [primaryIdentifier] + allIdentifiers.filter { $0 != primaryIdentifier }, ocrHints: ocrHints)
    }

    private nonisolated static func mapCategory(identifiers: [String], ocrHints: OCRHints) -> InventoryCategory {
        let scores = scoreCategories(identifiers: identifiers, ocrHints: ocrHints)
        if let best = scores.max(by: { $0.value < $1.value }), best.value >= 0.8 {
            return best.key
        }
        return .other
    }

    // MARK: - Display titles

    private nonisolated static let friendlyTitles: [String: String] = [
        "laptop_computer": "Laptop",
        "desktop_computer": "Desktop computer",
        "tablet_computer": "Tablet",
        "mobile_phone": "Smartphone",
        "smartphone": "Smartphone",
        "digital_watch": "Smartwatch",
        "wristwatch": "Watch",
        "television": "Television",
        "flatscreen_tv": "Flat-screen TV",
        "computer_monitor": "Monitor",
        "mountain_bike": "Mountain bike",
        "road_bicycle": "Road bike",
        "bicycle": "Bicycle",
        "sedan": "Car",
        "suv": "SUV",
        "automobile": "Car",
        "passenger_car": "Car",
        "pickup_truck": "Pickup truck",
        "refrigerator": "Refrigerator",
        "microwave_oven": "Microwave",
        "vacuum_cleaner": "Vacuum cleaner",
        "sofa": "Sofa",
        "coffee_maker": "Coffee maker",
        "washing_machine": "Washing machine",
        "alpine_ski": "Alpine skis",
        "cross_country_ski": "Cross-country skis",
        "snowboard": "Snowboard",
        "tennis_racket": "Tennis racket",
        "golf_club": "Golf club",
        "power_drill": "Power drill",
        "circular_saw": "Circular saw",
        "barbecue_grill": "Grill",
        "outdoor_grill": "Grill",
        "kayak": "Kayak",
        "canoe": "Canoe",
        "motorboat": "Boat",
        "travel_trailer": "Travel trailer",
        "snow_blower": "Snow blower",
        "lawn_mower": "Lawn mower",
        "chainsaw": "Chainsaw",
        "digital_camera": "Camera",
        "dslr_camera": "DSLR camera",
        "headphones": "Headphones",
        "earbuds": "Earbuds",
        "game_console": "Game console",
        "soundbar": "Soundbar",
    ]

    private nonisolated static func displayTitle(for identifier: String) -> String {
        if let friendly = friendlyTitles[identifier] {
            return friendly
        }
        let lower = identifier.lowercased()
        for (key, title) in friendlyTitles where lower.contains(key.replacingOccurrences(of: "_", with: " ")) || lower.contains(key) {
            return title
        }
        return humanizedIdentifier(identifier)
    }

    private nonisolated static func humanizedIdentifier(_ id: String) -> String {
        id
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map(\.capitalized)
            .joined(separator: " ")
    }

    // MARK: - Analysis summary

    private nonisolated static func buildAnalysisSummary(
        rankedOptions: [RankedOption],
        ocrHints: OCRHints,
        moneyCount: Int,
        hadText: Bool
    ) -> String {
        if rankedOptions.isEmpty, !hadText {
            return "Center a household item in the photo and try again — cars, bikes, tools, and home goods work best."
        }

        var parts: [String] = []
        if let top = rankedOptions.first {
            let pct = Int((top.confidence * 100).rounded())
            parts.append("Center focus: \(top.title) · \(top.category.displayTitle) (\(pct)%)")
        }

        if let brand = ocrHints.brand {
            parts.append("Brand: \(brand)")
        }
        if let productLine = ocrHints.productLine {
            parts.append("Model: \(productLine)")
        }
        if moneyCount > 0 {
            parts.append("Price text found — optional value fields filled below")
        }
        if rankedOptions.count > 1 {
            parts.append("Tap a row if the type isn’t right")
        } else if let top = rankedOptions.first, top.confidence < 0.35 {
            parts.append("Low confidence — pick the property and adjust the name")
        }

        return parts.joined(separator: " · ")
    }

    private nonisolated static func emptySuggestion(summary: String) -> Suggestion {
        Suggestion(
            suggestedName: "",
            category: .other,
            estimatedValue: 0,
            currentRetailPrice: 0,
            analysisSummary: summary,
            rankedOptions: [],
            suggestedNotes: ""
        )
    }

    // MARK: - Money from OCR

    private nonisolated static func extractMoneyValues(from text: String) -> [Double] {
        guard !text.isEmpty else { return [] }

        var values: [Double] = []
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        let withSymbol = #"(?:\$|€|£|kr\.?|NOK)\s*(\d{1,3}(?:[,\s]\d{3})+|\d+)(?:[.,](\d{2}))?\b"#
        if let regex = try? NSRegularExpression(pattern: withSymbol, options: []) {
            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 2 else { return }
                let intPart = ns.substring(with: match.range(at: 1))
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: " ", with: "")
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

// MARK: - String helpers

private extension String {
    /// Title-cases product phrases while keeping brand tokens like "MacBook" / "iPhone".
    nonisolated var capitalizedProductPhrase: String {
        split(separator: " ")
            .map { word -> String in
                let w = String(word)
                let lower = w.lowercased()
                if lower.hasPrefix("iphone") || lower.hasPrefix("ipad") || lower.hasPrefix("imac") {
                    return "i" + w.dropFirst().prefix(1).uppercased() + w.dropFirst(2).lowercased()
                }
                if lower.hasPrefix("macbook") {
                    return "MacBook" + w.dropFirst("macbook".count)
                }
                return w.prefix(1).uppercased() + w.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}
