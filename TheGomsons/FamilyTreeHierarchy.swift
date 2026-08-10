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

/// Person-centered snapshot: ancestors above, focus (+ partner) in the middle, siblings beside, descendants below.
struct FamilyEgoGraph: Identifiable {
    var id: PersistentIdentifier { focus.persistentModelID }
    var focus: FamilyPerson
    var partner: FamilyPerson?
    var mother: FamilyPerson?
    var father: FamilyPerson?
    var maternalGrandmother: FamilyPerson?
    var maternalGrandfather: FamilyPerson?
    var paternalGrandmother: FamilyPerson?
    var paternalGrandfather: FamilyPerson?
    var siblings: [FamilyPerson]
    var childNodes: [FamilyTreeNode]

    var hasAncestors: Bool {
        mother != nil || father != nil
            || maternalGrandmother != nil || maternalGrandfather != nil
            || paternalGrandmother != nil || paternalGrandfather != nil
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
        descendantGenerations: Int = 2
    ) -> FamilyEgoGraph {
        let ids = Set(universe.map(\.persistentModelID))
        let ancDepth = max(1, min(ancestorGenerations, 3))
        let descDepth = max(1, min(descendantGenerations, 3))

        func inUniverse(_ p: FamilyPerson?) -> FamilyPerson? {
            guard let p, ids.contains(p.persistentModelID) else { return nil }
            return p
        }

        let mother = inUniverse(focus.mother)
        let father = inUniverse(focus.father)
        let partner = inUniverse(focus.resolvedPartner)

        var matGM: FamilyPerson?
        var matGF: FamilyPerson?
        var patGM: FamilyPerson?
        var patGF: FamilyPerson?
        if ancDepth >= 2 {
            matGM = inUniverse(mother?.mother)
            matGF = inUniverse(mother?.father)
            patGM = inUniverse(father?.mother)
            patGF = inUniverse(father?.father)
        }

        let focusID = focus.persistentModelID
        let partnerID = partner?.persistentModelID
        let siblings = focus.resolvedSiblings(among: universe)
            .filter { $0.persistentModelID != focusID && $0.persistentModelID != partnerID }
            .sorted { $0.sortOrder < $1.sortOrder }

        var primarySeen = Set<PersistentIdentifier>([focusID])
        if let partnerID { primarySeen.insert(partnerID) }

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
            mother: mother,
            father: father,
            maternalGrandmother: matGM,
            maternalGrandfather: matGF,
            paternalGrandmother: patGM,
            paternalGrandfather: patGF,
            siblings: siblings,
            childNodes: childNodes
        )
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

    static var generationDepth: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: generationsKey)
            return v == 0 ? 2 : min(max(v, 1), 3)
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 1), 3), forKey: generationsKey)
        }
    }

    static func setMe(_ person: FamilyPerson) {
        let name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        mePersonName = name.isEmpty ? nil : name
    }

    static func setHome(_ person: FamilyPerson) {
        setMe(person)
    }
}

// MARK: - Ego-centric visual tree

struct FamilyEgoTreeView: View {
    let graph: FamilyEgoGraph
    /// Full universe used for kinship labels (branch + search filtered).
    let universe: [FamilyPerson]
    /// Selected “me” — labels are relative to this person.
    var mePerson: FamilyPerson?
    var onFocus: (FamilyPerson) -> Void
    var onShowProfile: (FamilyPerson) -> Void
    var onSetMe: (FamilyPerson) -> Void
    var mePersonName: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        if graph.hasAncestors {
                            ancestorBlock
                            TreeConnectorLineDown()
                        }

                        focusRow
                            .id("ego-focus")

                        if !graph.siblings.isEmpty {
                            siblingsRow
                        }

