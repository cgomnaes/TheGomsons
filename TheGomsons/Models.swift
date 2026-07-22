//
//  Models.swift
//  TheGomsons
//

import Foundation
import SwiftData

// MARK: - Inventory

/// High-level buckets for Belongings list sections and the category picker.
enum InventoryStashSection: Int, CaseIterable, Comparable, Sendable {
    case vehiclesTowing = 0
    case yardSeasonal = 1
    case toolsWorkshop = 2
    case grillsOutdoorCooking = 3
    case electronics = 4
    case valuables = 5
    case sportsRecreation = 6
    case household = 7
    case general = 8

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .vehiclesTowing: String(localized: "inventory.section.vehicles")
        case .yardSeasonal: String(localized: "inventory.section.yard")
        case .toolsWorkshop: String(localized: "inventory.section.tools")
        case .grillsOutdoorCooking: String(localized: "inventory.section.grills")
        case .electronics: String(localized: "inventory.section.electronics")
        case .valuables: String(localized: "inventory.section.valuables")
        case .sportsRecreation: String(localized: "inventory.section.sports")
        case .household: String(localized: "inventory.section.household")
        case .general: String(localized: "inventory.section.general")
        }
    }

    /// Categories shown under this section (picker + grouping).
    var categories: [InventoryCategory] {
        switch self {
        case .vehiclesTowing: [.car, .bicycle, .boat, .trailer]
        case .yardSeasonal: [.snowRemoval]
        case .toolsWorkshop: [.diyTools]
        case .grillsOutdoorCooking: [.outdoorCooking]
        case .electronics: [.computers, .phoneTablet, .tvHomeTheater]
        case .valuables: [.watch, .musicalInstrument]
        case .sportsRecreation: [.downhillSkis, .telemarkSkis, .crossCountrySkis, .tennis, .golf]
        case .household: [.household]
        case .general: [.other]
        }
    }
}

enum InventoryCategory: String, Codable, CaseIterable, Sendable {
    // Vehicles & mobility
    case car
    case bicycle
    case boat
    case trailer

    // Yard & seasonal
    case snowRemoval

    // Tools & workshop (e.g. Ryobi, hand tools, power tools)
    case diyTools

    // Grills, pizza ovens, outdoor cookware
    case outdoorCooking

    // Electronics
    case computers
    case phoneTablet
    case tvHomeTheater

    // Watches & instruments
    case watch
    case musicalInstrument

    // Sports
    case downhillSkis
    case telemarkSkis
    case crossCountrySkis
    case tennis
    case golf

    // Home & everyday items
    case household

    case other

    nonisolated var displayTitle: String {
        switch self {
        case .car: String(localized: "inventory.cat.car")
        case .bicycle: String(localized: "inventory.cat.bicycle")
        case .boat: String(localized: "inventory.cat.boat")
        case .trailer: String(localized: "inventory.cat.trailer")
        case .snowRemoval: String(localized: "inventory.cat.snow")
        case .diyTools: String(localized: "inventory.cat.tools")
        case .outdoorCooking: String(localized: "inventory.cat.outdoorCooking")
        case .computers: String(localized: "inventory.cat.computers")
        case .phoneTablet: String(localized: "inventory.cat.phoneTablet")
        case .tvHomeTheater: String(localized: "inventory.cat.tv")
        case .watch: String(localized: "inventory.cat.watch")
        case .musicalInstrument: String(localized: "inventory.cat.instrument")
        case .downhillSkis: String(localized: "inventory.cat.downhill")
        case .telemarkSkis: String(localized: "inventory.cat.telemark")
        case .crossCountrySkis: String(localized: "inventory.cat.xc")
        case .tennis: String(localized: "inventory.cat.tennis")
        case .golf: String(localized: "inventory.cat.golf")
        case .household: String(localized: "inventory.cat.household")
        case .other: String(localized: "inventory.cat.other")
        }
    }

    var stashSection: InventoryStashSection {
        switch self {
        case .car, .bicycle, .boat, .trailer: .vehiclesTowing
        case .snowRemoval: .yardSeasonal
        case .diyTools: .toolsWorkshop
        case .outdoorCooking: .grillsOutdoorCooking
        case .computers, .phoneTablet, .tvHomeTheater: .electronics
        case .watch, .musicalInstrument: .valuables
        case .downhillSkis, .telemarkSkis, .crossCountrySkis, .tennis, .golf: .sportsRecreation
        case .household: .household
        case .other: .general
        }
    }
}

/// Attached PDF/image for a belonging (receipt, manual, guarantee, or other).
enum InventoryDocumentKind: String, Codable, CaseIterable, Sendable {
    case receipt
    case manual
    case guarantee
    case other

    var displayTitle: String {
        switch self {
        case .receipt: String(localized: "inventory.doc.receipt")
        case .manual: String(localized: "inventory.doc.manual")
        case .guarantee: String(localized: "inventory.doc.guarantee")
        case .other: String(localized: "inventory.doc.other")
        }
    }
}

// MARK: - Location

enum LocationKind: String, Codable, CaseIterable, Sendable {
    case lived
    case visited
}

// MARK: - Property

enum PropertyKind: String, Codable, Sendable {
    case house
    case cabin
    case apartment
    case land
    case other

    /// Legacy raw values kept so existing SwiftData rows still decode.
    case singleFamily
    case condo
    case townhouse
    case vacation

    /// Types shown in pickers (saved values use only these going forward).
    static let pickerCases: [PropertyKind] = [.house, .cabin, .apartment, .land, .other]

    var displayTitle: String {
        switch self {
        case .house: String(localized: "property.kind.house")
        case .cabin: String(localized: "property.kind.cabin")
        case .apartment: String(localized: "property.kind.apartment")
        case .land: String(localized: "property.kind.land")
        case .other: String(localized: "property.kind.other")
        case .singleFamily: String(localized: "property.kind.house")
        case .condo: String(localized: "property.kind.apartment")
        case .townhouse: String(localized: "property.kind.house")
        case .vacation: String(localized: "property.kind.cabin")
        }
    }

    /// Maps legacy stored cases to the current picker set so bindings stay valid and data migrates forward.
    var normalizedForPicker: PropertyKind {
        switch self {
        case .house, .cabin, .apartment, .land, .other: self
        case .singleFamily, .townhouse: .house
        case .condo: .apartment
        case .vacation: .cabin
        }
    }
}

// MARK: - Property contractor / service provider types

enum ContractorTrade: String, Codable, CaseIterable, Sendable {
    case electrician
    case plumber
    case handyman
    case snowPlougher
    case carpenter
    case painter
    case landscaper
    case locksmith
    case other

