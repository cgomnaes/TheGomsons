//
//  FamilyTreeHierarchy.swift
//  TheGomsons
//

import SwiftData
import SwiftUI
import UIKit

// MARK: - Tree model (descendant columns)

struct FamilyTreeNode: Identifiable {
    let id: PersistentIdentifier
    let person: FamilyPerson
    /// The other parent when every child lists both parents—shown beside `person`.
    let coParent: FamilyPerson?
    let children: [FamilyTreeNode]

    init(person: FamilyPerson, coParent: FamilyPerson? = nil, children: [FamilyTreeNode]) {
        self.person = person
        self.coParent = coParent
        self.children = children
        self.id = person.persistentModelID
    }
}

/// Person-centered snapshot: ancestors above, focus (+ partner + siblings) in the middle, descendants below.
struct FamilyEgoGraph: Identifiable {
    var id: PersistentIdentifier { focus.persistentModelID }
    var focus: FamilyPerson
    var partner: FamilyPerson?
    /// Pedigree rows from parents (index 0) up to older generations. Each row is mother/father pairs in pedigree order.
    var ancestorGenerations: [[FamilyPerson?]]
    var siblings: [FamilyPerson]
    var cousins: [FamilyPerson]
    var childNodes: [FamilyTreeNode]
    var missingMother: Bool
    var missingFather: Bool

    var hasAncestors: Bool {
        ancestorGenerations.contains { row in row.contains(where: { $0 != nil }) }
            || missingMother || missingFather
    }

    var hasDescendants: Bool { !childNodes.isEmpty }
}

enum FamilyTreeHierarchyBuilder {
    static func treeParent(in universe: Set<PersistentIdentifier>, for child: FamilyPerson) -> FamilyPerson? {
        if let m = child.mother, universe.contains(m.persistentModelID) { return m }
        if let f = child.father, universe.contains(f.persistentModelID) { return f }
        return nil
    }

    static func children(of person: FamilyPerson, in universe: [FamilyPerson]) -> [FamilyPerson] {
        let ids = Set(universe.map(\.persistentModelID))
        var kids = universe
            .filter { ids.contains($0.persistentModelID) }
            .filter { treeParent(in: ids, for: $0)?.persistentModelID == person.persistentModelID }

        var omit = Set<PersistentIdentifier>()
        for a in kids {
            guard let b = a.resolvedPartner, ids.contains(b.persistentModelID) else { continue }
            guard kids.contains(where: { $0.persistentModelID == b.persistentModelID }) else { continue }
            let keepA =
                a.sortOrder < b.sortOrder
                || (a.sortOrder == b.sortOrder
                    && String(describing: a.persistentModelID) < String(describing: b.persistentModelID))
            omit.insert(keepA ? b.persistentModelID : a.persistentModelID)
        }
        if !omit.isEmpty {
            kids = kids.filter { !omit.contains($0.persistentModelID) }
        }
        return kids.sorted { $0.sortOrder < $1.sortOrder }
    }

