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

    private var treeForest: [FamilyTreeNode] {
        FamilyTreeHierarchyBuilder.buildForest(from: treeUniverse)
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
                        onDeleted: { selectedPerson = nil }
                    )
                }
            }
        }
    }

    private var treeScroll: some View {
        Group {
            if treeForest.isEmpty {
                ContentUnavailableView(
                    String(localized: "family_tree.no_matches"),
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(String(localized: "family_tree.try_branch"))
                )
                .frame(minHeight: 200)
            } else {
                FamilyTreeHierarchyView(nodes: treeForest) { person in
                    selectedPerson = person
                }
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
                            FamilyPersonRow(person: person, allPeople: allPeople)
                        }
                    }
                }
                .listStyle(.insetGrouped)
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
                                FamilyPersonAvatar(photoData: item.person.photoData, name: item.person.name)
                                    .frame(width: 52, height: 52)
                                Text(firstName(item.person.name))
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

    private func firstName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return String(localized: "common.unnamed") }
        return String(trimmed.split(separator: " ").first ?? Substring(trimmed))
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

    var body: some View {
        HStack(spacing: 12) {
            FamilyPersonAvatar(photoData: person.photoData, name: person.name)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(person.name.isEmpty ? String(localized: "common.untitled") : person.name)
                        .font(.headline)
                    if person.isDeceased {
                        DeceasedCrossMark(font: .headline)
                    }
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
                if let p = person.resolvedPartner, !p.name.isEmpty {
                    HStack(spacing: 4) {
                        Text(String(format: String(localized: "family_tree.partner"), locale: .current, p.name))
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
                            siblings.prefix(3).map { $0.name.isEmpty ? String(localized: "common.unnamed") : $0.name }.joined(separator: ", ")
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
    var onDeleted: () -> Void

    @State private var showEditor = false

    private var displayName: String {
        person.name.isEmpty ? String(localized: "common.unnamed") : person.name
    }

    private var siblings: [FamilyPerson] {
        person.resolvedSiblings(among: allPeople)
    }

    private var otherPeople: [FamilyPerson] {
        allPeople.filter { $0.persistentModelID != person.persistentModelID }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    FamilyPersonAvatar(photoData: person.photoData, name: person.name)
                        .frame(width: 128, height: 128)
                    Text(displayName)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
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
                    Button {
                        onSelectRelated(partner)
                    } label: {
                        HStack(spacing: 12) {
                            FamilyPersonAvatar(photoData: partner.photoData, name: partner.name)
                                .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(partner.name.isEmpty ? String(localized: "common.unnamed") : partner.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if let status = person.displayPartnerStatus {
                                    Text(status.displayTitle)
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
                }
            }

            if !siblings.isEmpty {
                Section(String(localized: "family_tree.siblings")) {
                    ForEach(siblings, id: \.persistentModelID) { sibling in
                        Button {
                            onSelectRelated(sibling)
                        } label: {
                            HStack(spacing: 12) {
                                FamilyPersonAvatar(photoData: sibling.photoData, name: sibling.name)
                                    .frame(width: 40, height: 40)
                                Text(sibling.name.isEmpty ? String(localized: "common.unnamed") : sibling.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if person.sharesParent(with: sibling) {
                                    Text(String(localized: "family_tree.sibling_via_parents"))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
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

    private var isNew: Bool { person == nil }

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

            Section(String(localized: "family_tree.profile_section")) {
                TextField(String(localized: "common.name"), text: $draftName)
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
                        Text(p.name.isEmpty ? String(localized: "common.unnamed") : p.name).tag(p as FamilyPerson?)
                    }
                }
                Picker(String(localized: "family_tree.father"), selection: $father) {
                    Text("—").tag(nil as FamilyPerson?)
                    ForEach(allPeople, id: \.persistentModelID) { p in
                        Text(p.name.isEmpty ? String(localized: "common.unnamed") : p.name).tag(p as FamilyPerson?)
                    }
                }
                Picker(String(localized: "family_tree.partner_picker"), selection: $partner) {
                    Text("—").tag(nil as FamilyPerson?)
                    ForEach(allPeople, id: \.persistentModelID) { p in
                        Text(p.name.isEmpty ? String(localized: "common.unnamed") : p.name).tag(p as FamilyPerson?)
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
                                Text(p.name.isEmpty ? String(localized: "common.unnamed") : p.name)
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
                        if let person {
                            FamilyCalendarNotifications.cancelPersonBirthday(person)
                            modelContext.delete(person)
                            do {
                                try modelContext.save()
                            } catch {
                                print("[TheGomsons] Failed to delete family person: \(error.localizedDescription)")
                            }
                        }
                        if let onDeleted {
                            onDeleted()
                        } else {
                            onCancel()
                        }
                    } label: {
                        Text(String(localized: "family_tree.delete_person"))
                    }
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
        .onAppear {
            guard let person else {
                draftTier = 2
                draftBranch = .ourHousehold
                return
            }
            draftName = person.name
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
