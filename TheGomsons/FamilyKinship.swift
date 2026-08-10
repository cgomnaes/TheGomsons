//
//  FamilyKinship.swift
//  TheGomsons
//
//  Relationship labels relative to a selected “me” person (uncle, grandfather, …).
//

import Foundation
import SwiftData

enum FamilyKinship {
    enum InferredSex {
        case female
        case male
        case unknown
    }

    /// Prefer mother/father roles already recorded in the tree.
    static func inferredSex(of person: FamilyPerson) -> InferredSex {
        if !(person.childrenWhereMother ?? []).isEmpty { return .female }
        if !(person.childrenWhereFather ?? []).isEmpty { return .male }
        return .unknown
    }

    /// Short label for tree cards: “You”, “Uncle”, “Grandmother”, “Relative”, …
    static func label(
        of other: FamilyPerson,
        relativeTo me: FamilyPerson,
        among universe: [FamilyPerson]
    ) -> String {
        if other.persistentModelID == me.persistentModelID {
            return "You"
        }

        if let partner = me.resolvedPartner,
           partner.persistentModelID == other.persistentModelID {
            return me.displayPartnerStatus?.displayTitle ?? "Partner"
        }

        let ids = Set(universe.map(\.persistentModelID))
        guard ids.contains(other.persistentModelID), ids.contains(me.persistentModelID) else {
            return "Extended family"
        }

        // Direct parent links (most reliable gendered labels).
        if me.mother?.persistentModelID == other.persistentModelID { return "Mother" }
        if me.father?.persistentModelID == other.persistentModelID { return "Father" }

        // Direct children.
        let myKids = FamilyTreeHierarchyBuilder.mergedChildren(for: me, in: universe)
        if myKids.contains(where: { $0.persistentModelID == other.persistentModelID }) {
            return childLabel(for: other)
        }

        // Blood kinship via lowest common ancestor.
        if let blood = bloodLabel(of: other, relativeTo: me, among: universe) {
            return blood
        }

        // In-laws / step relations through partner.
        if let partner = me.resolvedPartner, ids.contains(partner.persistentModelID),
           let viaPartner = bloodLabel(of: other, relativeTo: partner, among: universe) {
            return inLawLabel(mapping: viaPartner, other: other)
        }

        // Partner of a close blood relative.
        if let through = partnerOfCloseRelativeLabel(of: other, relativeTo: me, among: universe) {
            return through
        }

        // Connected somehow in the visible graph?
        if isConnected(me, other, among: universe) {
            return "Relative"
        }
        return "Extended family"
    }

    // MARK: - Blood path (LCA)

    private static func bloodLabel(
        of other: FamilyPerson,
        relativeTo me: FamilyPerson,
        among universe: [FamilyPerson]
    ) -> String? {
        let myAncestors = ancestorDepths(from: me)
        let theirAncestors = ancestorDepths(from: other)

        // `other` is an ancestor of `me`
        if let up = myAncestors[other.persistentModelID] {
            return ancestorLabel(generationsUp: up, person: other)
        }
        // `me` is an ancestor of `other`
        if let down = theirAncestors[me.persistentModelID] {
            return descendantLabel(generationsDown: down, person: other)
        }

        // LCA among shared ancestors (including each person as ancestor of themselves at depth 0).
        var myMap = myAncestors
        myMap[me.persistentModelID] = 0
        var theirMap = theirAncestors
        theirMap[other.persistentModelID] = 0

        var best: (id: PersistentIdentifier, genMe: Int, genOther: Int)?
        for (id, genMe) in myMap {
            guard let genOther = theirMap[id] else { continue }
            let score = genMe + genOther
            if let b = best {
                if score < b.genMe + b.genOther
                    || (score == b.genMe + b.genOther && genMe < b.genMe) {
                    best = (id, genMe, genOther)
                }
            } else {
                best = (id, genMe, genOther)
            }
        }
        guard let lca = best else { return nil }

        let gMe = lca.genMe
        let gOther = lca.genOther

        // Same person handled earlier; siblings / cousins / aunts …
        if gMe == 0, gOther == 0 { return "You" }
        if gMe == 1, gOther == 1 {
            return siblingLabel(for: other)
        }
        if gMe == 1, gOther == 0 {
            // LCA is `other` → already handled as ancestor
            return ancestorLabel(generationsUp: 1, person: other)
        }
        if gMe == 0, gOther == 1 {
            return childLabel(for: other)
        }

        // Aunt / uncle: parent's sibling (or sibling of grandparent = great-aunt, etc.)
        if gOther == 1, gMe >= 2 {
            return collateralUpLabel(generationsUp: gMe, person: other)
        }
        // Niece / nephew
        if gMe == 1, gOther >= 2 {
            return collateralDownLabel(generationsDown: gOther, person: other)
        }
        // Cousins (same generation under a shared ancestor)
        if gMe >= 2, gOther >= 2, gMe == gOther {
            if gMe == 2 { return "Cousin" }
            if gMe == 3 { return "Second cousin" }
            return "Relative"
        }
        // Removed cousins / uneven cousins — keep simple.
        if gMe >= 2, gOther >= 2 {
            return "Relative"
        }

        if gMe + gOther >= 5 {
            return "Extended family"
        }
        return "Relative"
    }