    static func coParentIfShared(
        parent: FamilyPerson,
        children: [FamilyPerson],
        universe: Set<PersistentIdentifier>
    ) -> FamilyPerson? {
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

    static func mergedChildren(for person: FamilyPerson, in universe: [FamilyPerson]) -> [FamilyPerson] {
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

    /// Saved home → household with kids → household → anyone.
    static func defaultFocus(in universe: [FamilyPerson], preferredHomeName: String?) -> FamilyPerson? {
        guard !universe.isEmpty else { return nil }
        if let preferredHomeName {
            let key = preferredHomeName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty,
               let home = universe.first(where: {
                   $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
               }) {
                return home
            }
        }
        let household = universe.filter { $0.branch == .ourHousehold }
        if let withKids = household.first(where: { !mergedChildren(for: $0, in: universe).isEmpty }) {
            return withKids
        }
        if let firstHousehold = household.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
            return firstHousehold
        }
        return universe.sorted { $0.sortOrder < $1.sortOrder }.first
    }

    static func buildEgoGraph(
        focus: FamilyPerson,
        universe: [FamilyPerson],
        ancestorGenerations: Int = 2,
        descendantGenerations: Int = 2,
        includeCousins: Bool = false
    ) -> FamilyEgoGraph {
        let ids = Set(universe.map(\.persistentModelID))
        let ancDepth = max(1, min(ancestorGenerations, 5))
        let descDepth = max(1, min(descendantGenerations, 5))

        func inUniverse(_ p: FamilyPerson?) -> FamilyPerson? {
            guard let p, ids.contains(p.persistentModelID) else { return nil }
            return p
        }

        let partner = inUniverse(focus.resolvedPartner)
        let focusID = focus.persistentModelID
        let partnerID = partner?.persistentModelID

        var pedigreeRows: [[FamilyPerson?]] = []
        for generation in 1...ancDepth {
            pedigreeRows.append(pedigreeGeneration(focus: focus, generation: generation, inUniverse: ids))
        }

        let siblings = focus.resolvedSiblings(among: universe)
            .filter { $0.persistentModelID != focusID && $0.persistentModelID != partnerID }
            .sorted { lhs, rhs in
                switch (lhs.birthDate, rhs.birthDate) {
                case let (a?, b?): return a < b
                case (_?, nil): return true
                case (nil, _?): return false
                default:
                    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }

        var cousins: [FamilyPerson] = []
        if includeCousins {
            var seen = Set<PersistentIdentifier>([focusID])
            if let partnerID { seen.insert(partnerID) }
            for s in siblings { seen.insert(s.persistentModelID) }
            for parent in [focus.mother, focus.father].compactMap({ $0 }) {
                for auntUncle in parent.resolvedSiblings(among: universe) {
                    for kid in mergedChildren(for: auntUncle, in: universe) where seen.insert(kid.persistentModelID).inserted {
                        cousins.append(kid)
                    }
                }
            }
            cousins.sort { $0.sortOrder < $1.sortOrder }
        }

        var primarySeen = Set<PersistentIdentifier>([focusID])
        if let partnerID { primarySeen.insert(partnerID) }
        for s in siblings { primarySeen.insert(s.persistentModelID) }
        for c in cousins { primarySeen.insert(c.persistentModelID) }

        let kids = mergedChildren(for: focus, in: universe)
            .filter { $0.persistentModelID != focusID && $0.persistentModelID != partnerID }
        let childNodes = kids.map {
            buildSubtree(
                person: $0,
                universe: universe,
                primarySeen: &primarySeen,
                remainingDepth: descDepth - 1
            )
        }

        return FamilyEgoGraph(
            focus: focus,
            partner: partner,
            ancestorGenerations: pedigreeRows,
            siblings: siblings,
            cousins: cousins,
            childNodes: childNodes,
            missingMother: focus.mother == nil,
            missingFather: focus.father == nil
        )
    }

    /// Pedigree order: generation 1 = [mother, father], generation 2 = four grandparents, …
    private static func pedigreeGeneration(
        focus: FamilyPerson,
        generation: Int,
        inUniverse ids: Set<PersistentIdentifier>
    ) -> [FamilyPerson?] {
        func slot(_ person: FamilyPerson?) -> FamilyPerson? {
            guard let person, ids.contains(person.persistentModelID) else { return nil }
            return person
        }
        if generation <= 1 {
            return [slot(focus.mother), slot(focus.father)]
        }
        let parents = pedigreeGeneration(focus: focus, generation: generation - 1, inUniverse: ids)
        var row: [FamilyPerson?] = []
        row.reserveCapacity(parents.count * 2)
        for parent in parents {
            row.append(slot(parent?.mother))
            row.append(slot(parent?.father))
        }
        return row
    }

    private static func buildSubtree(
        person: FamilyPerson,
        universe: [FamilyPerson],
        primarySeen: inout Set<PersistentIdentifier>,
        remainingDepth: Int
    ) -> FamilyTreeNode {
        let ids = Set(universe.map(\.persistentModelID))
        primarySeen.insert(person.persistentModelID)

        guard remainingDepth > 0 else {
            return FamilyTreeNode(person: person, coParent: nil, children: [])
        }

        let childPeople = mergedChildren(for: person, in: universe)
            .filter { !primarySeen.contains($0.persistentModelID) }
        let hangsUnderSomeone = treeParent(in: ids, for: person) != nil

        var beside: FamilyPerson?
        if !hangsUnderSomeone {
            var coBio = coParentIfShared(parent: person, children: childPeople, universe: ids)
            if let c = coBio, primarySeen.contains(c.persistentModelID) {
                coBio = nil
            }
            beside = coBio
            if beside == nil,
               let p = person.resolvedPartner,
               ids.contains(p.persistentModelID),
               !primarySeen.contains(p.persistentModelID) {
                beside = p
            }
            if let b = beside {
                primarySeen.insert(b.persistentModelID)
            }
        }

        let childNodes = childPeople.map {
            buildSubtree(
                person: $0,
                universe: universe,
                primarySeen: &primarySeen,
                remainingDepth: remainingDepth - 1
            )
        }
        return FamilyTreeNode(person: person, coParent: beside, children: childNodes)
    }

    static func visibleUniverse(
        from all: [FamilyPerson],
        branchMatches: (FamilyTreeBranch) -> Bool,
        search: String
    ) -> [FamilyPerson] {
        let branchFiltered = all.filter { branchMatches($0.branch) }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return branchFiltered }

        func textMatches(_ p: FamilyPerson) -> Bool {
            let blob = [
                p.name,
                p.preferredName,
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

// MARK: - Home person preference

enum FamilyTreeHomePersonStore {
    private static let nameKey = "familyTree.homePersonName"
    private static let generationsKey = "familyTree.generationDepth"
    private static let showCousinsKey = "familyTree.showCousins"
    private static let showAddParentCardsKey = "familyTree.showAddParentCards"
    private static let colorCodeBranchesKey = "familyTree.colorCodeBranches"
    private static let showDeceasedRibbonKey = "familyTree.showDeceasedRibbon"

    /// Display name of the person who represents “me” on this device.
    static var mePersonName: String? {
        get {
            let s = UserDefaults.standard.string(forKey: nameKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty == false) ? s : nil
        }
        set {
            if let newValue, !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserDefaults.standard.set(newValue, forKey: nameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: nameKey)
            }
        }
    }

    /// Kept for older call sites.
    static var homePersonName: String? {
        get { mePersonName }
        set { mePersonName = newValue }
    }

    /// Generations above/below the centered person (1…5).
    static var generationDepth: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: generationsKey)
            return v == 0 ? 2 : min(max(v, 1), 5)
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 1), 5), forKey: generationsKey)
        }
    }

    static var showCousins: Bool {
        get {
            if UserDefaults.standard.object(forKey: showCousinsKey) == nil { return false }
            return UserDefaults.standard.bool(forKey: showCousinsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showCousinsKey) }
    }

    static var showAddParentCards: Bool {
        get {
            if UserDefaults.standard.object(forKey: showAddParentCardsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: showAddParentCardsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showAddParentCardsKey) }
    }

    static var colorCodeBranches: Bool {
        get {
            if UserDefaults.standard.object(forKey: colorCodeBranchesKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: colorCodeBranchesKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: colorCodeBranchesKey) }
    }

    static var showDeceasedRibbon: Bool {
        get {
            if UserDefaults.standard.object(forKey: showDeceasedRibbonKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: showDeceasedRibbonKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showDeceasedRibbonKey) }
    }

    static func setMe(_ person: FamilyPerson) {
        let name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        mePersonName = name.isEmpty ? nil : name
    }

    static func setHome(_ person: FamilyPerson) {
        setMe(person)
    }
}


