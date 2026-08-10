//
//  FamilyTreeView.swift
//  TheGomsons
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FamilyTreeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openFamilyLanding) private var openFamilyLanding
    @Query(sort: \FamilyPerson.sortOrder) private var allPeople: [FamilyPerson]

    @State private var branchFilter: BranchFilter = .all
    @State private var searchText = ""
    @State private var mode: TreeDisplayMode = .tree
    @State private var selectedPerson: FamilyPerson?
    /// Person currently at the center of the ego-centric tree.
    @State private var focusPerson: FamilyPerson?
    /// Selected “me” person name (relationship labels are relative to them).
    @State private var mePersonName: String? = FamilyTreeHomePersonStore.mePersonName
    @State private var generationDepth: Int = FamilyTreeHomePersonStore.generationDepth
    @State private var showPickMe = false
    @State private var showAddPerson = false
    @State private var showFamilyCSVImport = false
    @State private var familyImportAlert: String?

    enum BranchFilter: Int, CaseIterable {
        case all
        case ourHousehold
        case myLine
        case spouseLine
        case extended

        var title: String {
            switch self {
            case .all: String(localized: "family_tree.branch_all")
            case .ourHousehold: String(localized: "family_tree.branch_household")
            case .myLine: String(localized: "family_tree.branch_my_line")
            case .spouseLine: String(localized: "family_tree.branch_spouse")
            case .extended: String(localized: "family_tree.branch_extended")
            }
        }

        func matches(_ branch: FamilyTreeBranch) -> Bool {
            switch self {
            case .all: true
            case .ourHousehold: branch == .ourHousehold
            case .myLine: branch == .myParentsLine
            case .spouseLine: branch == .spouseParentsLine
            case .extended: branch == .extended
            }
        }
    }

    enum TreeDisplayMode: Int, CaseIterable {
        case tree
        case list
        case map
        case photos

        var title: String {
            switch self {
            case .tree: String(localized: "family_tree.view_tree")
            case .list: String(localized: "family_tree.view_list")
            case .map: String(localized: "family_tree.view_map")
            case .photos: String(localized: "family_tree.view_photos")
            }
        }
    }

    /// Branch filter + optional search (names & notes); search also pulls in ancestors and descendants.
    private var treeUniverse: [FamilyPerson] {
        FamilyTreeHierarchyBuilder.visibleUniverse(
            from: allPeople,
            branchMatches: { branchFilter.matches($0) },
            search: searchText
        )
    }

    private var filteredPeopleForList: [FamilyPerson] {
        let u = treeUniverse
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return u.sorted { lhs, rhs in
                if lhs.treeTier != rhs.treeTier { return lhs.treeTier < rhs.treeTier }
                return lhs.sortOrder < rhs.sortOrder
            }
        }
        return u.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var resolvedFocus: FamilyPerson? {
        if let focusPerson,
           treeUniverse.contains(where: { $0.persistentModelID == focusPerson.persistentModelID }) {
            return focusPerson
        }
        return FamilyTreeHierarchyBuilder.defaultFocus(
            in: treeUniverse,
            preferredHomeName: mePersonName
        )
    }

    /// Resolved “me” for kinship labels (may be outside current branch filter — use allPeople).
    private var mePerson: FamilyPerson? {
        guard let mePersonName else { return nil }
        let key = mePersonName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allPeople.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
        }
    }

    private var egoGraph: FamilyEgoGraph? {
        guard let focus = resolvedFocus else { return nil }
        return FamilyTreeHierarchyBuilder.buildEgoGraph(
            focus: focus,
            universe: treeUniverse,
            ancestorGenerations: generationDepth,
            descendantGenerations: generationDepth
        )
    }

    /// Next upcoming birthdays for the social strip (prefer calendar-included; fall back to all).
    private var upcomingBirthdays: [(person: FamilyPerson, next: Date, days: Int)] {
        let now = Date()
        func ranked(from people: [FamilyPerson]) -> [(person: FamilyPerson, next: Date, days: Int)] {
            people.compactMap { p -> (FamilyPerson, Date, Int)? in
                guard let next = p.nextBirthdayOccurrence(after: now),
                      let days = p.daysUntilNextBirthday(after: now) else { return nil }
                return (p, next, days)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(8)
            .map { ($0.0, $0.1, $0.2) }
        }
        let preferred = ranked(from: allPeople.filter { $0.includeBirthdayOnCalendar && !$0.isDeceased })
        if !preferred.isEmpty { return preferred }
        return ranked(from: allPeople.filter { !$0.isDeceased })
    }

    var body: some View {
        NavigationStack {
            Group {
                if allPeople.isEmpty {
                    ContentUnavailableView(
                        String(localized: "family_tree.empty"),
                        systemImage: "person.3.sequence",
                        description: Text(String(localized: "family_tree.empty.detail"))
                    )
                } else {
                    VStack(spacing: 0) {
                        if !upcomingBirthdays.isEmpty {
                            UpcomingBirthdaysStrip(items: upcomingBirthdays) { person in
                                selectedPerson = person
                            }
                        }

                        Picker(String(localized: "common.view"), selection: $mode) {
                            ForEach(TreeDisplayMode.allCases, id: \.self) { m in
                                Text(m.title).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 8)

                        Picker(String(localized: "common.branch"), selection: $branchFilter) {
                            ForEach(BranchFilter.allCases, id: \.self) { f in
                                Text(f.title).tag(f)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal)
                        .padding(.vertical, 6)

                        if mode == .tree {
                            treeFocusControls
                        }

                        switch mode {
                        case .tree:
                            treeScroll
                        case .list:
                            listPanel
                        case .map:
                            FamilyTreeCityMapView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .photos:
                            FamilyGroupPhotosView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "family_tree.title"))
            .onAppear {
                FamilyCalendarNotifications.rescheduleAllPersonBirthdays(allPeople)
                syncFocusIfNeeded()
            }
            .onChange(of: allPeople.count) { _, _ in
                syncFocusIfNeeded()
            }
            .onChange(of: branchFilter) { _, _ in
                syncFocusIfNeeded()
            }
            .onChange(of: searchText) { _, _ in
                syncFocusIfNeeded()
            }
            .searchable(text: $searchText, prompt: String(localized: "family_tree.search_prompt"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Menu {
                            Button {
                                showFamilyCSVImport = true
                            } label: {
                                Label(String(localized: "family_tree.import_csv"), systemImage: "square.and.arrow.down")
                            }
                            ShareLink(
                                item: familyTreeTemplateFileURL(),
                                subject: Text(String(localized: "family_tree.import_template")),
                                message: Text(String(localized: "family_tree.import_template_message"))
                            ) {
                                Label(String(localized: "family_tree.import_template"), systemImage: "doc.plaintext")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityLabel(String(localized: "family_tree.import_menu_a11y"))

                        Button {
                            showAddPerson = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityLabel(String(localized: "family_tree.add_person"))
                    }
                }
            }
            .fileImporter(
                isPresented: $showFamilyCSVImport,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        await importFamilyCSV(from: url)
                    }
                case .failure(let err):
                    familyImportAlert = err.localizedDescription
                }
            }
            .alert(
                String(localized: "family_tree.import_result_title"),
                isPresented: Binding(
                    get: { familyImportAlert != nil },
                    set: { if !$0 { familyImportAlert = nil } }
                ),
                actions: { Button(String(localized: "common.ok"), role: .cancel) { familyImportAlert = nil } },
                message: { Text(familyImportAlert ?? "") }
            )
            .sheet(isPresented: $showAddPerson) {
                NavigationStack {
                    FamilyPersonEditorView(
                        person: nil,
                        allPeople: allPeople,
                        onSave: { _ in showAddPerson = false },
                        onCancel: { showAddPerson = false }
                    )
                }
            }
            .sheet(item: $selectedPerson) { person in
                NavigationStack {
                    FamilyPersonProfileView(
                        person: person,
                        onDone: { selectedPerson = nil },
                        onSelectRelated: { related in
                            selectedPerson = related
                        },
                        onCenterInTree: { related in
                            selectedPerson = nil
                            mode = .tree
                            withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                                focusPerson = related
                            }
                        },
                        onSetMe: { person in
                            FamilyTreeHomePersonStore.setMe(person)
                            mePersonName = FamilyTreeHomePersonStore.mePersonName
                        },
                        onDeleted: {
                            selectedPerson = nil
                            mePersonName = FamilyTreeHomePersonStore.mePersonName
                        }
                    )
                }
            }
        }
    }

    private var treeFocusControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    showPickMe = true
                } label: {
                    Label(
                        mePerson.map { "Me: \($0.displayName.isEmpty ? $0.name : $0.displayName)" } ?? "Who am I?",
                        systemImage: "person.fill.checkmark"
                    )
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .tint(mePerson == nil ? SimpsonsTheme.orange : SimpsonsTheme.blue)
                .controlSize(.small)

                Button {
                    goToMePerson()
                } label: {
                    Label("Center on me", systemImage: "scope")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(mePerson == nil)

                Spacer(minLength: 4)

                Text("Gens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Generations", selection: $generationDepth) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 120)
                .onChange(of: generationDepth) { _, newValue in
                    FamilyTreeHomePersonStore.generationDepth = newValue
                }
            }

            if mePerson == nil {
                Text("Choose yourself so others are labeled Uncle, Grandmother, Cousin, …")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
        .sheet(isPresented: $showPickMe) {
            NavigationStack {
                List {
                    Section {
                        Text("Relationship labels (Uncle, Grandfather, …) are shown relative to the person you pick.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("I am…") {
                        ForEach(allPeople.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, id: \.persistentModelID) { person in
                            Button {
                                FamilyTreeHomePersonStore.setMe(person)
                                mePersonName = FamilyTreeHomePersonStore.mePersonName
                                withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                                    focusPerson = person
                                }
                                showPickMe = false
                            } label: {
                                HStack {
                                    FamilyPersonAvatar(photoData: person.photoData, name: person.displayName)
                                        .frame(width: 36, height: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.displayName.isEmpty ? String(localized: "common.unnamed") : person.displayName)
                                            .foregroundStyle(.primary)
                                        if person.hasPreferredName, !person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(person.name)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        Text(person.branch.displayTitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if isMeName(person.name) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(SimpsonsTheme.blue)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Who am I?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showPickMe = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func isMeName(_ name: String) -> Bool {
        guard let mePersonName else { return false }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(mePersonName) == .orderedSame
    }

    private var treeScroll: some View {
        Group {
            if let egoGraph {
                FamilyEgoTreeView(
                    graph: egoGraph,
                    universe: treeUniverse,
                    mePerson: mePerson,
                    onFocus: { person in
                        withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                            focusPerson = person
                        }
                    },
                    onShowProfile: { person in
                        selectedPerson = person
                    },
                    onSetMe: { person in
                        FamilyTreeHomePersonStore.setMe(person)
                        mePersonName = FamilyTreeHomePersonStore.mePersonName
                        withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                            focusPerson = person
                        }
                    },
                    mePersonName: mePersonName
                )
            } else {
                ContentUnavailableView(
                    String(localized: "family_tree.no_matches"),
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(String(localized: "family_tree.try_branch"))
                )
                .frame(minHeight: 200)
            }
        }
    }

    private var listPanel: some View {
        Group {
            if filteredPeopleForList.isEmpty {
                ContentUnavailableView(
                    String(localized: "family_tree.no_matches"),
                    systemImage: "magnifyingglass",
                    description: Text(String(localized: "family_tree.try_branch"))
                )
            } else {
                List {
                    ForEach(filteredPeopleForList, id: \.persistentModelID) { person in
                        Button {
                            selectedPerson = person
                        } label: {
                            FamilyPersonRow(person: person, allPeople: allPeople, mePerson: mePerson)
                        }
                        .contextMenu {
                            Button {
                                mode = .tree
                                withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                                    focusPerson = person
                                }
                            } label: {
                                Label("Center in tree", systemImage: "scope")
                            }
                            Button {
                                FamilyTreeHomePersonStore.setMe(person)
                                mePersonName = FamilyTreeHomePersonStore.mePersonName
                            } label: {
                                Label("This is me", systemImage: "person.fill.checkmark")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func syncFocusIfNeeded() {
        if let focusPerson,
           treeUniverse.contains(where: { $0.persistentModelID == focusPerson.persistentModelID }) {
            return
        }
        focusPerson = FamilyTreeHierarchyBuilder.defaultFocus(
            in: treeUniverse,
            preferredHomeName: mePersonName
        )
    }

    private func goToMePerson() {
        if let me = mePerson {
            withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                focusPerson = me
            }
        } else if let home = FamilyTreeHierarchyBuilder.defaultFocus(
            in: treeUniverse,
            preferredHomeName: mePersonName
        ) {
            withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                focusPerson = home
            }
        }
    }

    private func familyTreeTemplateFileURL() -> URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FamilyTreeImportTemplate.csv")
        try? FamilyTreeCSVImport.templateFileContents.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    @MainActor
    private func importFamilyCSV(from url: URL) async {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let result = try FamilyTreeCSVImport.importCSV(
                data: data,
                modelContext: modelContext,
                existingPeople: allPeople
            )
            var msg = String(
                format: String(localized: "family_tree.import_ok_fmt"),
                locale: .current,
                result.added,
                result.linkedPartners
            )
            if !result.warnings.isEmpty {
                msg += "\n\n"
                msg += String(localized: "family_tree.import_warnings_header")
                msg += "\n"
                msg += result.warnings.joined(separator: "\n")
            }
            familyImportAlert = msg
        } catch {
            familyImportAlert = error.localizedDescription
        }
    }
}

// MARK: - Upcoming birthdays

private struct UpcomingBirthdaysStrip: View {
    let items: [(person: FamilyPerson, next: Date, days: Int)]
    var onSelect: (FamilyPerson) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "family_tree.upcoming_birthdays"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items, id: \.person.persistentModelID) { item in
                        Button {
                            onSelect(item.person)
                        } label: {
                            VStack(spacing: 6) {
                                FamilyPersonAvatar(photoData: item.person.photoData, name: item.person.displayName)
                                    .frame(width: 52, height: 52)
                                Text(item.person.displayFirstName.isEmpty ? String(localized: "common.unnamed") : item.person.displayFirstName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(maxWidth: 72)
                                Text(daysLabel(item.days, date: item.next))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func daysLabel(_ days: Int, date: Date) -> String {
        if days == 0 {
            return String(localized: "family_tree.birthday_today")
        }
        if days == 1 {
            return String(localized: "family_tree.birthday_tomorrow")
        }
        if days <= 14 {
            return String(format: String(localized: "family_tree.birthday_in_days_fmt"), locale: .current, days)
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - List row

private struct FamilyPersonRow: View {
    let person: FamilyPerson
    let allPeople: [FamilyPerson]
    var mePerson: FamilyPerson?

    var body: some View {
        HStack(spacing: 12) {
            FamilyPersonAvatar(photoData: person.photoData, name: person.displayName)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(person.displayName.isEmpty ? String(localized: "common.untitled") : person.displayName)
                        .font(.headline)
                    if person.isDeceased {
                        DeceasedCrossMark(font: .headline)
                    }
                }
                if person.hasPreferredName, !person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(person.name)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let mePerson {
                    Text(FamilyKinship.label(of: person, relativeTo: mePerson, among: allPeople))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SimpsonsTheme.blue.opacity(0.85))
                }
                HStack(spacing: 8) {
                    if let d = person.birthDate {
                        Text(d, format: .dateTime.month().day().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(person.branch.displayTitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if person.isDeceased, let death = person.deathDate {
                    Text("† \(death.formatted(.dateTime.month().day().year()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            String(
                                format: String(localized: "family_tree.died_on_fmt"),
                                locale: .current,
                                death.formatted(.dateTime.month().day().year())
                            )
                        )
                }
                if let p = person.resolvedPartner, !p.displayName.isEmpty {
                    HStack(spacing: 4) {
                        Text(String(format: String(localized: "family_tree.partner"), locale: .current, p.displayName))
                        if let status = person.displayPartnerStatus {
                            Text("·")
                            Text(status.displayTitle)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                let siblings = person.resolvedSiblings(among: allPeople)
                if !siblings.isEmpty {
                    Text(
                        String(
                            format: String(localized: "family_tree.siblings_fmt"),
                            locale: .current,
                            siblings.prefix(3).map { $0.displayName.isEmpty ? String(localized: "common.unnamed") : $0.displayName }.joined(separator: ", ")
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                if !person.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(person.city)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !person.hobbies.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(person.hobbies)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FamilyPersonAvatar: View {
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
                    Circle().fill(SimpsonsTheme.orange.opacity(0.25))
                    Text(initials(from: name))
                        .font(.headline.weight(.bold))
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

// MARK: - Social profile

private struct FamilyPersonProfileView: View {
    @Query(sort: \FamilyPerson.sortOrder) private var allPeople: [FamilyPerson]

    let person: FamilyPerson
    var onDone: () -> Void
    var onSelectRelated: (FamilyPerson) -> Void
    var onCenterInTree: (FamilyPerson) -> Void
    var onSetMe: (FamilyPerson) -> Void
    var onDeleted: () -> Void

    @State private var showEditor = false

    private var titleName: String {
        let shown = person.displayName
        return shown.isEmpty ? String(localized: "common.unnamed") : shown
    }

    private var siblings: [FamilyPerson] {
        person.resolvedSiblings(among: allPeople)
    }

    private var children: [FamilyPerson] {
        FamilyTreeHierarchyBuilder.mergedChildren(for: person, in: allPeople)
    }

    private var otherPeople: [FamilyPerson] {
        allPeople.filter { $0.persistentModelID != person.persistentModelID }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    FamilyPersonAvatar(photoData: person.photoData, name: person.displayName)
                        .frame(width: 128, height: 128)
                    Text(titleName)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    if person.hasPreferredName, !person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(person.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if person.isDeceased {
                        DeceasedCrossMark(font: .title3.weight(.semibold))
                    }
                    HStack(spacing: 8) {
                        Text(person.branch.displayTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if !person.familyRelationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(person.familyRelationLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    onCenterInTree(person)
                } label: {
                    Label("Center in family tree", systemImage: "scope")
                }
                Button {
                    onSetMe(person)
                } label: {
                    Label("This is me", systemImage: "person.fill.checkmark")
                }
            }

            if person.mother != nil || person.father != nil {
                Section("Parents") {
                    if let mother = person.mother {
                        relatedPersonButton(mother, subtitle: "Mother")
                    }
                    if let father = person.father {
                        relatedPersonButton(father, subtitle: "Father")
                    }
                }
            }

            if person.birthDate != nil || person.isDeceased {
                Section(String(localized: "family_tree.profile_birthday")) {
                    if let birth = person.birthDate {
                        LabeledContent(String(localized: "event.kind.birthday")) {
                            Text(birth, format: .dateTime.month().day().year())
                        }
                    }
                    if person.isDeceased {
                        if let death = person.deathDate {
                            LabeledContent {
                                Text(death, format: .dateTime.month().day().year())
                            } label: {
                                HStack(spacing: 4) {
                                    DeceasedCrossMark(font: .body)
                                    Text(String(localized: "family_tree.death_date"))
                                }
                            }
                        }
                        if let age = person.ageAtDeath {
                            LabeledContent(String(localized: "family_tree.age_at_death")) {
                                Text("\(age)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if let days = person.daysUntilNextBirthday(), let next = person.nextBirthdayOccurrence(after: Date()) {
                        LabeledContent(String(localized: "family_tree.next_birthday")) {
                            Text(nextBirthdayText(days: days, date: next))
                                .foregroundStyle(.secondary)
                        }
                        if let age = person.ageOnBirthday(onCelebrationDay: next) {
                            LabeledContent(String(localized: "family_tree.turning_age")) {
                                Text("\(age)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let partner = person.resolvedPartner {
                Section(String(localized: "family_tree.profile_partner")) {
                    relatedPersonButton(partner, subtitle: person.displayPartnerStatus?.displayTitle)
                }
            }

            if !siblings.isEmpty {
                Section(String(localized: "family_tree.siblings")) {
                    ForEach(siblings, id: \.persistentModelID) { sibling in
                        relatedPersonButton(
                            sibling,
                            subtitle: person.sharesParent(with: sibling)
                                ? String(localized: "family_tree.sibling_via_parents")
                                : nil
                        )
                    }
                }
            }

            if !children.isEmpty {
                Section("Children") {
                    ForEach(children, id: \.persistentModelID) { child in
                        relatedPersonButton(child, subtitle: nil)
                    }
                }
            }

            if hasContactContent {
                Section(String(localized: "family_tree.contact_section")) {
                    if !person.mobile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let tel = FamilyContactURL.telephone(person.mobile) {
                            Link(destination: tel) {
                                Label(person.mobile, systemImage: "phone.fill")
                            }
                        } else {
                            Label(person.mobile, systemImage: "phone.fill")
                        }
                        if let sms = FamilyContactURL.sms(person.mobile) {
                            Link(destination: sms) {
                                Label(String(localized: "family_tree.message"), systemImage: "message.fill")
                            }
                        }
                    }
                    if !person.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let mail = FamilyContactURL.mailto(person.email) {
                            Link(destination: mail) {
                                Label(person.email, systemImage: "envelope.fill")
                            }
                        } else {
                            Label(person.email, systemImage: "envelope.fill")
                        }
                    }
                    if !person.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(person.city, systemImage: "mappin.and.ellipse")
                    }
                }
            }

            if !person.hobbies.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section(String(localized: "family_tree.hobbies")) {
                    Text(person.hobbies)
                }
            }

            if !person.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section(String(localized: "common.notes")) {
                    Text(person.notes)
                }
            }
        }
        .navigationTitle(String(localized: "family_tree.profile_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "common.done"), action: onDone)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(String(localized: "common.edit")) {
                    showEditor = true
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                FamilyPersonEditorView(
                    person: person,
                    allPeople: otherPeople,
                    onSave: { _ in showEditor = false },
                    onCancel: { showEditor = false },
                    onDeleted: {
                        showEditor = false
                        onDeleted()
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func relatedPersonButton(_ related: FamilyPerson, subtitle: String?) -> some View {
        Button {
            onSelectRelated(related)
        } label: {
            HStack(spacing: 12) {
                FamilyPersonAvatar(photoData: related.photoData, name: related.displayName)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(related.displayName.isEmpty ? String(localized: "common.unnamed") : related.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            Button {
                onCenterInTree(related)
            } label: {
                Label("Center in tree", systemImage: "scope")
            }
        }
    }

    private var hasContactContent: Bool {
        !person.mobile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !person.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !person.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func nextBirthdayText(days: Int, date: Date) -> String {
        if days == 0 {
            return String(localized: "family_tree.birthday_today")
        }
        if days == 1 {
            return String(localized: "family_tree.birthday_tomorrow")
        }
        return String(
            format: String(localized: "family_tree.birthday_next_fmt"),
            locale: .current,
            days,
            date.formatted(.dateTime.month(.abbreviated).day())
        )
    }
}

private enum FamilyContactURL {
    static func telephone(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digits = trimmed.filter { $0.isNumber || $0 == "+" }
        guard digits.count >= 3 else { return nil }
        return URL(string: "tel:" + digits)
    }

    static func sms(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digits = trimmed.filter { $0.isNumber || $0 == "+" }
        guard digits.count >= 3 else { return nil }
        return URL(string: "sms:" + digits)
    }

    static func mailto(_ email: String) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":/?#[]@!$&'()*+,;=")
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "mailto:" + encoded)
    }
}

// MARK: - Editor

private struct FamilyPersonEditorView: View {
    @Environment(\.modelContext) private var modelContext
    let person: FamilyPerson?
    let allPeople: [FamilyPerson]
    var onSave: (FamilyPerson) -> Void
    var onCancel: () -> Void
    var onDeleted: (() -> Void)? = nil

    @State private var draftName = ""
    @State private var draftPreferredName = ""
    @State private var draftBirth: Date = Date()
    @State private var hasBirth = false
    @State private var draftIncludeBirthdayOnCalendar = true
    @State private var draftIsDeceased = false
    @State private var draftDeath: Date = Date()
    @State private var hasDeathDate = false
    @State private var draftNotes = ""
    @State private var draftEmail = ""
    @State private var draftMobile = ""
    @State private var draftCity = ""
    @State private var draftHobbies = ""
    @State private var draftRelationLabel = ""
    @State private var draftTier = 2
    @State private var draftBranch: FamilyTreeBranch = .extended
    @State private var mother: FamilyPerson?
    @State private var father: FamilyPerson?
    @State private var partner: FamilyPerson?
    @State private var draftPartnerStatus: PartnerRelationshipStatus = .partner
    @State private var selectedSiblingIDs: Set<PersistentIdentifier> = []
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var confirmDeletePerson = false

    private var isNew: Bool { person == nil }

    private var deleteConfirmTitle: String {
        let fromPerson = person?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = fromPerson.isEmpty
            ? draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            : fromPerson
        let name = label.isEmpty ? String(localized: "common.unnamed") : label
        return String(format: String(localized: "family_tree.delete_person_confirm_title"), locale: .current, name)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Group {
                            if let data = photoData, let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                ZStack {
                                    Circle().fill(SimpsonsTheme.orange.opacity(0.2))
                                    Image(systemName: "camera.fill")
                                        .font(.title2)
                                        .foregroundStyle(SimpsonsTheme.charcoal.opacity(0.5))
                                }
                            }
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                    }
                    .onChange(of: photoItem) { _, new in
                        Task {
                            guard let new else { return }
                            if let data = try? await new.loadTransferable(type: Data.self) {
                                photoData = data
                            }
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)

                if photoData != nil {
                    Button(role: .destructive) {
                        photoData = nil
                        photoItem = nil
                    } label: {
                        Label(String(localized: "family_tree.remove_photo"), systemImage: "trash")
                    }
                }
            } header: {
                Text(String(localized: "family_tree.photo_section"))
            } footer: {
                Text(String(localized: "family_tree.photo_footer"))
            }

            Section {
                TextField(String(localized: "common.name"), text: $draftName)
                    .textContentType(.name)
                TextField(String(localized: "family_tree.preferred_name"), text: $draftPreferredName)
                    .textContentType(.nickname)
                Toggle(String(localized: "family_tree.birthday_toggle"), isOn: $hasBirth)
                if hasBirth {
                    DatePicker(String(localized: "event.kind.birthday"), selection: $draftBirth, displayedComponents: .date)
                    if !draftIsDeceased {
                        Toggle(String(localized: "family_tree.birthday_on_calendar"), isOn: $draftIncludeBirthdayOnCalendar)
                    }
                }
                Toggle(String(localized: "family_tree.deceased_toggle"), isOn: $draftIsDeceased)
                if draftIsDeceased {
                    Toggle(String(localized: "family_tree.death_date_toggle"), isOn: $hasDeathDate)
                    if hasDeathDate {
                        DatePicker(String(localized: "family_tree.death_date"), selection: $draftDeath, displayedComponents: .date)
                    }
                }
            } header: {
                Text(String(localized: "family_tree.profile_section"))
            } footer: {
                Text(String(localized: "family_tree.preferred_name_footer"))
            }

            Section {
                TextField(String(localized: "family_tree.contact_email"), text: $draftEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField(String(localized: "family_tree.contact_mobile"), text: $draftMobile)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                TextField(String(localized: "family_tree.city"), text: $draftCity)
                    .textInputAutocapitalization(.words)
            } header: {
                Text(String(localized: "family_tree.contact_section"))
            } footer: {
                Text(String(localized: "family_tree.city_map_footer"))
            }

            Section(String(localized: "family_tree.hobbies")) {
                TextField(String(localized: "family_tree.hobbies_placeholder"), text: $draftHobbies, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section(String(localized: "family_tree.relationships")) {
                Picker(String(localized: "family_tree.mother"), selection: $mother) {
                    Text("—").tag(nil as FamilyPerson?)
                    ForEach(allPeople, id: \.persistentModelID) { p in
                        Text(p.displayName.isEmpty ? String(localized: "common.unnamed") : p.displayName).tag(p as FamilyPerson?)
                    }
                }
                Picker(String(localized: "family_tree.father"), selection: $father) {
                    Text("—").tag(nil as FamilyPerson?)
                    ForEach(allPeople, id: \.persistentModelID) { p in
                        Text(p.displayName.isEmpty ? String(localized: "common.unnamed") : p.displayName).tag(p as FamilyPerson?)
                    }
                }
                Picker(String(localized: "family_tree.partner_picker"), selection: $partner) {
                    Text("—").tag(nil as FamilyPerson?)
                    ForEach(allPeople, id: \.persistentModelID) { p in
                        Text(p.displayName.isEmpty ? String(localized: "common.unnamed") : p.displayName).tag(p as FamilyPerson?)
                    }
                }
                if partner != nil {
                    Picker(String(localized: "family_tree.partner_status"), selection: $draftPartnerStatus) {
                        ForEach(PartnerRelationshipStatus.allCases, id: \.self) { status in
                            Text(status.displayTitle).tag(status)
                        }
                    }
                }
            }

            Section {
                if allPeople.isEmpty {
                    Text(String(localized: "family_tree.siblings_empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(allPeople, id: \.persistentModelID) { p in
                        let parentDerived = isParentDerivedSibling(p)
                        Toggle(isOn: siblingToggleBinding(for: p, parentDerived: parentDerived)) {
                            HStack {
                                Text(p.displayName.isEmpty ? String(localized: "common.unnamed") : p.displayName)
                                if parentDerived {
                                    Text(String(localized: "family_tree.sibling_via_parents"))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .disabled(parentDerived)
                    }
                }
            } header: {
                Text(String(localized: "family_tree.siblings"))
            } footer: {
                Text(String(localized: "family_tree.siblings_footer"))
            }

            Section {
                Stepper(
                    String(format: String(localized: "family_tree.tier_stepper"), locale: .current, draftTier),
                    value: $draftTier,
                    in: -2...8
                )
                Picker(String(localized: "common.branch"), selection: $draftBranch) {
                    ForEach(FamilyTreeBranch.allCases, id: \.self) { b in
                        Text(b.displayTitle).tag(b)
                    }
                }
                TextField(String(localized: "family_tree.relation_label"), text: $draftRelationLabel, axis: .vertical)
                    .lineLimit(1 ... 3)
            } header: {
                Text(String(localized: "family_tree.tree_layout"))
            } footer: {
                Text(String(localized: "family_tree.relation_label_footer"))
            }

            Section(String(localized: "common.notes")) {
                TextField(String(localized: "common.notes"), text: $draftNotes, axis: .vertical)
                    .lineLimit(3...8)
            }

            if !isNew {
                Section {
                    Button(role: .destructive) {
                        confirmDeletePerson = true
                    } label: {
                        Text(String(localized: "family_tree.delete_person"))
                    }
                } footer: {
                    Text(String(localized: "family_tree.delete_person_footer"))
                }
            }
        }
        .navigationTitle(isNew ? String(localized: "family_tree.new_person") : String(localized: "family_tree.edit_person"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "common.cancel"), action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "common.save")) {
                    save()
                }
                .fontWeight(.semibold)
            }
        }
        .confirmationDialog(
            deleteConfirmTitle,
            isPresented: $confirmDeletePerson,
            titleVisibility: .visible
        ) {
            Button(String(localized: "family_tree.delete_person_confirm_action"), role: .destructive) {
                performDelete()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "family_tree.delete_person_confirm_msg"))
        }
        .onAppear {
            guard let person else {
                draftTier = 2
                draftBranch = .ourHousehold
                return
            }
            draftName = person.name
            draftPreferredName = person.preferredName
            draftNotes = person.notes
            draftEmail = person.email
            draftMobile = person.mobile
            draftCity = person.city
            draftHobbies = person.hobbies
            draftRelationLabel = person.familyRelationLabel
            draftTier = person.treeTier
            draftBranch = person.branch
            if let b = person.birthDate {
                draftBirth = b
                hasBirth = true
            }
            draftIncludeBirthdayOnCalendar = person.includeBirthdayOnCalendar
            draftIsDeceased = person.isDeceased
            if let d = person.deathDate {
                draftDeath = d
                hasDeathDate = true
            }
            photoData = person.photoData
            mother = person.mother
            father = person.father
            partner = person.partner ?? person.partnerOf
            draftPartnerStatus = person.partnerStatus ?? .partner
            selectedSiblingIDs = Set(person.explicitSiblings.map(\.persistentModelID))
        }
    }

    private func performDelete() {
        guard let person else { return }

        FamilyCalendarNotifications.cancelPersonBirthday(person)

        let legalName = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let meName = FamilyTreeHomePersonStore.mePersonName,
           !legalName.isEmpty,
           legalName.caseInsensitiveCompare(meName) == .orderedSame {
            FamilyTreeHomePersonStore.mePersonName = nil
        }

        clearPartnerLinks(for: person)
        person.partnerStatus = nil

        for child in person.childrenWhereMother ?? [] {
            child.mother = nil
        }
        for child in person.childrenWhereFather ?? [] {
            child.father = nil
        }

        clearExplicitSiblingLinks(for: person)

        person.mother = nil
        person.father = nil

        modelContext.delete(person)
        do {
            try modelContext.save()
        } catch {
            print("[TheGomsons] Failed to delete family person: \(error.localizedDescription)")
        }

        if let onDeleted {
            onDeleted()
        } else {
            onCancel()
        }
    }

    private func isParentDerivedSibling(_ other: FamilyPerson) -> Bool {
        if let m = mother, other.mother?.persistentModelID == m.persistentModelID { return true }
        if let f = father, other.father?.persistentModelID == f.persistentModelID { return true }
        return false
    }

    private func siblingToggleBinding(for other: FamilyPerson, parentDerived: Bool) -> Binding<Bool> {
        Binding(
            get: {
                parentDerived || selectedSiblingIDs.contains(other.persistentModelID)
            },
            set: { isOn in
                guard !parentDerived else { return }
                if isOn {
                    selectedSiblingIDs.insert(other.persistentModelID)
                } else {
                    selectedSiblingIDs.remove(other.persistentModelID)
                }
            }
        )
    }

    private func save() {
        let target: FamilyPerson
        if let person {
            target = person
        } else {
            target = FamilyPerson()
            modelContext.insert(target)
        }

        target.name = draftName
        target.preferredName = draftPreferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.notes = draftNotes
        target.email = draftEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        target.mobile = draftMobile.trimmingCharacters(in: .whitespacesAndNewlines)
        target.city = draftCity.trimmingCharacters(in: .whitespacesAndNewlines)
        target.hobbies = draftHobbies.trimmingCharacters(in: .whitespacesAndNewlines)
        target.familyRelationLabel = draftRelationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        target.treeTier = draftTier
        target.branch = draftBranch
        target.photoData = photoData
        target.birthDate = hasBirth ? Calendar.current.startOfDay(for: draftBirth) : nil
        target.isDeceased = draftIsDeceased
        target.deathDate = draftIsDeceased && hasDeathDate
            ? Calendar.current.startOfDay(for: draftDeath)
            : nil
        target.includeBirthdayOnCalendar = hasBirth && draftIncludeBirthdayOnCalendar && !draftIsDeceased

        target.mother = mother
        target.father = father

        clearPartnerLinks(for: target)
        if let p = partner {
            target.partner = p
            target.partnerStatus = draftPartnerStatus
        } else {
            target.partnerStatus = nil
        }

        let chosenSiblings = allPeople.filter { selectedSiblingIDs.contains($0.persistentModelID) }
        setSiblingGroup(for: target, siblings: chosenSiblings)

        if isNew {
            target.sortOrder = (allPeople.map(\.sortOrder).max() ?? 0) + 1
        }

        FamilyCalendarNotifications.schedulePersonBirthday(target)

        do {
            try modelContext.save()
        } catch {
            print("[TheGomsons] Failed to save family person: \(error.localizedDescription)")
        }

        Task {
            await FamilyTreeGeocoding.refreshCoordinates(for: target, modelContext: modelContext)
        }

        onSave(target)
    }

    /// Breaks existing `partner` / `partnerOf` edges so we can assign a new forward `partner` link.
    private func clearPartnerLinks(for person: FamilyPerson) {
        if person.partner != nil {
            person.partner = nil
        }
        if let other = person.partnerOf {
            other.partner = nil
        }
    }

    /// Replace this person's explicit sibling links with `siblings` (bidirectional).
    private func setSiblingGroup(for person: FamilyPerson, siblings: [FamilyPerson]) {
        clearExplicitSiblingLinks(for: person)
        for s in siblings {
            addExplicitSiblingLink(between: person, and: s)
        }
    }

    private func clearExplicitSiblingLinks(for person: FamilyPerson) {
        let linked = person.explicitSiblings
        for other in linked {
            other.siblings?.removeAll { $0.persistentModelID == person.persistentModelID }
        }
        person.siblings = []
    }

    private func addExplicitSiblingLink(between a: FamilyPerson, and b: FamilyPerson) {
        guard a.persistentModelID != b.persistentModelID else { return }
        if a.siblings == nil { a.siblings = [] }
        let already =
            (a.siblings ?? []).contains(where: { $0.persistentModelID == b.persistentModelID })
            || (a.siblingOf ?? []).contains(where: { $0.persistentModelID == b.persistentModelID })
        if !already {
            a.siblings?.append(b)
        }
    }
}

#Preview {
    FamilyTreeView()
        .modelContainer(for: [FamilyPerson.self, FamilyEvent.self, FamilyGroupPhoto.self], inMemory: true)
}
