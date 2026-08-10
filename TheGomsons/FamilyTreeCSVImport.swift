//
//  FamilyTreeCSVImport.swift
//  TheGomsons
//
//  UTF-8 CSV template: name, preferred_name, dob, relation, email, mobile, partner_name, partner_status, note, city, hobbies, deceased, death_date, sibling_names
//

import Foundation
import SwiftData

enum FamilyTreeCSVImport {

    /// Exact header (order) for the bundled template; columns may appear in any order in user files.
    static let templateHeaderLine =
        "name,preferred_name,dob,relation,email,mobile,partner_name,partner_status,note,city,hobbies,deceased,death_date,sibling_names"

    static var templateFileContents: String {
        """
        \(templateHeaderLine)
        Ada Gomnaes,Ada,1990-05-12,ourHousehold,ada@example.com,+47 900 00 000,Ola Gomnaes,married,,"Oslo","Hiking, cooking",,,
        Ola Gomnaes,,1988-03-01,ourHousehold,ola@example.com,+47 900 00 001,Ada Gomnaes,married,,"Oslo","Football, photography",,,
        Ingrid Berg,Ingrid,1960-11-20,myParentsLine,,+47 400 00 000,,,Mother,,"Bergen","Gardening",,,
        """
    }

    struct Result: Sendable {
        var added: Int
        var linkedPartners: Int
        var warnings: [String]
    }

    /// Imports rows from CSV/UTF-8 data. Skips blank names; warns on duplicate names (in file or already in the store).
    static func importCSV(data: Data, modelContext: ModelContext, existingPeople: [FamilyPerson]) throws -> Result {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportError.notUTF8
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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

        let dobIdx = col("dob", "date_of_birth", "birthdate", "birth_date")
        let preferredNameIdx = col("preferred_name", "nickname", "preferred", "goes_by")
        let relationIdx = col("relation", "branch")
        let emailIdx = col("email", "e_mail")
        let mobileIdx = col("mobile", "phone", "cell", "cellphone")
        let partnerIdx = col("partner_name", "partner", "spouse")
        let partnerStatusIdx = col("partner_status", "relationship_status", "status")
        let noteIdx = col("note", "notes", "comment")
        let cityIdx = col("city", "town", "place")
        let hobbiesIdx = col("hobbies", "hobby", "interests")
        let deceasedIdx = col("deceased", "is_deceased", "dead", "passed")
        let deathDateIdx = col("death_date", "dod", "date_of_death", "died")

        var warnings: [String] = []
        var byNormalizedName: [String: FamilyPerson] = [:]

        for p in existingPeople {
            let k = normalizePersonNameKey(p.name)
            guard !k.isEmpty else { continue }
            if byNormalizedName[k] == nil {
                byNormalizedName[k] = p
            }
        }

        var parsedRows: [(row: Int, name: String, partnerName: String, partnerStatus: PartnerRelationshipStatus?, siblingNames: [String])] = []
        var nextSort = (existingPeople.map(\.sortOrder).max() ?? 0) + 1

        let siblingNamesIdx = col("sibling_names", "siblings", "sibling")

        for (lineIndex, cells) in rows.dropFirst().enumerated() {
            let rowNumber = lineIndex + 2
            guard cells.count > nameIdx else { continue }
            let rawName = cells[nameIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizePersonNameKey(rawName)
            if key.isEmpty {
                if cells.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    continue
                }
                warnings.append(String(format: String(localized: "family_tree.import_warn_empty_name_fmt"), rowNumber))
                continue
            }
            if byNormalizedName[key] != nil {
                warnings.append(String(format: String(localized: "family_tree.import_warn_duplicate_fmt"), rawName))
                continue
            }

            let dobStr = dobIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let preferredName = preferredNameIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let relationStr = relationIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let email = emailIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let mobile = mobileIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let partnerRaw = partnerIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let partnerStatusRaw = partnerStatusIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let note = noteIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let city = cityIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let hobbies = hobbiesIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let deceasedRaw = deceasedIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let deathDateStr = deathDateIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let siblingNamesRaw = siblingNamesIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""

            let (branch, relationLabel) = parseRelationColumn(relationStr)
            let birth = parseDOB(dobStr)
            let parsedStatus = PartnerRelationshipStatus.parseCSV(partnerStatusRaw)
            let death = parseDOB(deathDateStr)
            let deceased = parseDeceasedFlag(deceasedRaw) || death != nil
            let siblingNames = parseSiblingNames(siblingNamesRaw)

            let person = FamilyPerson(
                name: rawName,
                preferredName: preferredName.trimmingCharacters(in: .whitespacesAndNewlines),
                birthDate: birth,
                notes: note,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                mobile: mobile.trimmingCharacters(in: .whitespacesAndNewlines),
                city: city.trimmingCharacters(in: .whitespacesAndNewlines),
                familyRelationLabel: relationLabel,
                hobbies: hobbies.trimmingCharacters(in: .whitespacesAndNewlines),
                partnerStatus: parsedStatus,
                isDeceased: deceased,
                deathDate: death,
                treeTier: 2,
                branch: branch,
                sortOrder: nextSort,
                includeBirthdayOnCalendar: birth != nil && !deceased
            )
            nextSort += 1
            if birth != nil && !deceased {
                FamilyCalendarNotifications.schedulePersonBirthday(person)
            }

            modelContext.insert(person)
            byNormalizedName[key] = person
            parsedRows.append((
                rowNumber,
                rawName,
                partnerRaw.trimmingCharacters(in: .whitespacesAndNewlines),
                parsedStatus,
                siblingNames
            ))
        }

        let added = parsedRows.count
        var linkedPartners = 0

        for (_, name, partnerName, status, _) in parsedRows {
            let selfKey = normalizePersonNameKey(name)
            let partnerKey = normalizePersonNameKey(partnerName)
            guard !partnerKey.isEmpty else { continue }
            guard let person = byNormalizedName[selfKey] else { continue }
            guard let partner = byNormalizedName[partnerKey] else {
                warnings.append(String(format: String(localized: "family_tree.import_warn_partner_fmt"), partnerName, name))
                continue
            }
            if person.persistentModelID == partner.persistentModelID { continue }
            if let ex = person.resolvedPartner, ex.persistentModelID == partner.persistentModelID {
                if let status {
                    person.partnerStatus = status
                    if partner.partnerStatus == nil { partner.partnerStatus = status }
                }
                continue
            }
            if person.resolvedPartner != nil || partner.resolvedPartner != nil {
                warnings.append(String(format: String(localized: "family_tree.import_warn_partner_busy_fmt"), name))
                continue
            }

            clearPartnerEdges(for: person)
            clearPartnerEdges(for: partner)
            person.partner = partner
            if let status {
                person.partnerStatus = status
                if partner.partnerStatus == nil {
                    partner.partnerStatus = status
                }
            }
            linkedPartners += 1
        }

        for (_, name, _, _, siblingNames) in parsedRows {
            guard !siblingNames.isEmpty else { continue }
            let selfKey = normalizePersonNameKey(name)
            guard let person = byNormalizedName[selfKey] else { continue }
            if person.siblings == nil { person.siblings = [] }
            for siblingName in siblingNames {
                let siblingKey = normalizePersonNameKey(siblingName)
                guard !siblingKey.isEmpty else { continue }
                guard let sibling = byNormalizedName[siblingKey] else {
                    warnings.append(
                        String(
                            format: String(localized: "family_tree.import_warn_sibling_fmt"),
                            siblingName,
                            name
                        )
                    )
                    continue
                }
                guard sibling.persistentModelID != person.persistentModelID else { continue }
                let already =
                    (person.siblings ?? []).contains(where: { $0.persistentModelID == sibling.persistentModelID })
                    || (person.siblingOf ?? []).contains(where: { $0.persistentModelID == sibling.persistentModelID })
                if !already {
                    person.siblings?.append(sibling)
                }
            }
        }

        try modelContext.save()
        return Result(added: added, linkedPartners: linkedPartners, warnings: warnings)
    }

