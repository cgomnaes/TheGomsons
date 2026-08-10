//
//  PropertiesCSVImport.swift
//  TheGomsons
//
//  UTF-8 CSV for Google Sheets → app import. One row per property; optional related
//  columns (contact*, emergency*, contractor*, service*). Matching `name` upserts.
//

import Foundation
import SwiftData

enum PropertiesCSVImport {

    /// Exact header (order) for the bundled / shareable template.
    static let templateHeaderLine = [
        "name",
        "address",
        "kind",
        "tenure",
        "bedrooms",
        "bathrooms",
        "living_area_m2",
        "year_built",
        "wifi_network",
        "wifi_password",
        "emergency_notes",
        "insurance_carrier",
        "insurance_policy_number",
        "utilities_notes",
        "landlord_or_owner",
        "rental_company",
        "rental_company_phone",
        "rental_company_email",
        "deposit",
        "monthly_rent",
        "lease_start",
        "lease_end",
        "rental_contract_ref",
        "rental_contract_notes",
        "alarm_or_security_code",
        "gate_or_access_code",
        "water_shutoff_location",
        "trash_and_recycling_schedule",
        "parking_notes",
        "smart_home_notes",
        "contact_name",
        "contact_role",
        "contact_phone",
        "contact_email",
        "contact_notes",
        "contact_is_primary",
        "contact2_name",
        "contact2_role",
        "contact2_phone",
        "contact2_email",
        "contact2_notes",
        "contact2_is_primary",
        "emergency_label",
        "emergency_phone",
        "emergency2_label",
        "emergency2_phone",
        "contractor_name",
        "contractor_trade",
        "contractor_phone",
        "contractor_email",
        "contractor_website",
        "contractor_notes",
        "contractor2_name",
        "contractor2_trade",
        "contractor2_phone",
        "contractor2_email",
        "contractor2_website",
        "contractor2_notes",
        "service_company",
        "service_kind",
        "service_account",
        "service_phone",
        "service_email",
        "service_website",
        "service_notes",
        "service2_company",
        "service2_kind",
        "service2_account",
        "service2_phone",
        "service2_email",
        "service2_website",
        "service2_notes",
    ].joined(separator: ",")

    static var templateFileContents: String {
        let samples: [[String]] = [
            sampleRow(
                name: "Marbella Villa",
                address: "Calle Example 12, Marbella",
                kind: "house",
                bedrooms: "4",
                bathrooms: "3.5",
                area: "220",
                year: "1998",
                wifi: "MarbellaGuest",
                wifiPass: "changeme",
                emergencyNotes: "Breaker panel in garage; first aid kit in kitchen",
                insurance: "Tryg",
                policy: "POL-12345",
                utilities: "Electric: Endesa account in folder",
                trash: "Tue/Fri pickup; bins by gate",
                parking: "2 spots in driveway",
                contactName: "Ada Gomnaes",
                contactRole: "Owner",
                contactPhone: "+47 900 00 000",
                contactEmail: "ada@example.com",
                contactPrimary: "yes",
                contact2Name: "Local caretaker",
                contact2Role: "Caretaker",
                contact2Phone: "+34 600 00 000",
                contact2Primary: "yes",
                emergencyLabel: "Emergency",
                emergencyPhone: "112",
                emergency2Label: "Police",
                emergency2Phone: "091",
                contractorName: "Juan Electric",
                contractorTrade: "electrician",
                contractorPhone: "+34 611 00 000",
                contractorNotes: "Preferred for cabin trips",
                serviceCompany: "Aqua Marbella",
                serviceKind: "water",
                serviceAccount: "ACC-7788",
                servicePhone: "+34 952 00 000",
                service2Company: "Endesa",
                service2Kind: "electricity",
                service2Account: "END-4411"
            ),
            sampleRow(
                name: "Oslo Apartment",
                address: "Storgata 1, Oslo",
                kind: "apartment",
                tenure: "owned",
                bedrooms: "2",
                bathrooms: "1",
                area: "78",
                year: "2012",
                wifi: "OsloHome",
                insurance: "If",
                policy: "POL-OSL-9",
                emergencyLabel: "Fire",
                emergencyPhone: "110",
                service2Company: "Telenor",
                service2Kind: "internet",
                service2Account: "MOB-55"
            ),
            sampleRow(
                name: "Bergen Student Flat",
                address: "Nygårdsgaten 10, Bergen",
                kind: "apartment",
                tenure: "rented",
                bedrooms: "1",
                bathrooms: "1",
                area: "42",
                year: "2005",
                wifi: "BergenFiber",
                wifiPass: "changeme",
                landlord: "Kari Hansen",
                rentalCompany: "Bergen Utleie AS",
                rentalCompanyPhone: "+47 55 00 00 00",
                rentalCompanyEmail: "drift@bergenutleie.example",
                deposit: "25 000 kr",
                monthlyRent: "12 500 kr",
                leaseStart: "2025-08-01",
                leaseEnd: "2026-07-31",
                rentalContractRef: "HU-2025-441",
                rentalContractNotes: "3 months notice; parking not included",
                contactName: "Vaktmester Ola",
                contactRole: "Caretaker",
                contactPhone: "+47 900 11 223",
                contactPrimary: "yes",
                contractorName: "Bergen VVS",
                contractorTrade: "plumber",
                contractorPhone: "+47 55 11 22 33",
                contractorNotes: "Use for leaks — landlord pays",
                serviceCompany: "BKK",
                serviceKind: "electricity",
                serviceAccount: "BKK-778"
            ),
        ]
        let header = templateHeaderLine
        let body = samples.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n")
        return header + "\n" + body + "\n"
    }

