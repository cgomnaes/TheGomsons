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

    /// Internal kind so in-law mapping does not depend on English display strings.
    enum Kind: Equatable {
        case you
        case partner
        case mother, father, parent
        case daughter, son, child
        case sister, brother, sibling
        case grandmother, grandfather, grandparent
        case greatGrandmother, greatGrandfather, greatGrandparent
        case granddaughter, grandson, grandchild
        case greatGranddaughter, greatGrandson, greatGrandchild
        case aunt, uncle, auntOrUncle
        case greatAunt, greatUncle, greatAuntOrUncle
        case niece, nephew, nieceOrNephew
        case grandniece, grandnephew, grandnieceOrNephew
        case cousin, cousinFemale, cousinMale, secondCousin
        case parentInLaw
        case sisterInLaw, brotherInLaw, siblingInLaw
        case daughterInLaw, sonInLaw, childInLaw
        case parentsPartner
        case relative
        case extended
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
        kind(of: other, relativeTo: me, among: universe).localizedName(partnerStatus: me.displayPartnerStatus)
    }

    static func kind(
        of other: FamilyPerson,
        relativeTo me: FamilyPerson,
        among universe: [FamilyPerson]
    ) -> Kind {
        if other.persistentModelID == me.persistentModelID {
            return .you
        }

        if let partner = me.resolvedPartner,
           partner.persistentModelID == other.persistentModelID {
            return .partner
        }

        let ids = Set(universe.map(\.persistentModelID))
        guard ids.contains(other.persistentModelID), ids.contains(me.persistentModelID) else {
            return .extended
        }

        if me.mother?.persistentModelID == other.persistentModelID { return .mother }
        if me.father?.persistentModelID == other.persistentModelID { return .father }

        let myKids = FamilyTreeHierarchyBuilder.mergedChildren(for: me, in: universe)
        if myKids.contains(where: { $0.persistentModelID == other.persistentModelID }) {
            return childKind(for: other)
        }

        if let blood = bloodKind(of: other, relativeTo: me, among: universe) {
            return blood
        }

        if let partner = me.resolvedPartner, ids.contains(partner.persistentModelID),
           let viaPartner = bloodKind(of: other, relativeTo: partner, among: universe) {
            return inLawKind(mapping: viaPartner, other: other)
        }

        if let through = partnerOfCloseRelativeKind(of: other, relativeTo: me, among: universe) {
            return through
        }

        if isConnected(me, other, among: universe) {
            return .relative
        }
        return .extended
    }

    // MARK: - Blood path (LCA)

    private static func bloodKind(
        of other: FamilyPerson,
        relativeTo me: FamilyPerson,
        among universe: [FamilyPerson]
    ) -> Kind? {
        let myAncestors = ancestorDepths(from: me)
        let theirAncestors = ancestorDepths(from: other)

        if let up = myAncestors[other.persistentModelID] {
            return ancestorKind(generationsUp: up, person: other)
        }
        if let down = theirAncestors[me.persistentModelID] {
            return descendantKind(generationsDown: down, person: other)
        }

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

        if gMe == 0, gOther == 0 { return .you }
        if gMe == 1, gOther == 1 {
            return siblingKind(for: other)
        }
        if gMe == 1, gOther == 0 {
            return ancestorKind(generationsUp: 1, person: other)
        }
        if gMe == 0, gOther == 1 {
            return childKind(for: other)
        }

        if gOther == 1, gMe >= 2 {
            return collateralUpKind(generationsUp: gMe, person: other)
        }
        if gMe == 1, gOther >= 2 {
            return collateralDownKind(generationsDown: gOther, person: other)
        }
        if gMe >= 2, gOther >= 2, gMe == gOther {
            if gMe == 2 { return cousinKind(for: other) }
            if gMe == 3 { return .secondCousin }
            return .relative
        }
        if gMe >= 2, gOther >= 2 {
            return .relative
        }

        if gMe + gOther >= 5 {
            return .extended
        }
        return .relative
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

    private static func ancestorKind(generationsUp: Int, person: FamilyPerson) -> Kind {
        let sex = inferredSex(of: person)
        switch generationsUp {
        case 1:
            switch sex {
            case .female: return .mother
            case .male: return .father
            case .unknown: return .parent
            }
        case 2:
            switch sex {
            case .female: return .grandmother
            case .male: return .grandfather
            case .unknown: return .grandparent
            }
        case 3:
            switch sex {
            case .female: return .greatGrandmother
            case .male: return .greatGrandfather
            case .unknown: return .greatGrandparent
            }
        default:
            return .extended
        }
    }

    private static func descendantKind(generationsDown: Int, person: FamilyPerson) -> Kind {
        switch generationsDown {
        case 1:
            return childKind(for: person)
        case 2:
            switch inferredSex(of: person) {
            case .female: return .granddaughter
            case .male: return .grandson
            case .unknown: return .grandchild
            }
        case 3:
            switch inferredSex(of: person) {
            case .female: return .greatGranddaughter
            case .male: return .greatGrandson
            case .unknown: return .greatGrandchild
            }
        default:
            return .extended
        }
    }

    private static func childKind(for person: FamilyPerson) -> Kind {
        switch inferredSex(of: person) {
        case .female: return .daughter
        case .male: return .son
        case .unknown: return .child
        }
    }

    private static func siblingKind(for person: FamilyPerson) -> Kind {
        switch inferredSex(of: person) {
        case .female: return .sister
        case .male: return .brother
        case .unknown: return .sibling
        }
    }

    private static func cousinKind(for person: FamilyPerson) -> Kind {
        switch inferredSex(of: person) {
        case .female: return .cousinFemale
        case .male: return .cousinMale
        case .unknown: return .cousin
        }
    }

    /// Parent’s sibling, grandparent’s sibling, …
    private static func collateralUpKind(generationsUp: Int, person: FamilyPerson) -> Kind {
        let sex = inferredSex(of: person)
        switch generationsUp {
        case 2:
            switch sex {
            case .female: return .aunt
            case .male: return .uncle
            case .unknown: return .auntOrUncle
            }
        case 3:
            switch sex {
            case .female: return .greatAunt
            case .male: return .greatUncle
            case .unknown: return .greatAuntOrUncle
            }
        default:
            return .extended
        }
    }

    private static func collateralDownKind(generationsDown: Int, person: FamilyPerson) -> Kind {
        let sex = inferredSex(of: person)
        switch generationsDown {
        case 2:
            switch sex {
            case .female: return .niece
            case .male: return .nephew
            case .unknown: return .nieceOrNephew
            }
        case 3:
            switch sex {
            case .female: return .grandniece
            case .male: return .grandnephew
            case .unknown: return .grandnieceOrNephew
            }
        default:
            return .extended
        }
    }

    private static func inLawKind(mapping bloodAsIfPartner: Kind, other: FamilyPerson) -> Kind {
        switch bloodAsIfPartner {
        case .mother, .father, .parent:
            return .parentInLaw
        case .sister, .brother, .sibling:
            switch inferredSex(of: other) {
            case .female: return .sisterInLaw
            case .male: return .brotherInLaw
            case .unknown: return .siblingInLaw
            }
        case .daughter, .son, .child:
            switch inferredSex(of: other) {
            case .female: return .daughterInLaw
            case .male: return .sonInLaw
            case .unknown: return .childInLaw
            }
        case .you:
            return .partner
        default:
            return .relative
        }
    }

    private static func partnerOfCloseRelativeKind(
        of other: FamilyPerson,
        relativeTo me: FamilyPerson,
        among universe: [FamilyPerson]
    ) -> Kind? {
        guard let theirPartner = other.resolvedPartner else { return nil }
        guard let blood = bloodKind(of: theirPartner, relativeTo: me, among: universe) else { return nil }
        switch blood {
        case .mother, .father, .parent:
            return .parentsPartner
        case .sister, .brother, .sibling:
            switch inferredSex(of: other) {
            case .female: return .sisterInLaw
            case .male: return .brotherInLaw
            case .unknown: return .siblingInLaw
            }
        case .daughter, .son, .child:
            switch inferredSex(of: other) {
            case .female: return .daughterInLaw
            case .male: return .sonInLaw
            case .unknown: return .childInLaw
            }
        case .aunt, .uncle, .auntOrUncle:
            switch inferredSex(of: other) {
            case .female: return .aunt
            case .male: return .uncle
            case .unknown: return .auntOrUncle
            }
        case .you:
            return .partner
        default:
            return .relative
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

extension FamilyKinship.Kind {
    func localizedName(partnerStatus: PartnerRelationshipStatus? = nil) -> String {
        switch self {
        case .you: String(localized: "kinship.you")
        case .partner: partnerStatus?.displayTitle ?? String(localized: "kinship.partner")
        case .mother: String(localized: "kinship.mother")
        case .father: String(localized: "kinship.father")
        case .parent: String(localized: "kinship.parent")
        case .daughter: String(localized: "kinship.daughter")
        case .son: String(localized: "kinship.son")
        case .child: String(localized: "kinship.child")
        case .sister: String(localized: "kinship.sister")
        case .brother: String(localized: "kinship.brother")
        case .sibling: String(localized: "kinship.sibling")
        case .grandmother: String(localized: "kinship.grandmother")
        case .grandfather: String(localized: "kinship.grandfather")
        case .grandparent: String(localized: "kinship.grandparent")
        case .greatGrandmother: String(localized: "kinship.great_grandmother")
        case .greatGrandfather: String(localized: "kinship.great_grandfather")
        case .greatGrandparent: String(localized: "kinship.great_grandparent")
        case .granddaughter: String(localized: "kinship.granddaughter")
        case .grandson: String(localized: "kinship.grandson")
        case .grandchild: String(localized: "kinship.grandchild")
        case .greatGranddaughter: String(localized: "kinship.great_granddaughter")
        case .greatGrandson: String(localized: "kinship.great_grandson")
        case .greatGrandchild: String(localized: "kinship.great_grandchild")
        case .aunt: String(localized: "kinship.aunt")
        case .uncle: String(localized: "kinship.uncle")
        case .auntOrUncle: String(localized: "kinship.aunt_uncle")
        case .greatAunt: String(localized: "kinship.great_aunt")
        case .greatUncle: String(localized: "kinship.great_uncle")
        case .greatAuntOrUncle: String(localized: "kinship.great_aunt_uncle")
        case .niece: String(localized: "kinship.niece")
        case .nephew: String(localized: "kinship.nephew")
        case .nieceOrNephew: String(localized: "kinship.niece_nephew")
        case .grandniece: String(localized: "kinship.grandniece")
        case .grandnephew: String(localized: "kinship.grandnephew")
        case .grandnieceOrNephew: String(localized: "kinship.grandniece_nephew")
        case .cousin: String(localized: "kinship.cousin")
        case .cousinFemale: String(localized: "kinship.cousin_female")
        case .cousinMale: String(localized: "kinship.cousin_male")
        case .secondCousin: String(localized: "kinship.second_cousin")
        case .parentInLaw: String(localized: "kinship.parent_in_law")
        case .sisterInLaw: String(localized: "kinship.sister_in_law")
        case .brotherInLaw: String(localized: "kinship.brother_in_law")
        case .siblingInLaw: String(localized: "kinship.sibling_in_law")
        case .daughterInLaw: String(localized: "kinship.daughter_in_law")
        case .sonInLaw: String(localized: "kinship.son_in_law")
        case .childInLaw: String(localized: "kinship.child_in_law")
        case .parentsPartner: String(localized: "kinship.parents_partner")
        case .relative: String(localized: "kinship.relative")
        case .extended: String(localized: "kinship.extended")
        }
    }
}