    var displayTitle: String {
        switch self {
        case .electrician: String(localized: "contractor.electrician")
        case .plumber: String(localized: "contractor.plumber")
        case .handyman: String(localized: "contractor.handyman")
        case .snowPlougher: String(localized: "contractor.snow")
        case .carpenter: String(localized: "contractor.carpenter")
        case .painter: String(localized: "contractor.painter")
        case .landscaper: String(localized: "contractor.landscaper")
        case .locksmith: String(localized: "contractor.locksmith")
        case .other: String(localized: "contractor.other")
        }
    }

    var systemImage: String {
        switch self {
        case .electrician: "bolt.fill"
        case .plumber: "drop.fill"
        case .handyman: "wrench.and.screwdriver.fill"
        case .snowPlougher: "snowflake"
        case .carpenter: "hammer.fill"
        case .painter: "paintbrush.fill"
        case .landscaper: "leaf.fill"
        case .locksmith: "lock.fill"
        case .other: "person.fill.questionmark"
        }
    }
}

enum ServiceProviderKind: String, Codable, CaseIterable, Sendable {
    case electricity
    case gas
    case water
    case internet
    case publicServices
    case insurance
    case other

    var displayTitle: String {
        switch self {
        case .electricity: String(localized: "svc.electricity")
        case .gas: String(localized: "svc.gas")
        case .water: String(localized: "svc.water")
        case .internet: String(localized: "svc.internet")
        case .publicServices: String(localized: "svc.public")
        case .insurance: String(localized: "svc.insurance")
        case .other: String(localized: "svc.other")
        }
    }

    var systemImage: String {
        switch self {
        case .electricity: "bolt.circle.fill"
        case .gas: "flame.fill"
        case .water: "drop.circle.fill"
        case .internet: "wifi"
        case .publicServices: "building.columns.fill"
        case .insurance: "shield.checkered"
        case .other: "ellipsis.circle.fill"
        }
    }
}

// MARK: - Bloomberg / CSV import

/// Row shape aligned with typical export columns (e.g. Bloomberg Terminal CSV) for easy parsing later.
struct BloombergAssetRow: Codable, Sendable, Equatable {
    var name: String
    var assetClass: String
    var value: Double
    var lastUpdated: Date
}

// MARK: - SwiftData models

@Model
final class Property {
    var name: String = ""
    var address: String = ""
    var wifiNetwork: String = ""
    var wifiPassword: String = ""
    /// On-site medical, fire egress, breaker location, etc. (distinct from dialable emergency numbers below.)
    var emergencyNotes: String = ""

    @Attribute(.externalStorage)
    var coverImageData: Data?

    // MARK: Key information
    var propertyKind: PropertyKind = PropertyKind.other
    var bedrooms: Int = 0
    var bathrooms: Double = 0
    /// Stored attribute name must stay `livingAreaSqFt` for CloudKit (property renames are not allowed). UI treats values as m².
    var livingAreaSqFt: Int = 0
    var yearBuilt: Int = 0
    var insuranceCarrier: String = ""
    var insurancePolicyNumber: String = ""
    var utilitiesNotes: String = ""

    // MARK: Other systems (access, utilities-adjacent notes)
    var alarmOrSecurityCode: String = ""
    var gateOrAccessCode: String = ""
    var waterShutoffLocation: String = ""
    var trashAndRecyclingSchedule: String = ""
    var parkingNotes: String = ""
    var smartHomeNotes: String = ""

    // MARK: Soft delete (archive)
    var isArchived: Bool = false
    /// `Date.distantPast` when not archived — non-optional keeps CloudKit export stable (nil optional dates can confuse mirroring).
    var archivedAt: Date = Date.distantPast

    @Relationship(deleteRule: .cascade, inverse: \InventoryItem.property)
    var inventoryItems: [InventoryItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \PropertyContact.property)
    var contacts: [PropertyContact]? = []

    @Relationship(deleteRule: .cascade, inverse: \PropertyEmergencyLine.property)
    var emergencyLines: [PropertyEmergencyLine]? = []

    @Relationship(deleteRule: .cascade, inverse: \PropertyContractor.property)
    var contractors: [PropertyContractor]? = []

    @Relationship(deleteRule: .cascade, inverse: \PropertyServiceProvider.property)
    var serviceProviders: [PropertyServiceProvider]? = []

    @Relationship(deleteRule: .nullify, inverse: \Recipe.property)
    var recipes: [Recipe]? = []

    @Relationship(deleteRule: .cascade, inverse: \PropertyMaintenanceEntry.property)
    var maintenanceEntries: [PropertyMaintenanceEntry]? = []

    init(
        name: String = "",
        address: String = "",
        wifiNetwork: String = "",
        wifiPassword: String = "",
        emergencyNotes: String = "",
        coverImageData: Data? = nil,
        propertyKind: PropertyKind = PropertyKind.other,
        bedrooms: Int = 0,
        bathrooms: Double = 0,
        livingAreaSqFt: Int = 0,
        yearBuilt: Int = 0,
        insuranceCarrier: String = "",
        insurancePolicyNumber: String = "",
        utilitiesNotes: String = "",
        alarmOrSecurityCode: String = "",
        gateOrAccessCode: String = "",
        waterShutoffLocation: String = "",
        trashAndRecyclingSchedule: String = "",
        parkingNotes: String = "",
        smartHomeNotes: String = "",
        inventoryItems: [InventoryItem] = [],
        contacts: [PropertyContact] = [],
        emergencyLines: [PropertyEmergencyLine] = []
    ) {
        self.name = name
        self.address = address
        self.wifiNetwork = wifiNetwork
        self.wifiPassword = wifiPassword
        self.emergencyNotes = emergencyNotes
        self.coverImageData = coverImageData
        self.propertyKind = propertyKind
        self.bedrooms = bedrooms
        self.bathrooms = bathrooms
        self.livingAreaSqFt = livingAreaSqFt
        self.yearBuilt = yearBuilt
        self.insuranceCarrier = insuranceCarrier
        self.insurancePolicyNumber = insurancePolicyNumber
        self.utilitiesNotes = utilitiesNotes
        self.alarmOrSecurityCode = alarmOrSecurityCode
        self.gateOrAccessCode = gateOrAccessCode
        self.waterShutoffLocation = waterShutoffLocation
        self.trashAndRecyclingSchedule = trashAndRecyclingSchedule
        self.parkingNotes = parkingNotes
        self.smartHomeNotes = smartHomeNotes
        self.inventoryItems = inventoryItems
        self.contacts = contacts
        self.emergencyLines = emergencyLines
    }
}

@Model
final class PropertyContact {
    var name: String = ""
    var role: String = ""
    var phone: String = ""
    var email: String = ""
    var notes: String = ""
    var isPrimary: Bool = false
    var sortOrder: Int = 0

    var property: Property?

    init(
        name: String = "",
        role: String = "",
        phone: String = "",
        email: String = "",
        notes: String = "",
        isPrimary: Bool = false,
        sortOrder: Int = 0,
        property: Property? = nil
    ) {
        self.name = name
        self.role = role
        self.phone = phone
        self.email = email
        self.notes = notes
        self.isPrimary = isPrimary
        self.sortOrder = sortOrder
        self.property = property
    }
}