    private enum ImportError: LocalizedError {
        case notUTF8
        case emptyFile
        case noDataRows
        case missingNameColumn

        var errorDescription: String? {
            switch self {
            case .notUTF8: String(localized: "family_tree.import_err_utf8")
            case .emptyFile: String(localized: "family_tree.import_err_empty")
            case .noDataRows: String(localized: "family_tree.import_err_no_rows")
            case .missingNameColumn: String(localized: "family_tree.import_err_no_name")
            }
        }
    }

    // MARK: - Partner edges (matches editor semantics)

    private static func clearPartnerEdges(for person: FamilyPerson) {
        if person.partner != nil {
            person.partner = nil
        }
        if let other = person.partnerOf {
            other.partner = nil
        }
    }

    // MARK: - Relation → branch + optional label

    private static func parseRelationColumn(_ raw: String) -> (FamilyTreeBranch, String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return (.extended, "") }

        let compact = t
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        switch compact {
        case "ourhousehold", "household", "home", "ushousehold":
            return (.ourHousehold, "")
        case "myparentsline", "myparents", "myparent", "parentsline", "mothersline", "fathersline", "myline":
            return (.myParentsLine, "")
        case "spouseparentsline", "spouseparents", "spouseline", "inlaws", "inlaw":
            return (.spouseParentsLine, "")
        case "extended", "other", "family", "extendedfamily":
            return (.extended, "")
        default:
            return (.extended, t)
        }
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

    private static func normalizeHeaderKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func normalizePersonNameKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let folded = trimmed.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: - Date of birth

    private static func parseDeceasedFlag(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "1", "y", "yes", "true", "t", "deceased", "dead", "passed", "død", "avdød":
            return true
        default:
            return false
        }
    }

    /// Sibling names separated by `;` or `|` (commas are also accepted).
    private static func parseSiblingNames(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let separators = CharacterSet(charactersIn: ";|,")
        return trimmed
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseDOB(_ raw: String) -> Date? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let d = iso.date(from: t) {
            return Calendar.current.startOfDay(for: d)
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        let patterns = ["yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy", "MM/dd/yyyy", "yyyy/MM/dd"]
        for p in patterns {
            df.dateFormat = p
            if let d = df.date(from: t) {
                return Calendar.current.startOfDay(for: d)
            }
        }
        return nil
    }
}