// MARK: - Ego-centric visual tree (MyHeritage-style family view)

struct FamilyEgoTreeView: View {
    let graph: FamilyEgoGraph
    let universe: [FamilyPerson]
    var mePerson: FamilyPerson?
    var showAddParentCards: Bool = true
    var colorCodeBranches: Bool = true
    var showDeceasedRibbon: Bool = true
    var onFocus: (FamilyPerson) -> Void
    var onShowProfile: (FamilyPerson) -> Void
    var onSetMe: (FamilyPerson) -> Void
    var onAddParent: ((FamilyPerson, Bool) -> Void)?
    var mePersonName: String?

    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    treeCanvas
                        .padding(.vertical, 24)
                        .padding(.horizontal, 20)
                        .scaleEffect(zoom, anchor: .top)
                        .frame(
                            minWidth: max(0, geo.size.width),
                            minHeight: max(0, geo.size.height * 0.85),
                            alignment: .top
                        )
                        .id("ego-focus")
                }
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = min(max(zoomAtGestureStart * value.magnification, 0.55), 1.9)
                        }
                        .onEnded { _ in
                            zoomAtGestureStart = zoom
                        }
                )
                .onAppear {
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo("ego-focus", anchor: .center)
                        }
                    }
                }
                .onChange(of: graph.focus.persistentModelID) { _, _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("ego-focus", anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var treeCanvas: some View {
        VStack(spacing: 0) {
            if graph.hasAncestors {
                ancestorBlock
                TreeConnectorLineDown()
            }
            homeGenerationRow
            if graph.hasDescendants {
                TreeConnectorLineDown()
                descendantsRow
            }
        }
    }

    /// Older generations on top; parents immediately above the home row.
    private var ancestorBlock: some View {
        let gens = graph.ancestorGenerations
        return VStack(spacing: 10) {
            ForEach(Array(gens.indices.reversed()), id: \.self) { idx in
                let row = gens[idx]
                let isParentRow = idx == 0
                let hasPeople = row.contains { $0 != nil }
                let showAdds = isParentRow && showAddParentCards && (graph.missingMother || graph.missingFather)
                if hasPeople || showAdds {
                    pedigreeRowView(row, isParentRow: isParentRow)
                    if idx > 0 {
                        TreeConnectorLineDown()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pedigreeRowView(_ row: [FamilyPerson?], isParentRow: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(0..<max(row.count / 2, 1), id: \.self) { coupleIndex in
                let i = coupleIndex * 2
                let left = i < row.count ? row[i] : nil
                let right = i + 1 < row.count ? row[i + 1] : nil
                let showAddMother = isParentRow && coupleIndex == 0 && showAddParentCards && graph.missingMother && left == nil
                let showAddFather = isParentRow && coupleIndex == 0 && showAddParentCards && graph.missingFather && right == nil

                if coupleIndex > 0, left != nil || right != nil {
                    Spacer().frame(width: 6)
                }

                if showAddMother {
                    addParentCard(asMother: true)
                } else if let left {
                    personCard(left, emphasized: false)
                }

                let showHeart = (left != nil || showAddMother) && (right != nil || showAddFather)
                if showHeart {
                    ParentPartnershipBadge()
                }

                if showAddFather {
                    addParentCard(asMother: false)
                } else if let right {
                    personCard(right, emphasized: false)
                }
            }
        }
    }

    private var homeGenerationRow: some View {
        HStack(alignment: .top, spacing: 12) {
            if !graph.cousins.isEmpty {
                HStack(spacing: 8) {
                    ForEach(graph.cousins, id: \.persistentModelID) { cousin in
                        personCard(cousin, emphasized: false, compact: true)
                    }
                }
            }

            if !graph.siblings.isEmpty {
                HStack(spacing: 8) {
                    ForEach(graph.siblings, id: \.persistentModelID) { sibling in
                        personCard(sibling, emphasized: false, compact: true)
                    }
                }
            }

            HStack(alignment: .center, spacing: 8) {
                personCard(graph.focus, emphasized: true)
                if let partner = graph.partner {
                    ParentPartnershipBadge()
                    personCard(partner, emphasized: false)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SimpsonsTheme.orange.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SimpsonsTheme.orange.opacity(0.35), lineWidth: 1.5)
            )
        }
    }

    private var descendantsRow: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(graph.childNodes) { node in
                FamilyTreeNodeColumn(
                    node: node,
                    focusID: graph.focus.persistentModelID,
                    universe: universe,
                    mePerson: mePerson,
                    colorCodeBranches: colorCodeBranches,
                    showDeceasedRibbon: showDeceasedRibbon,
                    onFocus: onFocus,
                    onShowProfile: onShowProfile,
                    onSetMe: onSetMe,
                    mePersonName: mePersonName
                )
            }
        }
    }

    private func addParentCard(asMother: Bool) -> some View {
        Button {
            onAddParent?(graph.focus, asMother)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(SimpsonsTheme.blue.opacity(0.55))
                        .frame(width: 72, height: 88)
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SimpsonsTheme.blue)
                }
                Text(asMother
                     ? String(localized: "family_tree.add_mother")
                     : String(localized: "family_tree.add_father"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SimpsonsTheme.blue)
                    .multilineTextAlignment(.center)
                    .frame(width: 88)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground).opacity(0.65))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(asMother
            ? String(localized: "family_tree.add_mother")
            : String(localized: "family_tree.add_father"))
    }

    private func personCard(
        _ person: FamilyPerson,
        emphasized: Bool,
        compact: Bool = false
    ) -> some View {
        FamilyTreePersonCard(
            person: person,
            roleLabel: displayRole(for: person),
            isFocused: emphasized,
            isMe: isMe(person),
            compact: compact,
            colorCodeBranches: colorCodeBranches,
            showDeceasedRibbon: showDeceasedRibbon,
            onTap: {
                if person.persistentModelID == graph.focus.persistentModelID {
                    onShowProfile(person)
                } else {
                    onFocus(person)
                }
            },
            onShowProfile: { onShowProfile(person) },
            onSetMe: { onSetMe(person) }
        )
    }

    private func displayRole(for person: FamilyPerson) -> String? {
        if let mePerson {
            let kin = FamilyKinship.label(of: person, relativeTo: mePerson, among: universe)
            if kin == String(localized: "kinship.relative")
                || kin == String(localized: "kinship.extended") {
                let custom = person.familyRelationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                if !custom.isEmpty { return custom }
            }
            return kin
        }
        return nil
    }

    private func isMe(_ person: FamilyPerson) -> Bool {
        guard let mePersonName else { return false }
        return person.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(mePersonName) == .orderedSame
    }
}

private struct FamilyTreeNodeColumn: View {
    let node: FamilyTreeNode
    var focusID: PersistentIdentifier
    var universe: [FamilyPerson]
    var mePerson: FamilyPerson?
    var colorCodeBranches: Bool
    var showDeceasedRibbon: Bool
    var onFocus: (FamilyPerson) -> Void
    var onShowProfile: (FamilyPerson) -> Void
    var onSetMe: (FamilyPerson) -> Void
    var mePersonName: String?

    var body: some View {
        VStack(spacing: 0) {
            if let co = node.coParent {
                HStack(alignment: .center, spacing: 6) {
                    card(node.person)
                    ParentPartnershipBadge()
                    card(co)
                }
            } else {
                card(node.person)
            }

            if !node.children.isEmpty {
                TreeConnectorLineDown()
                HStack(alignment: .top, spacing: 12) {
                    ForEach(node.children) { child in
                        FamilyTreeNodeColumn(
                            node: child,
                            focusID: focusID,
                            universe: universe,
                            mePerson: mePerson,
                            colorCodeBranches: colorCodeBranches,
                            showDeceasedRibbon: showDeceasedRibbon,
                            onFocus: onFocus,
                            onShowProfile: onShowProfile,
                            onSetMe: onSetMe,
                            mePersonName: mePersonName
                        )
                    }
                }
            }
        }
    }

    private func card(_ person: FamilyPerson) -> some View {
        let role: String?
        if let mePerson {
            role = FamilyKinship.label(of: person, relativeTo: mePerson, among: universe)
        } else {
            role = nil
        }
        return FamilyTreePersonCard(
            person: person,
            roleLabel: role,
            isFocused: person.persistentModelID == focusID,
            isMe: isMe(person),
            compact: false,
            colorCodeBranches: colorCodeBranches,
            showDeceasedRibbon: showDeceasedRibbon,
            onTap: {
                if person.persistentModelID == focusID {
                    onShowProfile(person)
                } else {
                    onFocus(person)
                }
            },
            onShowProfile: { onShowProfile(person) },
            onSetMe: { onSetMe(person) }
        )
    }

    private func isMe(_ person: FamilyPerson) -> Bool {
        guard let mePersonName else { return false }
        return person.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(mePersonName) == .orderedSame
    }
}

private struct ParentPartnershipBadge: View {
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundStyle(SimpsonsTheme.pink)
            Rectangle()
                .fill(SimpsonsTheme.orange.opacity(0.45))
                .frame(width: 20, height: 2)
        }
        .accessibilityLabel(String(localized: "family_tree.partners_a11y"))
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
    var isFocused: Bool = false
    var isMe: Bool = false
    var compact: Bool = false
    var colorCodeBranches: Bool = true
    var showDeceasedRibbon: Bool = true
    var onTap: () -> Void
    var onShowProfile: () -> Void
    var onSetMe: () -> Void

    private var photoWidth: CGFloat { compact ? 64 : (isFocused ? 78 : 72) }
    private var photoHeight: CGFloat { compact ? 78 : (isFocused ? 96 : 88) }
    private var cardWidth: CGFloat { compact ? 80 : (isFocused ? 96 : 90) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    FamilyTreeAvatar(photoData: person.photoData, name: person.displayName, cornerRadius: 10)
                        .frame(width: photoWidth, height: photoHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if person.isDeceased, showDeceasedRibbon {
                        DeceasedRibbon()
                            .frame(width: photoWidth * 0.55, height: photoHeight * 0.28)
                    }

                    if isMe {
                        Image(systemName: "person.crop.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, SimpsonsTheme.blue)
                            .font(.system(size: compact ? 14 : 16))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .offset(x: 4, y: -4)
                            .accessibilityLabel(String(localized: "kinship.you"))
                    }
                }
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(genderAccent)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                }

                VStack(spacing: 2) {
                    if let roleLabel {
                        Text(roleLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isMe ? SimpsonsTheme.blue : .secondary)
                            .lineLimit(1)
                    }
                    Text(displayName)
                        .font(isFocused ? .caption.weight(.bold) : .caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .foregroundStyle(person.isDeceased ? .secondary : .primary)
                    if let years = lifeYearsText {
                        Text(years)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(width: cardWidth)
            }
            .frame(width: cardWidth)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
            )
            .shadow(color: isFocused ? SimpsonsTheme.orange.opacity(0.22) : .clear, radius: 6, y: 2)
            .opacity(person.isDeceased ? 0.92 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "family_tree.card_tap_hint"))
        .contextMenu {
            Button(action: onShowProfile) {
                Label(String(localized: "family_tree.view_profile"), systemImage: "person.crop.circle")
            }
            Button(action: onTap) {
                Label(String(localized: "family_tree.center_in_tree"), systemImage: "scope")
            }
            Button(action: onSetMe) {
                Label(String(localized: "family_tree.this_is_me"), systemImage: "person.fill.checkmark")
            }
            .disabled(isMe)
        }
    }

    private var displayName: String {
        let n = person.displayFirstName
        return n.isEmpty ? String(localized: "common.unnamed") : n
    }

    private var lifeYearsText: String? {
        let birthY: String? = person.birthDate.map { $0.formatted(.dateTime.year()) }
        if person.isDeceased {
            let deathY = person.deathDate.map { $0.formatted(.dateTime.year()) }
            if let birthY, let deathY { return "\(birthY)–\(deathY)" }
            if let birthY { return "\(birthY)–†" }
            if let deathY { return "† \(deathY)" }
            return "†"
        }
        return birthY
    }

    private var genderAccent: Color {
        switch FamilyKinship.inferredSex(of: person) {
        case .female: return SimpsonsTheme.pink.opacity(0.85)
        case .male: return SimpsonsTheme.blue.opacity(0.85)
        case .unknown: return Color.secondary.opacity(0.35)
        }
    }

    private var cardBackground: Color {
        if colorCodeBranches {
            return branchTint.opacity(0.18)
        }
        return Color(.secondarySystemGroupedBackground)
    }

    private var branchTint: Color {
        switch person.branch {
        case .ourHousehold: return SimpsonsTheme.orange
        case .myParentsLine: return SimpsonsTheme.blue
        case .spouseParentsLine: return SimpsonsTheme.pink
        case .extended: return SimpsonsTheme.purple
        }
    }

    private var borderColor: Color {
        if isMe { return SimpsonsTheme.blue.opacity(0.85) }
        if isFocused { return SimpsonsTheme.orange }
        if person.isDeceased { return Color.secondary.opacity(0.35) }
        return genderAccent.opacity(0.55)
    }
}

private struct DeceasedRibbon: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                path.closeSubpath()
            }
            .fill(Color.black.opacity(0.78))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

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
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let data = photoData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(SimpsonsTheme.orange.opacity(0.28))
                    Text(initials(from: name))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SimpsonsTheme.charcoal)
                }
            }
        }
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