    /// Builds one template row aligned with `templateHeaderLine` column order.
    private static func sampleRow(
        name: String = "",
        address: String = "",
        kind: String = "",
        tenure: String = "owned",
        bedrooms: String = "",
        bathrooms: String = "",
        area: String = "",
        year: String = "",
        wifi: String = "",
        wifiPass: String = "",
        emergencyNotes: String = "",
        insurance: String = "",
        policy: String = "",
        utilities: String = "",
        landlord: String = "",
        rentalCompany: String = "",
        rentalCompanyPhone: String = "",
        rentalCompanyEmail: String = "",
        deposit: String = "",
        monthlyRent: String = "",
        leaseStart: String = "",
        leaseEnd: String = "",
        rentalContractRef: String = "",
        rentalContractNotes: String = "",
        alarm: String = "",
        gate: String = "",
        water: String = "",
        trash: String = "",
        parking: String = "",
        smart: String = "",
        contactName: String = "",
        contactRole: String = "",
        contactPhone: String = "",
        contactEmail: String = "",
        contactNotes: String = "",
        contactPrimary: String = "",
        contact2Name: String = "",
        contact2Role: String = "",
        contact2Phone: String = "",
        contact2Email: String = "",
        contact2Notes: String = "",
        contact2Primary: String = "",
        emergencyLabel: String = "",
        emergencyPhone: String = "",
        emergency2Label: String = "",
        emergency2Phone: String = "",
        contractorName: String = "",
        contractorTrade: String = "",
        contractorPhone: String = "",
        contractorEmail: String = "",
        contractorWebsite: String = "",
        contractorNotes: String = "",
        contractor2Name: String = "",
        contractor2Trade: String = "",
        contractor2Phone: String = "",
        contractor2Email: String = "",
        contractor2Website: String = "",
        contractor2Notes: String = "",
        serviceCompany: String = "",
        serviceKind: String = "",
        serviceAccount: String = "",
        servicePhone: String = "",
        serviceEmail: String = "",
        serviceWebsite: String = "",
        serviceNotes: String = "",
        service2Company: String = "",
        service2Kind: String = "",
        service2Account: String = "",
        service2Phone: String = "",
        service2Email: String = "",
        service2Website: String = "",
        service2Notes: String = ""
    ) -> [String] {
        [
            name, address, kind, tenure, bedrooms, bathrooms, area, year,
            wifi, wifiPass, emergencyNotes, insurance, policy, utilities,
            landlord, rentalCompany, rentalCompanyPhone, rentalCompanyEmail,
            deposit, monthlyRent, leaseStart, leaseEnd, rentalContractRef, rentalContractNotes,
            alarm, gate, water, trash, parking, smart,
            contactName, contactRole, contactPhone, contactEmail, contactNotes, contactPrimary,
            contact2Name, contact2Role, contact2Phone, contact2Email, contact2Notes, contact2Primary,
            emergencyLabel, emergencyPhone, emergency2Label, emergency2Phone,
            contractorName, contractorTrade, contractorPhone, contractorEmail, contractorWebsite, contractorNotes,
            contractor2Name, contractor2Trade, contractor2Phone, contractor2Email, contractor2Website, contractor2Notes,
            serviceCompany, serviceKind, serviceAccount, servicePhone, serviceEmail, serviceWebsite, serviceNotes,
            service2Company, service2Kind, service2Account, service2Phone, service2Email, service2Website, service2Notes,
        ]
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    /// Short guide shown in the import UI (also works as Google Sheets workflow).
    static var googleSheetsInstructions: String {
        String(localized: "properties.import_sheets_steps")
    }

    struct Result: Sendable {
        var added: Int
        var updated: Int
        var contactsAdded: Int
        var emergenciesAdded: Int
        var contractorsAdded: Int
        var servicesAdded: Int
        var warnings: [String]
    }

    /// Imports property rows. Empty `name` skipped. Existing properties (same name, case/diacritic-insensitive) are updated.
    static func importCSV(
        data: Data,
        modelContext: ModelContext,
        existingProperties: [Property]
    ) throws -> Result {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        else {
            throw ImportError.notUTF8
        }
        // Strip UTF-8 BOM from Google Sheets / Excel exports.
        let cleaned = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyFile }

        let (_, rows) = parseCSVRows(trimmed)
        guard rows.count >= 2 else { throw ImportError.noDataRows }

        let header = rows[0].map { normalizeHeaderKey($0) }
        guard let nameIdx = header.firstIndex(of: "name") else {
            throw ImportError.missingNameColumn
        }

        func col(_ keys: String...) -> Int? {
            for k in keys {
                if let i = header.firstIndex(of: k) { return i }
            }
            return nil
        }

        func cell(_ cells: [String], _ idx: Int?) -> String {
            guard let idx, idx < cells.count else { return "" }
            return cells[idx].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let addressIdx = col("address", "street", "location")
        let kindIdx = col("kind", "type", "property_kind", "property_type")
        let tenureIdx = col("tenure", "ownership", "owned_or_rented", "rental_status")
        let bedroomsIdx = col("bedrooms", "beds", "br")
        let bathroomsIdx = col("bathrooms", "baths", "ba")
        let areaIdx = col("living_area_m2", "living_area", "area_m2", "sqm", "m2", "livingareasqft")
        let yearIdx = col("year_built", "year", "built")
        let wifiNetIdx = col("wifi_network", "wifi", "ssid", "wifi_ssid")
        let wifiPassIdx = col("wifi_password", "wifi_pass", "wifi_pwd")
        let emergencyNotesIdx = col("emergency_notes", "emergency_info", "safety_notes")
        let insuranceIdx = col("insurance_carrier", "insurance", "insurance_company")
        let policyIdx = col("insurance_policy_number", "policy_number", "insurance_policy")
        let utilitiesIdx = col("utilities_notes", "utilities")
        let landlordIdx = col("landlord_or_owner", "landlord", "owner", "owner_name")
        let rentalCompanyIdx = col("rental_company", "management_company", "agency")
        let rentalCompanyPhoneIdx = col("rental_company_phone", "agency_phone", "management_phone")
        let rentalCompanyEmailIdx = col("rental_company_email", "agency_email", "management_email")
        let depositIdx = col("deposit", "deposit_amount", "security_deposit")
        let monthlyRentIdx = col("monthly_rent", "rent", "rent_amount")
        let leaseStartIdx = col("lease_start", "lease_start_date", "contract_start")
        let leaseEndIdx = col("lease_end", "lease_end_date", "contract_end")
        let rentalContractRefIdx = col("rental_contract_ref", "contract_ref", "contract_number")
        let rentalContractNotesIdx = col("rental_contract_notes", "contract_notes", "lease_notes")
        let alarmIdx = col("alarm_or_security_code", "alarm_code", "security_code")
        let gateIdx = col("gate_or_access_code", "gate_code", "access_code")
        let waterIdx = col("water_shutoff_location", "water_shutoff")
        let trashIdx = col("trash_and_recycling_schedule", "trash_schedule", "recycling")
        let parkingIdx = col("parking_notes", "parking")
        let smartIdx = col("smart_home_notes", "smart_home")

        var byKey: [String: Property] = [:]
        for p in existingProperties {
            let k = normalizePropertyNameKey(p.name)
            guard !k.isEmpty else { continue }
            if byKey[k] == nil { byKey[k] = p }
        }

        var warnings: [String] = []
        var added = 0
        var updated = 0
        var contactsAdded = 0
        var emergenciesAdded = 0
        var contractorsAdded = 0
        var servicesAdded = 0

        let contactSlots = relatedSlots(in: header, base: "contact", fields: ["name", "role", "phone", "email", "notes", "is_primary"])
        let emergencySlots = relatedSlots(in: header, base: "emergency", fields: ["label", "phone", "phone_number"])
        let contractorSlots = relatedSlots(in: header, base: "contractor", fields: ["name", "trade", "phone", "email", "website", "notes"])
        let serviceSlots = relatedSlots(in: header, base: "service", fields: ["company", "company_name", "kind", "account", "account_number", "phone", "email", "website", "notes"])

        for (lineIndex, cells) in rows.dropFirst().enumerated() {
            let rowNumber = lineIndex + 2
            guard cells.count > nameIdx else { continue }
            let rawName = cells[nameIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizePropertyNameKey(rawName)
            if key.isEmpty {
                if cells.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    continue
                }
                warnings.append(String(format: String(localized: "properties.import_warn_empty_name_fmt"), rowNumber))
                continue
            }

            let isNew: Bool
            let property: Property
            if let existing = byKey[key] {
                property = existing
                isNew = false
            } else {
                property = Property(name: rawName)
                modelContext.insert(property)
                byKey[key] = property
                isNew = true
            }

            // Scalars: only overwrite when the CSV cell is non-empty (keeps hand-entered extras on update).
            let address = cell(cells, addressIdx)
            if !address.isEmpty { property.address = address }

            let kindRaw = cell(cells, kindIdx)
            if !kindRaw.isEmpty {
                if let kind = parsePropertyKind(kindRaw) {
                    property.propertyKind = kind
                } else {
                    warnings.append(String(format: String(localized: "properties.import_warn_kind_fmt"), kindRaw, rowNumber))
                }
            }

            let tenureRaw = cell(cells, tenureIdx)
            if !tenureRaw.isEmpty {
                if let tenure = parsePropertyTenure(tenureRaw) {
                    property.tenure = tenure
                } else {
                    warnings.append(String(format: String(localized: "properties.import_warn_tenure_fmt"), tenureRaw, rowNumber))
                }
            }

            let bedroomsRaw = cell(cells, bedroomsIdx)
            if !bedroomsRaw.isEmpty {
                property.bedrooms = parseInt(bedroomsRaw) ?? property.bedrooms
            }
            let bathroomsRaw = cell(cells, bathroomsIdx)
            if !bathroomsRaw.isEmpty {
                property.bathrooms = parseDouble(bathroomsRaw) ?? property.bathrooms
            }
            let areaRaw = cell(cells, areaIdx)
            if !areaRaw.isEmpty {
                property.livingAreaSqFt = parseInt(areaRaw) ?? property.livingAreaSqFt
            }
            let yearRaw = cell(cells, yearIdx)
            if !yearRaw.isEmpty {
                property.yearBuilt = parseYear(yearRaw) ?? property.yearBuilt
            }

            applyIfPresent(cell(cells, wifiNetIdx)) { property.wifiNetwork = $0 }
            applyIfPresent(cell(cells, wifiPassIdx)) { property.wifiPassword = $0 }
            applyIfPresent(cell(cells, emergencyNotesIdx)) { property.emergencyNotes = $0 }
            applyIfPresent(cell(cells, insuranceIdx)) { property.insuranceCarrier = $0 }
            applyIfPresent(cell(cells, policyIdx)) { property.insurancePolicyNumber = $0 }
            applyIfPresent(cell(cells, utilitiesIdx)) { property.utilitiesNotes = $0 }
            applyIfPresent(cell(cells, landlordIdx)) { property.landlordOrOwnerName = $0 }
            applyIfPresent(cell(cells, rentalCompanyIdx)) { property.rentalCompanyName = $0 }
            applyIfPresent(cell(cells, rentalCompanyPhoneIdx)) { property.rentalCompanyPhone = $0 }
            applyIfPresent(cell(cells, rentalCompanyEmailIdx)) { property.rentalCompanyEmail = $0 }
            applyIfPresent(cell(cells, depositIdx)) { property.depositAmount = $0 }
            applyIfPresent(cell(cells, monthlyRentIdx)) { property.monthlyRent = $0 }
            applyIfPresent(cell(cells, rentalContractRefIdx)) { property.rentalContractReference = $0 }
            applyIfPresent(cell(cells, rentalContractNotesIdx)) { property.rentalContractNotes = $0 }
            let leaseStartRaw = cell(cells, leaseStartIdx)
            if !leaseStartRaw.isEmpty {
                property.leaseStartDate = parseLeaseDate(leaseStartRaw) ?? property.leaseStartDate
            }
            let leaseEndRaw = cell(cells, leaseEndIdx)
            if !leaseEndRaw.isEmpty {
                property.leaseEndDate = parseLeaseDate(leaseEndRaw) ?? property.leaseEndDate
            }
            applyIfPresent(cell(cells, alarmIdx)) { property.alarmOrSecurityCode = $0 }
            applyIfPresent(cell(cells, gateIdx)) { property.gateOrAccessCode = $0 }
            applyIfPresent(cell(cells, waterIdx)) { property.waterShutoffLocation = $0 }
            applyIfPresent(cell(cells, trashIdx)) { property.trashAndRecyclingSchedule = $0 }
            applyIfPresent(cell(cells, parkingIdx)) { property.parkingNotes = $0 }
            applyIfPresent(cell(cells, smartIdx)) { property.smartHomeNotes = $0 }

            if isNew { added += 1 } else { updated += 1 }

            // Related rows
            for slot in contactSlots {
                let cName = cell(cells, slot["name"])
                let cPhone = cell(cells, slot["phone"])
                let cEmail = cell(cells, slot["email"])
                guard !cName.isEmpty || !cPhone.isEmpty || !cEmail.isEmpty else { continue }
                if contactAlreadyExists(on: property, name: cName, phone: cPhone, email: cEmail) { continue }
                let nextOrder = ((property.contacts ?? []).map(\.sortOrder).max() ?? -1) + 1
                let contact = PropertyContact(
                    name: cName.isEmpty ? String(localized: "property.contact") : cName,
                    role: cell(cells, slot["role"]),
                    phone: cPhone,
                    email: cEmail,
                    notes: cell(cells, slot["notes"]),
                    isPrimary: parseBool(cell(cells, slot["is_primary"])) || (nextOrder == 0),
                    sortOrder: nextOrder,
                    property: property
                )
                modelContext.insert(contact)
                if property.contacts == nil { property.contacts = [] }
                property.contacts?.append(contact)
                contactsAdded += 1
            }

            for slot in emergencySlots {
                let label = cell(cells, slot["label"])
                let phone = cell(cells, slot["phone"])
                let phoneAlt = cell(cells, slot["phone_number"])
                let number = phone.isEmpty ? phoneAlt : phone
                guard !label.isEmpty || !number.isEmpty else { continue }
                if emergencyAlreadyExists(on: property, label: label, phone: number) { continue }
                let nextOrder = ((property.emergencyLines ?? []).map(\.sortOrder).max() ?? -1) + 1
                let line = PropertyEmergencyLine(
                    label: label.isEmpty ? String(localized: "property.emergency") : label,
                    phoneNumber: number,
                    sortOrder: nextOrder,
                    property: property
                )
                modelContext.insert(line)
                if property.emergencyLines == nil { property.emergencyLines = [] }
                property.emergencyLines?.append(line)
                emergenciesAdded += 1
            }

            for slot in contractorSlots {
                let cName = cell(cells, slot["name"])
                guard !cName.isEmpty else { continue }
                let tradeRaw = cell(cells, slot["trade"])
                let trade = parseContractorTrade(tradeRaw)
                if !tradeRaw.isEmpty && trade == .other && normalizeHeaderKey(tradeRaw) != "other" {
                    warnings.append(String(format: String(localized: "properties.import_warn_trade_fmt"), tradeRaw, rowNumber))
                }
                let phone = cell(cells, slot["phone"])
                if contractorAlreadyExists(on: property, name: cName, phone: phone) { continue }
                let nextOrder = ((property.contractors ?? []).map(\.sortOrder).max() ?? -1) + 1
                let contractor = PropertyContractor(
                    name: cName,
                    trade: trade,
                    phone: phone,
                    email: cell(cells, slot["email"]),
                    website: cell(cells, slot["website"]),
                    notes: cell(cells, slot["notes"]),
                    sortOrder: nextOrder,
                    property: property
                )
                modelContext.insert(contractor)
                if property.contractors == nil { property.contractors = [] }
                property.contractors?.append(contractor)
                contractorsAdded += 1
            }

            for slot in serviceSlots {
                let company = cell(cells, slot["company"]).isEmpty
                    ? cell(cells, slot["company_name"])
                    : cell(cells, slot["company"])
                guard !company.isEmpty else { continue }
                let kindRaw = cell(cells, slot["kind"])
                let kind = parseServiceKind(kindRaw)
                if !kindRaw.isEmpty && kind == .other && normalizeHeaderKey(kindRaw) != "other" {
                    warnings.append(String(format: String(localized: "properties.import_warn_service_fmt"), kindRaw, rowNumber))
                }
                let account = cell(cells, slot["account"]).isEmpty
                    ? cell(cells, slot["account_number"])
                    : cell(cells, slot["account"])
                if serviceAlreadyExists(on: property, company: company, kind: kind) { continue }
                let nextOrder = ((property.serviceProviders ?? []).map(\.sortOrder).max() ?? -1) + 1
                let provider = PropertyServiceProvider(
                    companyName: company,
                    kind: kind,
                    accountNumber: account,
                    phone: cell(cells, slot["phone"]),
                    email: cell(cells, slot["email"]),
                    website: cell(cells, slot["website"]),
                    notes: cell(cells, slot["notes"]),
                    sortOrder: nextOrder,
                    property: property
                )
                modelContext.insert(provider)
                if property.serviceProviders == nil { property.serviceProviders = [] }
                property.serviceProviders?.append(provider)
                servicesAdded += 1
            }
        }

        try modelContext.save()
        return Result(
            added: added,
            updated: updated,
            contactsAdded: contactsAdded,
            emergenciesAdded: emergenciesAdded,
            contractorsAdded: contractorsAdded,
            servicesAdded: servicesAdded,
            warnings: warnings
        )
    }

    // MARK: - Errors

    private enum ImportError: LocalizedError {
        case notUTF8
        case emptyFile
        case noDataRows
        case missingNameColumn

        var errorDescription: String? {
            switch self {
            case .notUTF8: String(localized: "properties.import_err_utf8")
            case .emptyFile: String(localized: "properties.import_err_empty")
            case .noDataRows: String(localized: "properties.import_err_no_rows")
            case .missingNameColumn: String(localized: "properties.import_err_no_name")
            }
        }
    }

    // MARK: - Related column slots

    /// Finds groups like `contact_*`, `contact2_*`, `emergency_*` …
    private static func relatedSlots(
        in header: [String],
        base: String,
        fields: [String]
    ) -> [[String: Int]] {
        var prefixes: [String] = [base]
        // contact2, contact3, … emergency2 …
        for i in 2...6 {
            prefixes.append("\(base)\(i)")
        }
        var slots: [[String: Int]] = []
        for prefix in prefixes {
            var map: [String: Int] = [:]
            for field in fields {
                let key = "\(prefix)_\(field)"
                if let idx = header.firstIndex(of: key) {
                    map[field] = idx
                }
            }
            // Also accept bare `emergency_phone_number` already covered via fields list.
            if !map.isEmpty {
                slots.append(map)
            }
        }
        return slots
    }

    // MARK: - Dedup helpers

    private static func contactAlreadyExists(on property: Property, name: String, phone: String, email: String) -> Bool {
        let n = normalizePropertyNameKey(name)
        let p = normalizeLoose(phone)
        let e = normalizeLoose(email)
        return (property.contacts ?? []).contains { c in
            let cn = normalizePropertyNameKey(c.name)
            let cp = normalizeLoose(c.phone)
            let ce = normalizeLoose(c.email)
            if !n.isEmpty && cn == n { return true }
            if !p.isEmpty && cp == p { return true }
            if !e.isEmpty && ce == e { return true }
            return false
        }
    }

    private static func emergencyAlreadyExists(on property: Property, label: String, phone: String) -> Bool {
        let l = normalizeLoose(label)
        let p = normalizeLoose(phone)
        return (property.emergencyLines ?? []).contains { line in
            if !p.isEmpty && normalizeLoose(line.phoneNumber) == p { return true }
            if !l.isEmpty && normalizeLoose(line.label) == l && p.isEmpty { return true }
            return false
        }
    }

    private static func contractorAlreadyExists(on property: Property, name: String, phone: String) -> Bool {
        let n = normalizePropertyNameKey(name)
        let p = normalizeLoose(phone)
        return (property.contractors ?? []).contains { c in
            if normalizePropertyNameKey(c.name) == n { return true }
            if !p.isEmpty && normalizeLoose(c.phone) == p && !n.isEmpty { return true }
            return false
        }
    }

    private static func serviceAlreadyExists(on property: Property, company: String, kind: ServiceProviderKind) -> Bool {
        let n = normalizePropertyNameKey(company)
        return (property.serviceProviders ?? []).contains {
            normalizePropertyNameKey($0.companyName) == n && $0.kind == kind
        }
    }

    private static func applyIfPresent(_ value: String, _ apply: (String) -> Void) {
        guard !value.isEmpty else { return }
        apply(value)
    }

    // MARK: - Parsing enums / numbers

    private static func parsePropertyKind(_ raw: String) -> PropertyKind? {
        let key = compactKey(raw)
        switch key {
        case "house", "home", "villa", "singlefamily", "townhouse":
            return .house
        case "cabin", "cottage", "hytte", "vacation", "holidayhome":
            return .cabin
        case "apartment", "flat", "condo", "leilighet":
            return .apartment
        case "land", "lot", "tomt", "plot":
            return .land
        case "other", "annet":
            return .other
        default:
            return PropertyKind(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? PropertyKind(rawValue: key)
        }
    }

    private static func parsePropertyTenure(_ raw: String) -> PropertyTenure? {
        let key = compactKey(raw)
        switch key {
        case "owned", "own", "owner", "eiet", "eid":
            return .owned
        case "rented", "rent", "rental", "lease", "leased", "leid", "leie", "utleid":
            return .rented
        default:
            return PropertyTenure(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? PropertyTenure(rawValue: key)
        }
    }

    private static func parseLeaseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formats = ["yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy", "yyyy/MM/dd"]
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        for format in formats {
            parser.dateFormat = format
            if let date = parser.date(from: trimmed) {
                return Calendar.current.startOfDay(for: date)
            }
        }
        return nil
    }

    private static func parseContractorTrade(_ raw: String) -> ContractorTrade {
        let key = compactKey(raw)
        switch key {
        case "electrician", "elektriker", "electric": return .electrician
        case "plumber", "rorlegger", "rørlegger": return .plumber
        case "handyman", "vaktmester", "fixit": return .handyman
        case "snowplougher", "snowplower", "snow", "brøyting", "broyting": return .snowPlougher
        case "carpenter", "snekker": return .carpenter
        case "painter", "maler": return .painter
        case "landscaper", "garden", "gartner": return .landscaper
        case "locksmith", "lasersmed", "låsesmed": return .locksmith
        case "other", "annet", "": return .other
        default:
            return ContractorTrade(rawValue: raw) ?? ContractorTrade(rawValue: key) ?? .other
        }
    }

    private static func parseServiceKind(_ raw: String) -> ServiceProviderKind {
        let key = compactKey(raw)
        switch key {
        case "electricity", "electric", "strom", "strøm", "power": return .electricity
        case "gas", "gass": return .gas
        case "water", "vann": return .water
        case "internet", "wifi", "broadband", "bredband": return .internet
        case "publicservices", "public", "kommune", "municipality": return .publicServices
        case "insurance", "forsikring": return .insurance
        case "other", "annet", "": return .other
        default:
            return ServiceProviderKind(rawValue: raw) ?? ServiceProviderKind(rawValue: key) ?? .other
        }
    }

    private static func parseBool(_ raw: String) -> Bool {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "y", "yes", "true", "t", "ja", "primary":
            return true
        default:
            return false
        }
    }

    private static func parseInt(_ raw: String) -> Int? {
        let digits = raw.filter { $0.isNumber || $0 == "-" }
        return Int(digits)
    }

    private static func parseYear(_ raw: String) -> Int? {
        let digits = String(raw.filter(\.isNumber).prefix(4))
        guard let y = Int(digits), y > 0 else { return nil }
        return y
    }

    private static func parseDouble(_ raw: String) -> Double? {
        let normalized = raw
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(normalized)
    }

    private static func compactKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func normalizeLoose(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace }
    }

    private static func normalizePropertyNameKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let folded = trimmed.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func normalizeHeaderKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    // MARK: - CSV

    private static func parseCSVRows(_ text: String) -> (Character, [[String]]) {
        let lines = splitIntoLogicalLines(text)
        guard let first = lines.first else { return (",", []) }
        let delim: Character = preferredDelimiter(first)
        let rows = lines.map { parseLine($0, delimiter: delim) }
        return (delim, rows)
    }

    private static func splitIntoLogicalLines(_ text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        var inQuotes = false
        for ch in text {
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
            } else if (ch == "\n" || ch == "\r") && !inQuotes {
                if !current.isEmpty {
                    lines.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func preferredDelimiter(_ headerLine: String) -> Character {
        let commas = headerLine.filter { $0 == "," }.count
        let semis = headerLine.filter { $0 == ";" }.count
        return semis > commas ? ";" : ","
    }

    private static func parseLine(_ line: String, delimiter: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "\"" {
                let next = line.index(after: i)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    i = line.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if c == delimiter && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i = line.index(after: i)
        }
        result.append(current)
        return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