@Model
final class PropertyEmergencyLine {
    var label: String = ""
    var phoneNumber: String = ""
    var sortOrder: Int = 0

    var property: Property?

    init(
        label: String = "",
        phoneNumber: String = "",
        sortOrder: Int = 0,
        property: Property? = nil
    ) {
        self.label = label
        self.phoneNumber = phoneNumber
        self.sortOrder = sortOrder
        self.property = property
    }
}

@Model
final class PropertyContractor {
    var name: String = ""
    var trade: ContractorTrade = ContractorTrade.other
    var phone: String = ""
    var email: String = ""
    var website: String = ""
    var notes: String = ""
    var sortOrder: Int = 0

    var property: Property?

    init(
        name: String = "",
        trade: ContractorTrade = ContractorTrade.other,
        phone: String = "",
        email: String = "",
        website: String = "",
        notes: String = "",
        sortOrder: Int = 0,
        property: Property? = nil
    ) {
        self.name = name
        self.trade = trade
        self.phone = phone
        self.email = email
        self.website = website
        self.notes = notes
        self.sortOrder = sortOrder
        self.property = property
    }
}

@Model
final class PropertyServiceProvider {
    var companyName: String = ""
    var kind: ServiceProviderKind = ServiceProviderKind.other
    var accountNumber: String = ""
    var phone: String = ""
    var email: String = ""
    var website: String = ""
    var notes: String = ""
    var sortOrder: Int = 0

    var property: Property?

    init(
        companyName: String = "",
        kind: ServiceProviderKind = ServiceProviderKind.other,
        accountNumber: String = "",
        phone: String = "",
        email: String = "",
        website: String = "",
        notes: String = "",
        sortOrder: Int = 0,
        property: Property? = nil
    ) {
        self.companyName = companyName
        self.kind = kind
        self.accountNumber = accountNumber
        self.phone = phone
        self.email = email
        self.website = website
        self.notes = notes
        self.sortOrder = sortOrder
        self.property = property
    }
}

// MARK: - Property presentation helpers