    /// Depths of blood ancestors only (mother/father walk). Self not included.
    private static func ancestorDepths(from person: FamilyPerson) -> [PersistentIdentifier: Int] {
        var result: [PersistentIdentifier: Int] = [:]
        var queue: [(FamilyPerson, Int)] = []
        if let m = person.mother { queue.append((m, 1)) }
        if let f = person.father { queue.append((f, 1)) }
        var i = 0
        while i < queue.count {
            let (p, depth) = queue[i]
            i += 1
            if result[p.persistentModelID] != nil { continue }
            result[p.persistentModelID] = depth
            if depth >= 8 { continue }
            if let m = p.mother { queue.append((m, depth + 1)) }
            if let f = p.father { queue.append((f, depth + 1)) }
        }
        return result
    }

    private static func ancestorLabel(generationsUp: Int, person: FamilyPerson) -> String {
        let sex = inferredSex(of: person)
        switch generationsUp {
        case 1:
            switch sex {
            case .female: return "Mother"
            case .male: return "Father"
            case .unknown: return "Parent"
            }
        case 2:
            switch sex {
            case .female: return "Grandmother"
            case .male: return "Grandfather"
            case .unknown: return "Grandparent"
            }
        case 3:
            switch sex {
            case .female: return "Great-grandmother"
            case .male: return "Great-grandfather"
            case .unknown: return "Great-grandparent"
            }
        default:
            return "Extended family"
        }
    }

    private static func descendantLabel(generationsDown: Int, person: FamilyPerson) -> String {
        let sex = inferredSex(of: person)
        switch generationsDown {
        case 1:
            return childLabel(for: person)
        case 2:
            switch sex {
            case .female: return "Granddaughter"
            case .male: return "Grandson"
            case .unknown: return "Grandchild"
            }
        case 3:
            switch sex {
            case .female: return "Great-granddaughter"
            case .male: return "Great-grandson"
            case .unknown: return "Great-grandchild"
            }
        default:
            return "Extended family"
        }
    }

    private static func childLabel(for person: FamilyPerson) -> String {
        switch inferredSex(of: person) {
        case .female: return "Daughter"
        case .male: return "Son"
        case .unknown: return "Child"
        }
    }

    private static func siblingLabel(for person: FamilyPerson) -> String {
        switch inferredSex(of: person) {
        case .female: return "Sister"
        case .male: return "Brother"
        case .unknown: return "Sibling"
        }
    }

    /// Parent’s sibling, grandparent’s sibling, …
    private static func collateralUpLabel(generationsUp: Int, person: FamilyPerson) -> String {
        let sex = inferredSex(of: person)
        switch generationsUp {
        case 2:
            switch sex {
            case .female: return "Aunt"
            case .male: return "Uncle"
            case .unknown: return "Aunt/Uncle"
            }
        case 3:
            switch sex {
            case .female: return "Great-aunt"
            case .male: return "Great-uncle"
            case .unknown: return "Great-aunt/uncle"
            }
        default:
            return "Extended family"
        }
    }