                        if graph.hasDescendants {
                            TreeConnectorLineDown()
                            descendantsRow
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 16)
                    .frame(minWidth: UIScreen.main.bounds.width - 24)
                }
            }
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

    @ViewBuilder
    private var ancestorBlock: some View {
        VStack(spacing: 10) {
            if hasAnyGrandparents {
                HStack(alignment: .top, spacing: 28) {
                    grandparentCouple(
                        left: graph.maternalGrandmother,
                        right: graph.maternalGrandfather,
                        label: "Mother’s parents"
                    )
                    grandparentCouple(
                        left: graph.paternalGrandmother,
                        right: graph.paternalGrandfather,
                        label: "Father’s parents"
                    )
                }
                if graph.mother != nil || graph.father != nil {
                    TreeConnectorLineDown()
                }
            }

            if graph.mother != nil || graph.father != nil {
                HStack(alignment: .center, spacing: 8) {
                    if let mother = graph.mother {
                        personCard(mother, role: "Mother", emphasized: false)
                    }
                    if graph.mother != nil, graph.father != nil {
                        ParentPartnershipBadge()
                    }
                    if let father = graph.father {
                        personCard(father, role: "Father", emphasized: false)
                    }
                }
            }
        }
    }

    private var hasAnyGrandparents: Bool {
        graph.maternalGrandmother != nil || graph.maternalGrandfather != nil
            || graph.paternalGrandmother != nil || graph.paternalGrandfather != nil
    }

    @ViewBuilder
    private func grandparentCouple(left: FamilyPerson?, right: FamilyPerson?, label: String) -> some View {
        if left != nil || right != nil {
            VStack(spacing: 6) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    if let left {
                        personCard(left, role: nil, emphasized: false, compact: true)
                    }
                    if left != nil, right != nil {
                        ParentPartnershipBadge()
                    }
                    if let right {
                        personCard(right, role: nil, emphasized: false, compact: true)
                    }
                }
            }
        }
    }

    private var focusRow: some View {
        VStack(spacing: 8) {
            Text("Centered on")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            HStack(alignment: .center, spacing: 10) {
                personCard(graph.focus, role: nil, emphasized: true)
                if let partner = graph.partner {
                    ParentPartnershipBadge()
                    personCard(partner, role: partnerRoleLabel, emphasized: false)
                }
            }
            Button {
                onShowProfile(graph.focus)
            } label: {
                Label("View profile", systemImage: "person.crop.circle")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SimpsonsTheme.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SimpsonsTheme.orange.opacity(0.35), lineWidth: 1.5)
        )
    }

    private var partnerRoleLabel: String? {
        graph.focus.displayPartnerStatus?.displayTitle
    }

    private var siblingsRow: some View {
        VStack(spacing: 6) {
            Text("Siblings")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(graph.siblings, id: \.persistentModelID) { sibling in
                        personCard(sibling, role: "Sibling", emphasized: false, compact: true)
                    }
                }
                .padding(.horizontal, 4)
            }
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
                    onFocus: onFocus,
                    onShowProfile: onShowProfile,
                    onSetMe: onSetMe,
                    mePersonName: mePersonName
                )
            }
        }
    }

    private func personCard(
        _ person: FamilyPerson,
        role: String?,
        emphasized: Bool,
        compact: Bool = false
    ) -> some View {
        FamilyTreePersonCard(
            person: person,
            roleLabel: displayRole(for: person, structural: role),
            showsPartnerCaption: false,
            isFocused: emphasized,
            isMe: isMe(person),
            compact: compact,
            onTap: { onFocus(person) },
            onShowProfile: { onShowProfile(person) },
            onSetMe: { onSetMe(person) }
        )
    }

    /// Prefer kinship-to-me labels; fall back to structural Mother/Father when “me” isn’t set.
    private func displayRole(for person: FamilyPerson, structural: String?) -> String? {
        if let mePerson {
            return FamilyKinship.label(of: person, relativeTo: mePerson, among: universe)
        }
        return structural
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
    var onFocus: (FamilyPerson) -> Void
    var onShowProfile: (FamilyPerson) -> Void
    var onSetMe: (FamilyPerson) -> Void
    var mePersonName: String?

    var body: some View {
        VStack(spacing: 0) {
            if let co = node.coParent {
                let sampleChild = node.children.first?.person
                HStack(alignment: .center, spacing: 6) {
                    card(node.person, structural: parentalRoleLabel(adult: node.person, sampleChild: sampleChild))
                    ParentPartnershipBadge()
                    card(co, structural: parentalRoleLabel(adult: co, sampleChild: sampleChild))
                }
            } else {
                card(node.person, structural: nil)
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

    private func card(_ person: FamilyPerson, structural: String?) -> some View {
        let role: String?
        if let mePerson {
            role = FamilyKinship.label(of: person, relativeTo: mePerson, among: universe)
        } else {
            role = structural
        }
        return FamilyTreePersonCard(
            person: person,
            roleLabel: role,
            showsPartnerCaption: false,
            isFocused: person.persistentModelID == focusID,
            isMe: isMe(person),
            compact: false,
            onTap: { onFocus(person) },
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
        .accessibilityLabel("Partners")
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
    var showsPartnerCaption: Bool = true
    var isFocused: Bool = false
    var isMe: Bool = false
    var compact: Bool = false
    var onTap: () -> Void
    var onShowProfile: () -> Void
    var onSetMe: () -> Void

    private var avatarSize: CGFloat { compact ? 56 : (isFocused ? 88 : 72) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    FamilyTreeAvatar(photoData: person.photoData, name: person.displayName)
                        .frame(width: avatarSize, height: avatarSize)
                    if isMe {
                        Image(systemName: "person.crop.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, SimpsonsTheme.blue)
                            .font(.system(size: compact ? 14 : 16))
                            .offset(x: 4, y: -4)
                            .accessibilityLabel("This is you")
                    }
                }
                if let roleLabel {
                    Text(roleLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            roleLabel == "You"
                                ? SimpsonsTheme.blue
                                : SimpsonsTheme.charcoal.opacity(0.55)
                        )
                }
                Text(person.displayName.isEmpty ? "Name" : person.displayName)
                    .font(isFocused ? .subheadline.weight(.bold) : .caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(minWidth: compact ? 72 : 88, maxWidth: isFocused ? 140 : 128)
                    .foregroundStyle(person.isDeceased ? .secondary : .primary)
                if person.isDeceased {
                    DeceasedCrossMark(font: .caption.weight(.semibold))
                }
                if showsPartnerCaption, let partner = person.resolvedPartner {
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
                } else if let birth = person.birthDate {
                    Text(birth, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(isFocused ? 12 : 10)
            .opacity(person.isDeceased ? 0.85 : 1)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: isFocused ? 2.5 : 1.5)
            )
            .shadow(color: isFocused ? SimpsonsTheme.orange.opacity(0.25) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Double-tap to center this person in the tree")
        .contextMenu {
            Button(action: onShowProfile) {
                Label("View profile", systemImage: "person.crop.circle")
            }
            Button(action: onTap) {
                Label("Center in tree", systemImage: "scope")
            }
            Button(action: onSetMe) {
                Label(isMe ? "This is you" : "This is me", systemImage: "person.fill.checkmark")
            }
            .disabled(isMe)
        }
    }

    private var borderColor: Color {
        if isMe { return SimpsonsTheme.blue.opacity(0.85) }
        if isFocused { return SimpsonsTheme.orange }
        if person.isDeceased { return Color.secondary.opacity(0.35) }
        return SimpsonsTheme.orange.opacity(0.4)
    }

    private func partnerFirstName(_ partner: FamilyPerson) -> String {
        let name = partner.displayFirstName
        return name.isEmpty ? String(localized: "common.unnamed") : name
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
