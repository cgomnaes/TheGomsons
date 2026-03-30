//
//  Models.swift
//  TheGomsons
//

import Foundation
import SwiftData

// MARK: - Inventory

enum InventoryCategory: String, Codable, CaseIterable, Sendable {
    case diyTools
    case downhillSkis
    case telemarkSkis
    case crossCountrySkis
    case tennis
    case golf
    case other

    var displayTitle: String {
        switch self {
        case .diyTools: "DIY tools"
        case .downhillSkis: "Downhill skis"
        case .telemarkSkis: "Telemark skis"
        case .crossCountrySkis: "Cross-country skis"
        case .tennis: "Tennis"
        case .golf: "Golf"
        case .other: "Other"
        }
    }
}

// MARK: - Location

enum LocationKind: String, Codable, CaseIterable, Sendable {
    case lived
    case visited
}

// MARK: - Property

enum PropertyKind: String, Codable, CaseIterable, Sendable {
    case singleFamily
    case condo
    case apartment
    case townhouse
    case vacation
    case land
    case other

    var displayTitle: String {
        switch self {
        case .singleFamily: "Single-family"
        case .condo: "Condo"
        case .apartment: "Apartment"
        case .townhouse: "Townhouse"
        case .vacation: "Vacation"
        case .land: "Land"
        case .other: "Other"
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
        case .electrician: "Electrician"
        case .plumber: "Plumber"
        case .handyman: "Handyman"
        case .snowPlougher: "Snow plougher"
        case .carpenter: "Carpenter"
        case .painter: "Painter"
        case .landscaper: "Landscaper"
        case .locksmith: "Locksmith"
        case .other: "Other"
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
        case .electricity: "Electricity"
        case .gas: "Gas"
        case .water: "Water"
        case .internet: "Internet"
        case .publicServices: "Public services"
        case .insurance: "Insurance"
        case .other: "Other"
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
    var livingAreaSqFt: Int = 0
    var yearBuilt: Int = 0
    var parcelOrTaxId: String = ""
    var insuranceCarrier: String = ""
    var insurancePolicyNumber: String = ""
    var utilitiesNotes: String = ""

    // MARK: Access & home systems (high-signal “smart” fields)
    var alarmOrSecurityCode: String = ""
    var gateOrAccessCode: String = ""
    var waterShutoffLocation: String = ""
    var hvacNotes: String = ""
    var trashAndRecyclingSchedule: String = ""
    var parkingNotes: String = ""
    var smartHomeNotes: String = ""

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
        parcelOrTaxId: String = "",
        insuranceCarrier: String = "",
        insurancePolicyNumber: String = "",
        utilitiesNotes: String = "",
        alarmOrSecurityCode: String = "",
        gateOrAccessCode: String = "",
        waterShutoffLocation: String = "",
        hvacNotes: String = "",
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
        self.parcelOrTaxId = parcelOrTaxId
        self.insuranceCarrier = insuranceCarrier
        self.insurancePolicyNumber = insurancePolicyNumber
        self.utilitiesNotes = utilitiesNotes
        self.alarmOrSecurityCode = alarmOrSecurityCode
        self.gateOrAccessCode = gateOrAccessCode
        self.waterShutoffLocation = waterShutoffLocation
        self.hvacNotes = hvacNotes
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
    /// Compact “3 BR · 2 BA · 1,800 sq ft” line for list rows; `nil` if nothing set.
    var formattedBedBathSqft: String? {
        var parts: [String] = []
        if bedrooms > 0 {
            parts.append("\(bedrooms) BR")
        }
        if bathrooms > 0 {
            parts.append(String(format: "%g BA", bathrooms))
        }
        if livingAreaSqFt > 0 {
            parts.append("\(livingAreaSqFt.formatted(.number.grouping(.automatic))) sq ft")
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

    var property: Property?

    init(
        name: String = "",
        category: InventoryCategory = InventoryCategory.other,
        purchaseDate: Date = Date(timeIntervalSince1970: 0),
        warrantyExpiry: Date = Date(timeIntervalSince1970: 0),
        estimatedValue: Double = 0,
        currentRetailPrice: Double = 0,
        property: Property? = nil
    ) {
        self.name = name
        self.category = category
        self.purchaseDate = purchaseDate
        self.warrantyExpiry = warrantyExpiry
        self.estimatedValue = estimatedValue
        self.currentRetailPrice = currentRetailPrice
        self.property = property
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
    var ingredients: [String] = []
    var instructions: String = ""
    var prepTime: TimeInterval = 0

    init(
        title: String = "",
        ingredients: [String] = [],
        instructions: String = "",
        prepTime: TimeInterval = 0
    ) {
        self.title = title
        self.ingredients = ingredients
        self.instructions = instructions
        self.prepTime = prepTime
    }
}

@Model
final class FamilyEvent {
    var title: String = ""
    var date: Date = Date(timeIntervalSince1970: 0)
    var location: String = ""
    var assignedTo: String = ""

    init(
        title: String = "",
        date: Date = Date(timeIntervalSince1970: 0),
        location: String = "",
        assignedTo: String = ""
    ) {
        self.title = title
        self.date = date
        self.location = location
        self.assignedTo = assignedTo
    }
}

// MARK: - Holidays (trip history, planning, family chat)

@Model
final class HolidayTrip {
    var tripName: String = ""
    var startDate: Date = Date(timeIntervalSince1970: 0)
    var endDate: Date = Date(timeIntervalSince1970: 0)

    @Attribute(.externalStorage)
    var coverImageData: Data?

    @Relationship(deleteRule: .cascade, inverse: \HolidayDestination.trip)
    var destinations: [HolidayDestination]? = []

    @Relationship(deleteRule: .cascade, inverse: \HolidayTripParticipant.trip)
    var participants: [HolidayTripParticipant]? = []

    init(
        tripName: String = "",
        startDate: Date = Date(timeIntervalSince1970: 0),
        endDate: Date = Date(timeIntervalSince1970: 0),
        coverImageData: Data? = nil,
        destinations: [HolidayDestination] = [],
        participants: [HolidayTripParticipant] = []
    ) {
        self.tripName = tripName
        self.startDate = startDate
        self.endDate = endDate
        self.coverImageData = coverImageData
        self.destinations = destinations
        self.participants = participants
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

@Model
final class VacationIdea {
    var proposedDestination: String = ""
    var proposedDates: String = ""
    var notes: String = ""
    var upvotes: Int = 0
    /// Filled via MapKit lookup when proposing; (0,0) means not shown on the world map.
    var latitude: Double = 0
    var longitude: Double = 0

    init(
        proposedDestination: String = "",
        proposedDates: String = "",
        notes: String = "",
        upvotes: Int = 0,
        latitude: Double = 0,
        longitude: Double = 0
    ) {
        self.proposedDestination = proposedDestination
        self.proposedDates = proposedDates
        self.notes = notes
        self.upvotes = upvotes
        self.latitude = latitude
        self.longitude = longitude
    }
}

@Model
final class HolidayChatMessage {
    var senderName: String = ""
    var messageText: String = ""
    var timestamp: Date = Date(timeIntervalSince1970: 0)

    init(
        senderName: String = "",
        messageText: String = "",
        timestamp: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.senderName = senderName
        self.messageText = messageText
        self.timestamp = timestamp
    }
}
