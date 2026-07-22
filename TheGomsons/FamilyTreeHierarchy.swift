//
//  FamilyTreeHierarchy.swift
//  TheGomsons
//

import SwiftData
import SwiftUI
import UIKit

// MARK: - Tree model

struct FamilyTreeNode: Identifiable {
    let id: PersistentIdentifier
    let person: FamilyPerson
    /// The other parent when every child lists both parents (mother + father) in the universe—shown beside `person`.
    let coParent: FamilyPerson?
    let children: [FamilyTreeNode]

    init(person: FamilyPerson, coParent: FamilyPerson? = nil, children: [FamilyTreeNode]) {
        self.person = person
        self.coParent = coParent
        self.children = children
        self.id = person.persistentModelID
    }
}

enum FamilyTreeHierarchyBuilder {
    /// Prefer mother for the downward edge so two-parent children appear once (below mother if present, else father).
    static func treeParent(in universe: Set<PersistentIdentifier>, for child: FamilyPerson) -> FamilyPerson? {
        if let m = child.mother, universe.contains(m.persistentModelID) { return m }
        if let f = child.father, universe.contains(f.persistentModelID) { return f }
        return nil
    }

    /// Direct children whose chosen tree parent is `person`.
    static func children(of person: FamilyPerson, in universe: [FamilyPerson]) -> [FamilyPerson] {
        let ids = Set(universe.map(\.persistentModelID))
        return universe
            .filter { ids.contains($0.persistentModelID) }
            .filter { treeParent(in: ids, for: $0)?.persistentModelID == person.persistentModelID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// When all of `parent`’s listed children share the same other biological parent and that person is in `universe`.
    static func coParentIfShared(parent: FamilyPerson, children: [FamilyPerson], universe: Set<PersistentIdentifier>) -> FamilyPerson? {
        guard !children.isEmpty else { return nil }
        var expected: FamilyPerson?
        for c in children {
            let other: FamilyPerson?
            if let m = c.mother, m.persistentModelID == parent.persistentModelID {
                other = c.father
            } else if let f = c.father, f.persistentModelID == parent.persistentModelID {
                other = c.mother
            } else {
                return nil
            }
            guard let o = other, universe.contains(o.persistentModelID) else { return nil }
            if let e = expected, e.persistentModelID != o.persistentModelID { return nil }
            expected = o
        }
        return expected
    }

    /// People with no parent in the universe (top of the visual tree). Drops duplicate “roots” for the non–tree-parent when the couple row will show both parents.
    static func roots(in universe: [FamilyPerson]) -> [FamilyPerson] {
        let ids = Set(universe.map(\.persistentModelID))
        let roots = universe
            .filter { treeParent(in: ids, for: $0) == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        let rootIds = Set(roots.map(\.persistentModelID))
        var remove = Set<PersistentIdentifier>()
        for p in roots {
            let kids = children(of: p, in: universe)
            guard !kids.isEmpty else { continue }
            guard let co = coParentIfShared(parent: p, children: kids, universe: ids) else { continue }
            guard rootIds.contains(co.persistentModelID) else { continue }
            // `p` is the structural parent row; `co` is shown beside them—omit `co` as a separate root column.
            remove.insert(co.persistentModelID)
        }
        // Partner with no parents in the universe should not be a separate column when their spouse is already
        // under someone else’s subtree (e.g. you under your parents, spouse beside you instead of a second root).
        for r in roots {
            guard let p = r.resolvedPartner, ids.contains(p.persistentModelID) else { continue }
            if treeParent(in: ids, for: p) != nil {
                remove.insert(r.persistentModelID)
                continue
            }
            // Both partners are roots (no parents in universe): keep a single root; the other appears in the couple row.
            if rootIds.contains(p.persistentModelID), r.persistentModelID != p.persistentModelID,
               treeParent(in: ids, for: r) == nil, treeParent(in: ids, for: p) == nil {
                let tie = String(describing: r.persistentModelID) > String(describing: p.persistentModelID)
                if r.sortOrder > p.sortOrder || (r.sortOrder == p.sortOrder && tie) {
                    remove.insert(r.persistentModelID)
                }
            }
        }

        let filtered = roots.filter { !remove.contains($0.persistentModelID) }
        if !filtered.isEmpty { return filtered }

        // Partner/co-parent merging can remove every root while the list still has people (e.g. in-law with spouse
        // whose parent is outside the branch filter). Fall back to structural roots only—better a duplicate spouse
        // column than an empty tree.
        let structuralOnly = roots
        if !structuralOnly.isEmpty { return structuralOnly }

        // Cycles or everyone has a parent in-universe: show top tier(s) so the tree isn’t blank.
        let noParent = universe.filter { treeParent(in: ids, for: $0) == nil }.sorted { $0.sortOrder < $1.sortOrder }
        if !noParent.isEmpty { return noParent }

        let minTier = universe.map(\.treeTier).min() ?? 0
        return universe.filter { $0.treeTier == minTier }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Children whose tree parent is `person`, unioned with children of `person`’s partner when the partner is in the universe (one household column).
    private static func mergedChildren(for person: FamilyPerson, in universe: [FamilyPerson]) -> [FamilyPerson] {
        let ids = Set(universe.map(\.persistentModelID))
        let mine = children(of: person, in: universe)
        guard let partner = person.resolvedPartner, ids.contains(partner.persistentModelID) else { return mine }
        let theirs = children(of: partner, in: universe)
        guard !theirs.isEmpty else { return mine }
        var seen = Set(mine.map(\.persistentModelID))
        var merged = mine
        for c in theirs where seen.insert(c.persistentModelID).inserted {
            merged.append(c)
        }
        return merged.sorted { $0.sortOrder < $1.sortOrder }
    }

    static func buildForest(from universe: [FamilyPerson]) -> [FamilyTreeNode] {
        let roots = roots(in: universe)
        var primarySeen = Set<PersistentIdentifier>()
        return roots.map { buildSubtree(person: $0, universe: universe, primarySeen: &primarySeen) }
    }

    private static func buildSubtree(person: FamilyPerson, universe: [FamilyPerson], primarySeen: inout Set<PersistentIdentifier>) -> FamilyTreeNode {
        let ids = Set(universe.map(\.persistentModelID))
        primarySeen.insert(person.persistentModelID)

        let childPeople = mergedChildren(for: person, in: universe)
        var coBio = coParentIfShared(parent: person, children: childPeople, universe: ids)
        if let c = coBio, primarySeen.contains(c.persistentModelID) {
            // Already shown as their own node (e.g. you under your parents)—don’t draw again beside your spouse.
            coBio = nil
        }

        var beside = coBio
        if beside == nil, let p = person.resolvedPartner, ids.contains(p.persistentModelID), !primarySeen.contains(p.persistentModelID) {
            beside = p
        }
        if let b = beside {
            primarySeen.insert(b.persistentModelID)
        }

        let childNodes = childPeople.map { buildSubtree(person: $0, universe: universe, primarySeen: &primarySeen) }
        return FamilyTreeNode(person: person, coParent: beside, children: childNodes)
    }

    /// When searching: include matches, their ancestors, and descendants so the tree stays meaningful.
    static func visibleUniverse(from all: [FamilyPerson], branchMatches: (FamilyTreeBranch) -> Bool, search: String) -> [FamilyPerson] {
        let branchFiltered = all.filter { branchMatches($0.branch) }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return branchFiltered }

        func textMatches(_ p: FamilyPerson) -> Bool {
            let blob = [
                p.name,
                p.notes,
                p.email,
                p.mobile,
                p.city,
                p.familyRelationLabel,
                p.hobbies,
                p.displayPartnerStatus?.displayTitle ?? "",
                p.partnerStatusRaw,
                p.isDeceased ? "deceased" : "",
                p.explicitSiblings.map(\.name).joined(separator: " "),
            ]
            .joined(separator: "\n")
            .lowercased()
            return blob.contains(q)
        }

        let matches = Set(branchFiltered.filter(textMatches).map(\.persistentModelID))

        func ancestors(_ p: FamilyPerson, into set: inout Set<PersistentIdentifier>) {
            if let m = p.mother {
                set.insert(m.persistentModelID)
                ancestors(m, into: &set)
            }
            if let f = p.father {
                set.insert(f.persistentModelID)
                ancestors(f, into: &set)
            }
        }

        func descendants(_ p: FamilyPerson, into set: inout Set<PersistentIdentifier>) {
            for c in FamilyTreeHierarchyBuilder.children(of: p, in: branchFiltered) {
                if set.insert(c.persistentModelID).inserted {
                    descendants(c, into: &set)
                }
            }
        }

        var visible = Set<PersistentIdentifier>()
        for p in branchFiltered where matches.contains(p.persistentModelID) {
            visible.insert(p.persistentModelID)
            ancestors(p, into: &visible)
            descendants(p, into: &visible)
        }

        return branchFiltered.filter { visible.contains($0.persistentModelID) }
    }
}

// MARK: - Visual tree

struct FamilyTreeHierarchyView: View {
    let nodes: [FamilyTreeNode]
    var onSelect: (FamilyPerson) -> Void

    var body: some View {
        ScrollView(.vertical) {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(nodes) { node in
                        FamilyTreeNodeColumn(node: node, onSelect: onSelect)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FamilyTreeNodeColumn: View {
    let node: FamilyTreeNode
    var onSelect: (FamilyPerson) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let co = node.coParent {
                let sampleChild = node.children.first?.person
                HStack(alignment: .center, spacing: 6) {
                    FamilyTreePersonCard(
                        person: node.person,
                        roleLabel: parentalRoleLabel(adult: node.person, sampleChild: sampleChild),
                        onTap: { onSelect(node.person) }
                    )
                    ParentPartnershipBadge()
                    FamilyTreePersonCard(
                        person: co,
                        roleLabel: parentalRoleLabel(adult: co, sampleChild: sampleChild),
                        onTap: { onSelect(co) }
                    )
                }
            } else {
                FamilyTreePersonCard(person: node.person, onTap: { onSelect(node.person) })
            }

            if !node.children.isEmpty {
                TreeConnectorLineDown()
                HStack(alignment: .top, spacing: 12) {
                    ForEach(node.children) { child in
                        FamilyTreeNodeColumn(node: child, onSelect: onSelect)
                    }
                }
            }
        }
    }
}

private func parentalRoleLabel(adult: FamilyPerson, sampleChild: FamilyPerson?) -> String? {
    guard let c = sampleChild else { return nil }
    if c.mother?.persistentModelID == adult.persistentModelID { return "Mother" }
    if c.father?.persistentModelID == adult.persistentModelID { return "Father" }
    return nil
}

private struct ParentPartnershipBadge: View {
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundStyle(SimpsonsTheme.pink)
            Rectangle()
                .fill(SimpsonsTheme.orange.opacity(0.45))
                .frame(width: 24, height: 2)
        }
        .accessibilityLabel("Parents")
    }
}

private struct TreeConnectorLineDown: View {
    var body: some View {
        Rectangle()
            .fill(SimpsonsTheme.orange.opacity(0.45))
            .frame(width: 2, height: 14)
    }
}

private struct FamilyTreePersonCard: View {
    let person: FamilyPerson
    var roleLabel: String? = nil
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                FamilyTreeAvatar(photoData: person.photoData, name: person.name)
                    .frame(width: 72, height: 72)
                if let roleLabel {
                    Text(roleLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SimpsonsTheme.charcoal.opacity(0.55))
                }
                Text(person.name.isEmpty ? "Name" : person.name)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(minWidth: 88, maxWidth: 128)
                    .foregroundStyle(person.isDeceased ? .secondary : .primary)
                if person.isDeceased {
                    DeceasedCrossMark(font: .caption.weight(.semibold))
                }
                if let partner = person.resolvedPartner {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(SimpsonsTheme.pink)
                        Text(partnerFirstName(partner))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 128)
                }
                if person.isDeceased, let death = person.deathDate {
                    Text("† \(death.formatted(.dateTime.year()))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(
                            String(
                                format: String(localized: "family_tree.died_on_fmt"),
                                locale: .current,
                                death.formatted(.dateTime.month().day().year())
                            )
                        )
                } else if let birth = person.birthDate {
                    Text(birth, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .opacity(person.isDeceased ? 0.85 : 1)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        person.isDeceased
                            ? Color.secondary.opacity(0.35)
                            : SimpsonsTheme.orange.opacity(0.4),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func partnerFirstName(_ partner: FamilyPerson) -> String {
        let name = partner.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return String(localized: "common.unnamed") }
        return String(name.split(separator: " ").first ?? Substring(name))
    }
}

/// Genealogy-style † mark for deceased people (VoiceOver still says “Deceased”).
struct DeceasedCrossMark: View {
    var font: Font = .body

    var body: some View {
        Text("†")
            .font(font)
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: "family_tree.deceased_badge"))
    }
}

private struct FamilyTreeAvatar: View {
    var photoData: Data?
    var name: String

    var body: some View {
        Group {
            if let data = photoData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(SimpsonsTheme.orange.opacity(0.28))
                    Text(initials(from: name))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SimpsonsTheme.charcoal)
                }
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(SimpsonsTheme.charcoal.opacity(0.12), lineWidth: 1))
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