    private static func collateralDownLabel(generationsDown: Int, person: FamilyPerson) -> String {
        let sex = inferredSex(of: person)
        switch generationsDown {
        case 2:
            switch sex {
            case .female: return "Niece"
            case .male: return "Nephew"
            case .unknown: return "Niece/Nephew"
            }
        case 3:
            switch sex {
            case .female: return "Grandniece"
            case .male: return "Grandnephew"
            case .unknown: return "Grandniece/nephew"
            }
        default:
            return "Extended family"
        }
    }

    private static func inLawLabel(mapping bloodAsIfPartner: String, other: FamilyPerson) -> String {
        switch bloodAsIfPartner {
        case "Mother", "Father", "Parent":
            return "Parent-in-law"
        case "Sister", "Brother", "Sibling":
            switch inferredSex(of: other) {
            case .female: return "Sister-in-law"
            case .male: return "Brother-in-law"
            case .unknown: return "Sibling-in-law"
            }
        case "Daughter", "Son", "Child":
            switch inferredSex(of: other) {
            case .female: return "Daughter-in-law"
            case .male: return "Son-in-law"
            case .unknown: return "Child-in-law"
            }
        case "Grandmother", "Grandfather", "Grandparent":
            return "Relative"
        case "Aunt", "Uncle", "Aunt/Uncle":
            return "Relative"
        default:
            if bloodAsIfPartner == "You" { return "Partner" }
            return "Relative"
        }
    }

    private static func partnerOfCloseRelativeLabel(
        of other: FamilyPerson,
        relativeTo me: FamilyPerson,
        among universe: [FamilyPerson]
    ) -> String? {
        guard let theirPartner = other.resolvedPartner else { return nil }
        guard let blood = bloodLabel(of: theirPartner, relativeTo: me, among: universe) else { return nil }
        switch blood {
        case "Mother", "Father", "Parent":
            return "Parent’s partner"
        case "Sister", "Brother", "Sibling":
            switch inferredSex(of: other) {
            case .female: return "Sister-in-law"
            case .male: return "Brother-in-law"
            case .unknown: return "Sibling-in-law"
            }
        case "Daughter", "Son", "Child":
            switch inferredSex(of: other) {
            case .female: return "Daughter-in-law"
            case .male: return "Son-in-law"
            case .unknown: return "Child-in-law"
            }
        case "Aunt", "Uncle", "Aunt/Uncle":
            switch inferredSex(of: other) {
            case .female: return "Aunt"
            case .male: return "Uncle"
            case .unknown: return "Aunt/Uncle"
            }
        case "You":
            return me.displayPartnerStatus?.displayTitle ?? "Partner"
        default:
            return "Relative"
        }
    }

    /// Weak connectivity via parents / children / partners / siblings (for “Relative” vs “Extended family”).
    private static func isConnected(_ a: FamilyPerson, _ b: FamilyPerson, among universe: [FamilyPerson]) -> Bool {
        let ids = Set(universe.map(\.persistentModelID))
        var seen = Set<PersistentIdentifier>()
        var queue: [FamilyPerson] = [a]
        seen.insert(a.persistentModelID)
        var steps = 0
        while let person = queue.first {
            queue.removeFirst()
            if person.persistentModelID == b.persistentModelID { return true }
            steps += 1
            if steps > 80 { break }

            var neighbors: [FamilyPerson] = []
            if let m = person.mother, ids.contains(m.persistentModelID) { neighbors.append(m) }
            if let f = person.father, ids.contains(f.persistentModelID) { neighbors.append(f) }
            if let p = person.resolvedPartner, ids.contains(p.persistentModelID) { neighbors.append(p) }
            neighbors.append(contentsOf: FamilyTreeHierarchyBuilder.mergedChildren(for: person, in: universe))
            neighbors.append(contentsOf: person.resolvedSiblings(among: universe))

            for n in neighbors where seen.insert(n.persistentModelID).inserted {
                queue.append(n)
            }
        }
        return false
    }
}