extension Property {
    /// Compact “3 BR · 2 BA · 120 m²” line for list rows; `nil` if nothing set.
    var formattedBedBathArea: String? {
        var parts: [String] = []
        if bedrooms > 0 {
            parts.append("\(bedrooms) BR")
        }
        if bathrooms > 0 {
            parts.append(String(format: "%g BA", bathrooms))
        }
        if livingAreaSqFt > 0 {
            parts.append("\(livingAreaSqFt.formatted(.number.grouping(.never))) m²")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var primaryContactForDisplay: PropertyContact? {
        let sorted = (contacts ?? []).sorted { a, b in
            if a.isPrimary != b.isPrimary { return a.isPrimary && !b.isPrimary }
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.name < b.name
        }
        return sorted.first { !$0.phone.isEmpty || !$0.email.isEmpty }
            ?? sorted.first { !$0.name.isEmpty }
    }

    var firstEmergencyNumber: PropertyEmergencyLine? {
        (emergencyLines ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .first { !$0.phoneNumber.isEmpty }
    }
}

@Model
final class InventoryItem {
    var name: String = ""
    var category: InventoryCategory = InventoryCategory.other
    var purchaseDate: Date = Date(timeIntervalSince1970: 0)
    var warrantyExpiry: Date = Date(timeIntervalSince1970: 0)
    /// Replacement / insured value (e.g. from photo text or manual entry).
    var estimatedValue: Double = 0
    /// Observed list or retail price when visible in the photo (OCR); otherwise 0.
    var currentRetailPrice: Double = 0
    /// Free-form notes (serial numbers, reminders).
    var notes: String = ""
    /// Where the item was bought (store, site, person).
    var purchasePlace: String = ""
    /// Where it is now when not (only) tied to a property — e.g. garage, with Herman.
    var locationDetail: String = ""
    /// Primary product / support / shop website.
    var productURL: String = ""
    /// Policy / rider notes for insurance.
    var insuranceNotes: String = ""

    /// Optional photo taken when adding the item (external blob storage for CloudKit).
    @Attribute(.externalStorage)
    var photoData: Data?

    /// Optional home/cabin; `nil` means family-wide.
    var property: Property?

    @Relationship(deleteRule: .cascade, inverse: \InventoryItemLink.item)
    var links: [InventoryItemLink]? = []

    @Relationship(deleteRule: .cascade, inverse: \InventoryItemDocument.item)
    var documents: [InventoryItemDocument]? = []

    init(
        name: String = "",
        category: InventoryCategory = InventoryCategory.other,
        purchaseDate: Date = Date(timeIntervalSince1970: 0),
        warrantyExpiry: Date = Date(timeIntervalSince1970: 0),
        estimatedValue: Double = 0,
        currentRetailPrice: Double = 0,
        notes: String = "",
        purchasePlace: String = "",
        locationDetail: String = "",
        productURL: String = "",
        insuranceNotes: String = "",
        photoData: Data? = nil,
        property: Property? = nil,
        links: [InventoryItemLink] = [],
        documents: [InventoryItemDocument] = []
    ) {
        self.name = name
        self.category = category
        self.purchaseDate = purchaseDate
        self.warrantyExpiry = warrantyExpiry
        self.estimatedValue = estimatedValue
        self.currentRetailPrice = currentRetailPrice
        self.notes = notes
        self.purchasePlace = purchasePlace
        self.locationDetail = locationDetail
        self.productURL = productURL
        self.insuranceNotes = insuranceNotes
        self.photoData = photoData
        self.property = property
        self.links = links
        self.documents = documents
    }
}

@Model
final class InventoryItemLink {
    var title: String = ""
    var url: String = ""
    var sortOrder: Int = 0
    var item: InventoryItem?

    init(title: String = "", url: String = "", sortOrder: Int = 0, item: InventoryItem? = nil) {
        self.title = title
        self.url = url
        self.sortOrder = sortOrder
        self.item = item
    }
}

@Model
final class InventoryItemDocument {
    var title: String = ""
    var kindRaw: String = InventoryDocumentKind.other.rawValue
    var fileName: String = ""
    var contentType: String = "application/pdf"
    var sortOrder: Int = 0

    @Attribute(.externalStorage)
    var fileData: Data?

    var item: InventoryItem?

    var kind: InventoryDocumentKind {
        get { InventoryDocumentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    init(
        title: String = "",
        kind: InventoryDocumentKind = .other,
        fileName: String = "",
        contentType: String = "application/pdf",
        fileData: Data? = nil,
        sortOrder: Int = 0,
        item: InventoryItem? = nil
    ) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.fileName = fileName
        self.contentType = contentType
        self.fileData = fileData
        self.sortOrder = sortOrder
        self.item = item
    }
}

extension InventoryItem {
    /// Leading/trailing whitespace trimmed; use for list previews and search.
    var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedPurchasePlace: String {
        purchasePlace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedLocationDetail: String {
        locationDetail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedProductURL: String {
        productURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Property name, or family-wide label, plus optional location detail.
    var locationSummary: String {
        let base: String
        if let name = property?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            base = name
        } else {
            base = String(localized: "inventory.family_wide")
        }
        let detail = trimmedLocationDetail
        if detail.isEmpty { return base }
        return "\(base) · \(detail)"
    }

    var sortedLinks: [InventoryItemLink] {
        (links ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedDocuments: [InventoryItemDocument] {
        (documents ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var hasAttachments: Bool {
        !trimmedProductURL.isEmpty || !(links ?? []).isEmpty || !(documents ?? []).isEmpty
    }

    /// Groups items by `InventoryStashSection` in display order; empty sections omitted.
    static func groupedByStashSection(_ items: [InventoryItem]) -> [(section: InventoryStashSection, items: [InventoryItem])] {
        let grouped = Dictionary(grouping: items) { $0.category.stashSection }
        return InventoryStashSection.allCases.compactMap { sec in
            guard let list = grouped[sec], !list.isEmpty else { return nil }
            let sorted = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return (sec, sorted)
        }
    }
}

@Model
final class Asset {
    var name: String = ""
    var assetClass: String = ""
    /// Stored as `Double` for CloudKit; map CSV strings in your importer before assignment.
    var value: Double = 0
    var lastUpdated: Date = Date(timeIntervalSince1970: 0)

    init(
        name: String = "",
        assetClass: String = "",
        value: Double = 0,
        lastUpdated: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.name = name
        self.assetClass = assetClass
        self.value = value
        self.lastUpdated = lastUpdated
    }

    convenience init(row: BloombergAssetRow) {
        self.init(
            name: row.name,
            assetClass: row.assetClass,
            value: row.value,
            lastUpdated: row.lastUpdated
        )
    }
}

@Model
final class Location {
    var cityName: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var type: LocationKind = LocationKind.visited

    init(
        cityName: String = "",
        latitude: Double = 0,
        longitude: Double = 0,
        type: LocationKind = LocationKind.visited
    ) {
        self.cityName = cityName
        self.latitude = latitude
        self.longitude = longitude
        self.type = type
    }
}

@Model
final class Recipe {
    var title: String = ""
    /// JSON array of strings (`["eggs","flour"]`). Stored as plain UTF-8 text for CloudKit—**not** a keyed archive,
    /// so Public DB rows cannot hit `NSCocoaErrorDomain` 4864 from corrupt `[String]` transformable data.
    var ingredientsJSON: String = "[]"
    var instructions: String = ""
    var prepTime: TimeInterval = 0
    /// Free-text place when not (only) tied to a property — e.g. “Marbella”, “Skåbu kitchen”.
    var placeLabel: String = ""
    var notes: String = ""
    var sortOrder: Int = 0

    /// Optional home/cabin this recipe belongs with (waffle recipe at the cabin, etc.).
    var property: Property?

    init(
        title: String = "",
        ingredients: [String] = [],
        instructions: String = "",
        prepTime: TimeInterval = 0,
        placeLabel: String = "",
        notes: String = "",
        sortOrder: Int = 0,
        property: Property? = nil
    ) {
        self.title = title
        self.ingredientsJSON = Self.encodeIngredientsJSON(ingredients)
        self.instructions = instructions
        self.prepTime = prepTime
        self.placeLabel = placeLabel
        self.notes = notes
        self.sortOrder = sortOrder
        self.property = property
    }

    private static func encodeIngredientsJSON(_ ingredients: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ingredients),
              let s = String(data: data, encoding: .utf8)
        else { return "[]" }
        return s
    }
}

extension Recipe {
    /// App-facing list; persisted field is `ingredientsJSON`.
    var ingredients: [String] {
        get {
            guard let data = ingredientsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            ingredientsJSON = Self.encodeIngredientsJSON(newValue)
        }
    }

    var trimmedPlaceLabel: String {
        placeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Property name, free-text place, or “family-wide”.
    var placeSummary: String {
        if let name = property?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            let extra = trimmedPlaceLabel
            return extra.isEmpty ? name : "\(name) · \(extra)"
        }
        let label = trimmedPlaceLabel
        return label.isEmpty ? String(localized: "recipe.place.family") : label
    }

    var prepTimeMinutes: Int {
        get { Int((prepTime / 60.0).rounded()) }
        set { prepTime = TimeInterval(max(0, newValue) * 60) }
    }

    static func sorted(_ recipes: [Recipe]) -> [Recipe] {
        recipes.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}

// MARK: - Property maintenance log

enum MaintenanceCategory: String, Codable, CaseIterable, Sendable {
    case hvac
    case roof
    case plumbing
    case electrical
    case outdoor
    case appliance
    case security
    case other

    var displayTitle: String {
        switch self {
        case .hvac: String(localized: "maintenance.category.hvac")
        case .roof: String(localized: "maintenance.category.roof")
        case .plumbing: String(localized: "maintenance.category.plumbing")
        case .electrical: String(localized: "maintenance.category.electrical")
        case .outdoor: String(localized: "maintenance.category.outdoor")
        case .appliance: String(localized: "maintenance.category.appliance")
        case .security: String(localized: "maintenance.category.security")
        case .other: String(localized: "maintenance.category.other")
        }
    }

    var systemImage: String {
        switch self {
        case .hvac: "fan.fill"
        case .roof: "house.fill"
        case .plumbing: "drop.fill"
        case .electrical: "bolt.fill"
        case .outdoor: "leaf.fill"
        case .appliance: "washer.fill"
        case .security: "lock.fill"
        case .other: "wrench.and.screwdriver.fill"
        }
    }
}

@Model
final class PropertyMaintenanceEntry {
    var title: String = ""
    /// Stored as String raw value for CloudKit stability (same pattern as `FamilyEvent.kindRaw`).
    var categoryRaw: String = MaintenanceCategory.other.rawValue
    var performedAt: Date = Date(timeIntervalSince1970: 0)
    /// `Date(timeIntervalSince1970: 0)` means no next-due date.
    var nextDueAt: Date = Date(timeIntervalSince1970: 0)
    var performedBy: String = ""
    var costAmount: Double = 0
    var notes: String = ""
    var sortOrder: Int = 0

    @Attribute(.externalStorage)
    var photoData: Data?

    var property: Property?

    var category: MaintenanceCategory {
        get { MaintenanceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        title: String = "",
        category: MaintenanceCategory = .other,
        performedAt: Date = Date(),
        nextDueAt: Date = Date(timeIntervalSince1970: 0),
        performedBy: String = "",
        costAmount: Double = 0,
        notes: String = "",
        sortOrder: Int = 0,
        photoData: Data? = nil,
        property: Property? = nil
    ) {
        self.title = title
        self.categoryRaw = category.rawValue
        self.performedAt = performedAt
        self.nextDueAt = nextDueAt
        self.performedBy = performedBy
        self.costAmount = costAmount
        self.notes = notes
        self.sortOrder = sortOrder
        self.photoData = photoData
        self.property = property
    }
}

extension PropertyMaintenanceEntry {
    private static let epoch = Date(timeIntervalSince1970: 0)

    var hasNextDue: Bool { nextDueAt > Self.epoch }

    var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedPerformedBy: String {
        performedBy.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Days until next due (negative = overdue). `nil` if no due date.
    func daysUntilDue(after afterDate: Date = Date()) -> Int? {
        guard hasNextDue else { return nil }
        let cal = Calendar.current
        let from = cal.startOfDay(for: afterDate)
        let to = cal.startOfDay(for: nextDueAt)
        return cal.dateComponents([.day], from: from, to: to).day
    }

    static func sorted(_ entries: [PropertyMaintenanceEntry]) -> [PropertyMaintenanceEntry] {
        entries.sorted {
            // Upcoming / overdue first by nextDue, then by performed date descending.
            let lDue = $0.hasNextDue ? $0.nextDueAt : Date.distantFuture
            let rDue = $1.hasNextDue ? $1.nextDueAt : Date.distantFuture
            if lDue != rDue { return lDue < rDue }
            if $0.performedAt != $1.performedAt { return $0.performedAt > $1.performedAt }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}

/// Type of family calendar entry (drives icons in month/year views).
enum FamilyEventKind: String, Codable, CaseIterable, Sendable {
    case birthday
    case party
    case holiday
    case school
    case other

    var displayTitle: String {
        switch self {
        case .birthday: String(localized: "event.kind.birthday")
        case .party: String(localized: "event.kind.party")
        case .holiday: String(localized: "event.kind.holidaytrip")
        case .school: String(localized: "event.kind.school")
        case .other: String(localized: "event.kind.other")
        }
    }

    /// SF Symbol used in calendar grids and lists.
    var systemImageName: String {
        switch self {
        case .birthday: "gift.fill"
        case .party: "balloon.2.fill"
        case .holiday: "airplane.departure"
        case .school: "book.fill"
        case .other: "calendar"
        }
    }
}

@Model
final class FamilyEvent {
    var title: String = ""
    var date: Date = Date(timeIntervalSince1970: 0)
    var location: String = ""
    var assignedTo: String = ""
    /// Minutes before the event to fire a local notification (0 = at event time).
    var reminderMinutesBefore: Int = 30
    /// Stored as `String` (same as `FamilyEventKind.rawValue`) so Core Data / CloudKit never uses a keyed archive for the enum.
    var kindRaw: String = FamilyEventKind.other.rawValue
    /// Shown in the “Don’t forget” strip (important reminders).
    var dontForget: Bool = false
    /// For birthdays: year the person was born (age = celebration year − this). `0` = unset (fall back to year on `date`).
    var yearBorn: Int = 0

    init(
        title: String = "",
        date: Date = Date(timeIntervalSince1970: 0),
        location: String = "",
        assignedTo: String = "",
        reminderMinutesBefore: Int = 30,
        kind: FamilyEventKind = .other,
        dontForget: Bool = false,
        yearBorn: Int = 0
    ) {
        self.title = title
        self.date = date
        self.location = location
        self.assignedTo = assignedTo
        self.reminderMinutesBefore = reminderMinutesBefore
        self.kindRaw = kind.rawValue
        self.dontForget = dontForget
        self.yearBorn = yearBorn
    }
}

extension FamilyEvent {
    /// Use this in app code; persisted field is `kindRaw`.
    var kind: FamilyEventKind {
        get { FamilyEventKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: - Birthdays (annual recurrence + age)

extension FamilyEvent {
    /// Birth year for age: explicit `yearBorn` when set, otherwise the year on `date` (older data).
    var resolvedBirthYear: Int {
        guard kind == .birthday else {
            return Calendar.current.component(.year, from: date)
        }
        if yearBorn > 0 { return yearBorn }
        return Calendar.current.component(.year, from: date)
    }

    /// Age on the calendar day of the celebration (e.g. turning 40 on that birthday). Nil when not a birthday.
    func age(onCelebrationDay day: Date) -> Int? {
        guard kind == .birthday else { return nil }
        let y = Calendar.current.component(.year, from: day)
        return y - resolvedBirthYear
    }

    /// Next time this event occurs (for birthdays: next annual date at start of day).
    func nextOccurrence(after afterDate: Date) -> Date {
        guard kind == .birthday else { return date }
        let cal = Calendar.current
        var match = DateComponents()
        match.month = cal.component(.month, from: date)
        match.day = cal.component(.day, from: date)
        match.hour = 0
        match.minute = 0
        match.second = 0
        if let next = cal.nextDate(after: afterDate.addingTimeInterval(-1), matching: match, matchingPolicy: .nextTime) {
            return cal.startOfDay(for: next)
        }
        return cal.startOfDay(for: date)
    }

    /// The celebration instant in the same calendar month as `monthStart` (same year as that month).
    func occurrence(inMonthContaining monthStart: Date) -> Date? {
        let cal = Calendar.current
        let targetMonth = cal.component(.month, from: monthStart)
        let m = cal.component(.month, from: date)
        guard m == targetMonth else { return nil }
        let y = cal.component(.year, from: monthStart)
        let d = cal.component(.day, from: date)
        var dc = DateComponents(year: y, month: m, day: d)
        let base: Date?
        if let b = cal.date(from: dc) {
            base = b
        } else if m == 2 && d == 29 {
            dc.day = 28
            base = cal.date(from: dc)
        } else {
            base = nil
        }
        guard let base else { return nil }
        if kind == .birthday {
            return cal.startOfDay(for: base)
        }
        return cal.date(
            bySettingHour: cal.component(.hour, from: date),
            minute: cal.component(.minute, from: date),
            second: cal.component(.second, from: date),
            of: base
        )
    }

    /// Celebration date in the given calendar year (month/day from birth date; Feb 29 → Feb 28 in non-leap years).
    func occurrence(inYear year: Int) -> Date? {
        let cal = Calendar.current
        let m = cal.component(.month, from: date)
        guard let monthStart = cal.date(from: DateComponents(year: year, month: m, day: 1)) else { return nil }
        return occurrence(inMonthContaining: monthStart)
    }
}

// MARK: - Subscriptions & memberships

enum SubscriptionCategory: String, Codable, CaseIterable, Sendable {
    case streaming
    case clubMembership
    case travelInsurance
    case software
    case newsMedia
    case fitness
    case utilities
    case other

    var displayTitle: String {
        switch self {
        case .streaming: String(localized: "sub.cat.streaming")
        case .clubMembership: String(localized: "sub.cat.club")
        case .travelInsurance: String(localized: "sub.cat.travel_ins")
        case .software: String(localized: "sub.cat.software")
        case .newsMedia: String(localized: "sub.cat.news")
        case .fitness: String(localized: "sub.cat.fitness")
        case .utilities: String(localized: "sub.cat.utilities")
        case .other: String(localized: "sub.cat.other")
        }
    }
}

enum SubscriptionBillingPeriod: String, Codable, CaseIterable, Sendable {
    case monthly
    case quarterly
    case yearly
    case oneTime

    var displayTitle: String {
        switch self {
        case .monthly: String(localized: "sub.bill.monthly")
        case .quarterly: String(localized: "sub.bill.quarterly")
        case .yearly: String(localized: "sub.bill.yearly")
        case .oneTime: String(localized: "sub.bill.onetime")
        }
    }

    /// Convert an amount in this billing period to a monthly equivalent.
    func toMonthly(_ amount: Double) -> Double {
        switch self {
        case .monthly: amount
        case .quarterly: amount / 3.0
        case .yearly: amount / 12.0
        case .oneTime: 0
        }
    }

    /// Convert an amount in this billing period to a yearly equivalent.
    func toYearly(_ amount: Double) -> Double {
        switch self {
        case .monthly: amount * 12.0
        case .quarterly: amount * 4.0
        case .yearly: amount
        case .oneTime: 0
        }
    }
}

@Model
final class Subscription {
    var name: String = ""
    var category: SubscriptionCategory = SubscriptionCategory.other
    var websiteURL: String = ""
    var loginEmail: String = ""
    var password: String = ""
    var notes: String = ""
    var renewalDate: Date?
    var priceAmount: Double = 0
    var billingPeriod: SubscriptionBillingPeriod = SubscriptionBillingPeriod.monthly
    var sortOrder: Int = 0
    var expiryDate: Date?
    var includeInSummary: Bool = true

    init(
        name: String = "",
        category: SubscriptionCategory = .other,
        websiteURL: String = "",
        loginEmail: String = "",
        password: String = "",
        notes: String = "",
        renewalDate: Date? = nil,
        priceAmount: Double = 0,
        billingPeriod: SubscriptionBillingPeriod = .monthly,
        sortOrder: Int = 0,
        expiryDate: Date? = nil,
        includeInSummary: Bool = true
    ) {
        self.name = name
        self.category = category
        self.websiteURL = websiteURL
        self.loginEmail = loginEmail
        self.password = password
        self.notes = notes
        self.renewalDate = renewalDate
        self.priceAmount = priceAmount
        self.billingPeriod = billingPeriod
        self.sortOrder = sortOrder
        self.expiryDate = expiryDate
        self.includeInSummary = includeInSummary
    }
}

// MARK: - Family tree

/// Groups people for filtering: your line, spouse’s line, household, or everyone else.
enum FamilyTreeBranch: String, Codable, CaseIterable, Sendable {
    case ourHousehold
    case myParentsLine
    case spouseParentsLine
    case extended

    var displayTitle: String {
        switch self {
        case .ourHousehold: String(localized: "family.branch.household")
        case .myParentsLine: String(localized: "family.branch.my_parents")
        case .spouseParentsLine: String(localized: "family.branch.spouse_parents")
        case .extended: String(localized: "family.branch.extended")
        }
    }
}

/// How two linked people are involved (dating, married, etc.).
enum PartnerRelationshipStatus: String, Codable, CaseIterable, Sendable {
    case dating
    case engaged
    case married
    case partner

    var displayTitle: String {
        switch self {
        case .dating: String(localized: "family_tree.partner_status.dating")
        case .engaged: String(localized: "family_tree.partner_status.engaged")
        case .married: String(localized: "family_tree.partner_status.married")
        case .partner: String(localized: "family_tree.partner_status.partner")
        }
    }

    static func parseCSV(_ raw: String) -> PartnerRelationshipStatus? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch key {
        case "dating", "date", "boyfriend", "girlfriend": return .dating
        case "engaged", "fiance", "fiancee", "fiancé", "fiancée": return .engaged
        case "married", "spouse", "husband", "wife": return .married
        case "partner", "partnered", "significantother", "so": return .partner
        default: return PartnerRelationshipStatus(rawValue: key)
        }
    }
}

@Model
final class FamilyPerson {
    var name: String = ""
    var birthDate: Date?
    var notes: String = ""
    /// Email for contact / reference (optional).
    var email: String = ""
    /// Phone number as entered (optional).
    var mobile: String = ""
    /// City or locality (optional).
    var city: String = ""
    /// Geocoded from `city` for the family map; `nil` until resolved or if lookup failed.
    var cityLatitude: Double?
    var cityLongitude: Double?
    /// When `relation` in CSV is not a branch keyword, stored here (e.g. Aunt, Cousin).
    var familyRelationLabel: String = ""
    /// Free-text hobbies / interests for social browsing.
    var hobbies: String = ""
    /// Raw `PartnerRelationshipStatus.rawValue`, or empty when unset / no partner.
    var partnerStatusRaw: String = ""
    /// When true, this person is marked deceased (shown on tree/profile; birthdays are not celebrated).
    var isDeceased: Bool = false
    /// Optional date of death when `isDeceased` is true.
    var deathDate: Date?

    @Attribute(.externalStorage)
    var photoData: Data?

    var mother: FamilyPerson?
    var father: FamilyPerson?

    /// Forward link (this person’s chosen partner). Inverse is `partnerOf` on the other person—CloudKit requires this pair.
    var partner: FamilyPerson?

    @Relationship(inverse: \FamilyPerson.partner)
    var partnerOf: FamilyPerson?

    @Relationship(inverse: \FamilyPerson.mother)
    var childrenWhereMother: [FamilyPerson]? = []

    @Relationship(inverse: \FamilyPerson.father)
    var childrenWhereFather: [FamilyPerson]? = []

    /// Explicit sibling links (forward). Inverse is `siblingOf`. Prefer shared parents when known; use this when parents aren’t listed.
    var siblings: [FamilyPerson]? = []

    @Relationship(inverse: \FamilyPerson.siblings)
    var siblingOf: [FamilyPerson]? = []

    /// Lower = higher on the tree (e.g. 0 = grandparents, 2 = your generation).
    var treeTier: Int = 2

    var branch: FamilyTreeBranch = FamilyTreeBranch.ourHousehold

    var sortOrder: Int = 0
    /// When true and `birthDate` is set, this birthday appears in the Calendar tab (and can drive notifications).
    var includeBirthdayOnCalendar: Bool = true

    init(
        name: String = "",
        birthDate: Date? = nil,
        notes: String = "",
        email: String = "",
        mobile: String = "",
        city: String = "",
        familyRelationLabel: String = "",
        hobbies: String = "",
        partnerStatus: PartnerRelationshipStatus? = nil,
        isDeceased: Bool = false,
        deathDate: Date? = nil,
        photoData: Data? = nil,
        mother: FamilyPerson? = nil,
        father: FamilyPerson? = nil,
        partner: FamilyPerson? = nil,
        treeTier: Int = 2,
        branch: FamilyTreeBranch = FamilyTreeBranch.ourHousehold,
        sortOrder: Int = 0,
        includeBirthdayOnCalendar: Bool = true,
        cityLatitude: Double? = nil,
        cityLongitude: Double? = nil
    ) {
        self.name = name
        self.birthDate = birthDate
        self.notes = notes
        self.email = email
        self.mobile = mobile
        self.city = city
        self.cityLatitude = cityLatitude
        self.cityLongitude = cityLongitude
        self.familyRelationLabel = familyRelationLabel
        self.hobbies = hobbies
        self.partnerStatusRaw = partnerStatus?.rawValue ?? ""
        self.isDeceased = isDeceased
        self.deathDate = deathDate
        self.photoData = photoData
        self.mother = mother
        self.father = father
        self.partner = partner
        self.treeTier = treeTier
        self.branch = branch
        self.sortOrder = sortOrder
        self.includeBirthdayOnCalendar = includeBirthdayOnCalendar
    }

    /// Partner link whether stored as `partner` or the inverse `partnerOf`.
    var resolvedPartner: FamilyPerson? { partner ?? partnerOf }

    var partnerStatus: PartnerRelationshipStatus? {
        get { PartnerRelationshipStatus(rawValue: partnerStatusRaw) }
        set { partnerStatusRaw = newValue?.rawValue ?? "" }
    }

    /// Status to show when a partner is linked; defaults to `.partner` if raw is empty.
    var displayPartnerStatus: PartnerRelationshipStatus? {
        guard resolvedPartner != nil else { return nil }
        return partnerStatus ?? .partner
    }

    /// Age in whole years at death, when both birth and death dates are known.
    var ageAtDeath: Int? {
        guard isDeceased, let birthDate, let deathDate else { return nil }
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: deathDate).year
        return years.map { max(0, $0) }
    }

    /// Explicit sibling links in either direction (not including parent-derived).
    var explicitSiblings: [FamilyPerson] {
        var seen = Set<PersistentIdentifier>()
        var result: [FamilyPerson] = []
        for s in (siblings ?? []) + (siblingOf ?? []) {
            guard s.persistentModelID != persistentModelID else { continue }
            if seen.insert(s.persistentModelID).inserted {
                result.append(s)
            }
        }
        return result.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Siblings via shared mother/father and/or explicit links.
    func resolvedSiblings(among people: [FamilyPerson]) -> [FamilyPerson] {
        var seen = Set<PersistentIdentifier>()
        var result: [FamilyPerson] = []

        func add(_ other: FamilyPerson) {
            guard other.persistentModelID != persistentModelID else { return }
            if seen.insert(other.persistentModelID).inserted {
                result.append(other)
            }
        }

        for s in explicitSiblings { add(s) }

        for other in people {
            guard other.persistentModelID != persistentModelID else { continue }
            if let m = mother, other.mother?.persistentModelID == m.persistentModelID {
                add(other)
                continue
            }
            if let f = father, other.father?.persistentModelID == f.persistentModelID {
                add(other)
            }
        }

        return result.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Whether `other` shares this person’s mother or father.
    func sharesParent(with other: FamilyPerson) -> Bool {
        if let m = mother, other.mother?.persistentModelID == m.persistentModelID { return true }
        if let f = father, other.father?.persistentModelID == f.persistentModelID { return true }
        return false
    }
}

// MARK: - Shared family photos (album in Family tab)

@Model
final class FamilyGroupPhoto {
    var caption: String = ""
    var sortOrder: Int = 0
    var addedAt: Date = Date(timeIntervalSince1970: 0)
    @Attribute(.externalStorage)
    var imageData: Data?

    init(caption: String = "", sortOrder: Int = 0, addedAt: Date = Date(), imageData: Data? = nil) {
        self.caption = caption
        self.sortOrder = sortOrder
        self.addedAt = addedAt
        self.imageData = imageData
    }
}

// MARK: - Family tree birthdays (annual, aligned with `FamilyEvent` birthday rules)

extension FamilyPerson {
    /// Next annual birthday (month/day from `birthDate`).
    func nextBirthdayOccurrence(after afterDate: Date) -> Date? {
        guard let birthDate = birthDate else { return nil }
        let cal = Calendar.current
        var match = DateComponents()
        match.month = cal.component(.month, from: birthDate)
        match.day = cal.component(.day, from: birthDate)
        match.hour = 0
        match.minute = 0
        match.second = 0
        if let next = cal.nextDate(after: afterDate.addingTimeInterval(-1), matching: match, matchingPolicy: .nextTime) {
            return cal.startOfDay(for: next)
        }
        return cal.startOfDay(for: birthDate)
    }

    /// Celebration date in the same calendar month as `monthStart` (Feb 29 → Feb 28 in non-leap years).
    func birthdayOccurrence(inMonthContaining monthStart: Date) -> Date? {
        guard let birthDate = birthDate else { return nil }
        let cal = Calendar.current
        let targetMonth = cal.component(.month, from: monthStart)
        let m = cal.component(.month, from: birthDate)
        guard m == targetMonth else { return nil }
        let y = cal.component(.year, from: monthStart)
        let d = cal.component(.day, from: birthDate)
        var dc = DateComponents(year: y, month: m, day: d)
        let base: Date?
        if let b = cal.date(from: dc) {
            base = b
        } else if m == 2 && d == 29 {
            dc.day = 28
            base = cal.date(from: dc)
        } else {
            base = nil
        }
        guard let base else { return nil }
        return cal.startOfDay(for: base)
    }

    /// Celebration date in the given calendar year.
    func birthdayOccurrence(inYear year: Int) -> Date? {
        guard let birthDate = birthDate else { return nil }
        let cal = Calendar.current
        let m = cal.component(.month, from: birthDate)
        guard let monthStart = cal.date(from: DateComponents(year: year, month: m, day: 1)) else { return nil }
        return birthdayOccurrence(inMonthContaining: monthStart)
    }

    /// Whole days until the next birthday (0 = today).
    func daysUntilNextBirthday(after afterDate: Date = Date()) -> Int? {
        guard let next = nextBirthdayOccurrence(after: afterDate) else { return nil }
        let cal = Calendar.current
        let from = cal.startOfDay(for: afterDate)
        return cal.dateComponents([.day], from: from, to: next).day
    }

    /// Age on the celebration day (year of day minus birth year).
    func ageOnBirthday(onCelebrationDay day: Date) -> Int? {
        guard let birthDate = birthDate else { return nil }
        let cal = Calendar.current
        let birthYear = cal.component(.year, from: birthDate)
        let dayYear = cal.component(.year, from: day)
        return dayYear - birthYear
    }
}

// MARK: - Holidays (trip history, planning, family chat)

@Model
final class HolidayTrip {
    var tripName: String = ""
    var startDate: Date = Date(timeIntervalSince1970: 0)
    var endDate: Date = Date(timeIntervalSince1970: 0)
    /// Free-form trip notes (plans, reminders, memories).
    var notes: String = ""

    /// Primary airline for the trip (optional).
    var airlineName: String = ""
    /// Booking / PNR / confirmation reference (flights, package, etc.).
    var bookingReference: String = ""
    /// Main hotel, rental, or where you’re staying.
    var mainAccommodation: String = ""

    @Attribute(.externalStorage)
    var coverImageData: Data?
    /// Place label from “city for cover photo” map search—used for the holiday world map pin title.
    var coverPlaceName: String = ""
    /// Coordinates from that same search; (0,0) means unset (world map falls back to geocoding `coverPlaceName`, then main stay / trip name).
    var coverLatitude: Double = 0
    var coverLongitude: Double = 0

    @Relationship(deleteRule: .cascade, inverse: \HolidayDestination.trip)
    var destinations: [HolidayDestination]? = []

    @Relationship(deleteRule: .cascade, inverse: \HolidayTripParticipant.trip)
    var participants: [HolidayTripParticipant]? = []

    init(
        tripName: String = "",
        startDate: Date = Date(timeIntervalSince1970: 0),
        endDate: Date = Date(timeIntervalSince1970: 0),
        notes: String = "",
        airlineName: String = "",
        bookingReference: String = "",
        mainAccommodation: String = "",
        coverImageData: Data? = nil,
        coverPlaceName: String = "",
        coverLatitude: Double = 0,
        coverLongitude: Double = 0,
        destinations: [HolidayDestination] = [],
        participants: [HolidayTripParticipant] = []
    ) {
        self.tripName = tripName
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.airlineName = airlineName
        self.bookingReference = bookingReference
        self.mainAccommodation = mainAccommodation
        self.coverImageData = coverImageData
        self.coverPlaceName = coverPlaceName
        self.coverLatitude = coverLatitude
        self.coverLongitude = coverLongitude
        self.destinations = destinations
        self.participants = participants
    }

    /// True when the trip’s last calendar day is before today (fully completed).
    var isPastTrip: Bool {
        Calendar.current.startOfDay(for: endDate) < Calendar.current.startOfDay(for: Date())
    }
}

/// Someone who joined a past or planned holiday trip (display name + optional family-role tag for the UI).
@Model
final class HolidayTripParticipant {
    var displayName: String = ""
    /// Short label shown under the name (e.g. Mom, Teen, Guest).
    var roleTag: String = ""
    var sortOrder: Int = 0

    var trip: HolidayTrip?

    init(
        displayName: String = "",
        roleTag: String = "",
        sortOrder: Int = 0,
        trip: HolidayTrip? = nil
    ) {
        self.displayName = displayName
        self.roleTag = roleTag
        self.sortOrder = sortOrder
        self.trip = trip
    }
}

@Model
final class HolidayDestination {
    var locationName: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var arrivalDate: Date = Date(timeIntervalSince1970: 0)
    var departureDate: Date = Date(timeIntervalSince1970: 0)
    var activities: String = ""

    var trip: HolidayTrip?

    init(
        locationName: String = "",
        latitude: Double = 0,
        longitude: Double = 0,
        arrivalDate: Date = Date(timeIntervalSince1970: 0),
        departureDate: Date = Date(timeIntervalSince1970: 0),
        activities: String = "",
        trip: HolidayTrip? = nil
    ) {
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.arrivalDate = arrivalDate
        self.departureDate = departureDate
        self.activities = activities
        self.trip = trip
    }
}

/// The four family members who vote on vacation ideas (Ideas tab). All must vote thumbs-up for a unanimous “let’s do it.”
enum HolidayFamilyVoter: String, CaseIterable, Identifiable, Sendable {
    case pappa = "Pappa"
    case mamma = "Mamma"
    case cc = "CC"
    case herman = "Herman"

    var id: String { rawValue }
}

@Model
final class VacationIdea {
    var proposedDestination: String = ""
    var proposedDates: String = ""
    var notes: String = ""
    /// JSON-encoded array of unique voter names (`["Pappa","Mamma"]`)—one vote per person.
    var voterNamesJSON: String = "[]"
    @Attribute(.externalStorage)
    var coverImageData: Data?
    /// Filled via MapKit lookup when proposing; (0,0) means not shown on the world map.
    var latitude: Double = 0
    var longitude: Double = 0

    init(
        proposedDestination: String = "",
        proposedDates: String = "",
        notes: String = "",
        voterNamesJSON: String = "[]",
        coverImageData: Data? = nil,
        latitude: Double = 0,
        longitude: Double = 0
    ) {
        self.proposedDestination = proposedDestination
        self.proposedDates = proposedDates
        self.notes = notes
        self.voterNamesJSON = voterNamesJSON
        self.coverImageData = coverImageData
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Decoded, unique, sorted voter names.
    func parsedVoterNames() -> [String] {
        guard let data = voterNamesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        let trimmed = decoded.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Array(Set(trimmed)).sorted()
    }

    var voteCount: Int { parsedVoterNames().count }

    func hasVoted(name: String) -> Bool {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        return parsedVoterNames().contains { $0.caseInsensitiveCompare(t) == .orderedSame }
    }

    /// Adds or removes this person’s vote (at most one per name).
    func toggleVote(for name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var names = parsedVoterNames()
        if let i = names.firstIndex(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
            names.remove(at: i)
        } else {
            names.append(t)
        }
        names.sort()
        if let data = try? JSONEncoder().encode(names),
           let s = String(data: data, encoding: .utf8)
        {
            voterNamesJSON = s
        }
    }

    /// `true` when Pappa, Mamma, CC, and Herman have all voted thumbs-up on this idea.
    var hasUnanimousFamilyVotes: Bool {
        let required = Set(HolidayFamilyVoter.allCases.map { $0.rawValue.lowercased() })
        let voted = Set(parsedVoterNames().map { $0.lowercased() })
        return required.isSubset(of: voted)
    }
}

@Model
final class HolidayChatMessage {
    var senderName: String = ""
    var messageText: String = ""
    var timestamp: Date = Date(timeIntervalSince1970: 0)
    /// Set when the sender changes the text after posting.
    var editedAt: Date?

    init(
        senderName: String = "",
        messageText: String = "",
        timestamp: Date = Date(timeIntervalSince1970: 0),
        editedAt: Date? = nil
    ) {
        self.senderName = senderName
        self.messageText = messageText
        self.timestamp = timestamp
        self.editedAt = editedAt
    }
}
