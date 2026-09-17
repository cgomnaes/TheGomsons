//
//  HolidayPartyInviteSheet.swift
//  TheGomsons
//
//  Add party names from the family tree, Contacts, or typed entry.
//

import Contacts
import ContactsUI
import SwiftData
import SwiftUI

enum HolidayPartyInviteTarget {
    case familyAttendees(HolidayTrip)
    case guestList(HolidayTrip)

    var trip: HolidayTrip {
        switch self {
        case .familyAttendees(let trip), .guestList(let trip): trip
        }
    }
}

struct HolidayPartyInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let target: HolidayPartyInviteTarget
    var celebrationRSVP: Bool = false

    @Query(sort: \FamilyPerson.sortOrder) private var allFamilyPeople: [FamilyPerson]

    @State private var selectedHousehold: Set<String> = []
    @State private var selectedTreeIDs: Set<PersistentIdentifier> = []
    @State private var pickedContactNames: [String] = []
    @State private var customName = ""
    @State private var roleTag = ""
    @State private var defaultGuestRSVP: HolidayRSVPStatus = .attending
    @State private var showContactPicker = false
    @State private var familySearch = ""
    @State private var saveFailedMessage: String?

    private let householdNames = ["Pappa", "Mamma", "CC", "Herman"]

    private var trip: HolidayTrip { target.trip }

    private var isGuestList: Bool {
        if case .guestList = target { return true }
        return false
    }

    private var trimmedCustom: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var existingParticipantNames: Set<String> {
        Set((trip.participants ?? []).map { normalizedName($0.displayName) })
    }

    private var existingGuestNames: Set<String> {
        Set((trip.guests ?? []).map { normalizedName($0.guestName) })
    }

    private var treeCandidates: [FamilyPerson] {
        allFamilyPeople.filter { person in
            !person.isDeceased && !person.displayName.isEmpty
        }
    }

    private var filteredTreeCandidates: [FamilyPerson] {
        let q = familySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return treeCandidates }
        return treeCandidates.filter { person in
            person.displayName.lowercased().contains(q)
                || person.name.lowercased().contains(q)
                || person.familyRelationLabel.lowercased().contains(q)
        }
    }

    private var pendingNames: [String] {
        var names: [String] = []
        if !isGuestList {
            for n in householdNames where selectedHousehold.contains(n) {
                names.append(n)
            }
        }
        for person in treeCandidates where selectedTreeIDs.contains(person.persistentModelID) {
            let name = person.displayName
            if !names.contains(name) { names.append(name) }
        }
        for name in pickedContactNames where !names.contains(name) {
            names.append(name)
        }
        if !trimmedCustom.isEmpty, !names.contains(trimmedCustom) {
            names.append(trimmedCustom)
        }
        return names
    }

    private var canAdd: Bool { !pendingNames.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if !isGuestList {
                    householdSection
                }

                familyTreeSection

                contactsSection

                manualSection

                if isGuestList {
                    Section(String(localized: "trip.guest.rsvp")) {
                        HolidayRSVPStatusPicker(status: $defaultGuestRSVP)
                    }
                } else {
                    Section(String(localized: "trip.role_all")) {
                        TextField(String(localized: "trip.shown_under"), text: $roleTag, prompt: Text(String(localized: "trip.role.prompt2")))
                    }
                }

                if !pendingNames.isEmpty {
                    Section(String(localized: "party.invite.ready_to_add")) {
                        ForEach(pendingNames, id: \.self) { name in
                            Label(name, systemImage: "person.fill")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .navigationTitle(isGuestList ? String(localized: "party.invite.guests_nav") : String(localized: "trip.add_travelers.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addButtonTitle) { save() }
                        .fontWeight(.semibold)
                        .disabled(!canAdd)
                }
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerSheet { names in
                    for name in names {
                        appendContactName(name)
                    }
                }
            }
            .alert(String(localized: "trip.couldnt_save_travelers"), isPresented: Binding(
                get: { saveFailedMessage != nil },
                set: { if !$0 { saveFailedMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) { saveFailedMessage = nil }
            } message: {
                Text(saveFailedMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var householdSection: some View {
        Section(String(localized: "trip.family")) {
            Text(trip.isPastTrip ? String(localized: "trip.family.hint.past") : String(localized: "trip.family.hint.future"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(householdNames, id: \.self) { name in
                let alreadyOnTrip = existingParticipantNames.contains(normalizedName(name))
                Toggle(isOn: bindingForHousehold(name)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.body.weight(.medium))
                        if alreadyOnTrip {
                            Text(String(localized: "party.invite.already_on_list"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(alreadyOnTrip)
            }
        }
    }

    @ViewBuilder
    private var familyTreeSection: some View {
        Section {
            Text(String(localized: "party.invite.family_tree.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(String(localized: "party.invite.search_tree"), text: $familySearch)
                .textInputAutocapitalization(.words)

            if treeCandidates.isEmpty {
                Text(String(localized: "party.invite.family_tree.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if filteredTreeCandidates.isEmpty {
                Text(String(localized: "party.invite.family_tree.no_match"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredTreeCandidates) { person in
                    let alreadyAdded = isAlreadyAdded(person.displayName)
                    Toggle(isOn: bindingForTreePerson(person)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.displayName)
                                .font(.body.weight(.medium))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if !person.familyRelationLabel.isEmpty {
                                Text(person.familyRelationLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if alreadyAdded {
                                Text(String(localized: "party.invite.already_on_list"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(alreadyAdded)
                }
            }
        } header: {
            Label(String(localized: "party.invite.family_tree"), systemImage: "person.3.fill")
        }
    }

    @ViewBuilder
    private var contactsSection: some View {
        Section {
            Button {
                showContactPicker = true
            } label: {
                Label(String(localized: "party.invite.pick_contacts"), systemImage: "person.crop.circle.badge.plus")
            }

            if !pickedContactNames.isEmpty {
                ForEach(pickedContactNames, id: \.self) { name in
                    HStack {
                        Text(name)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button {
                            pickedContactNames.removeAll { $0 == name }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "common.remove"))
                    }
                }
            }
        } header: {
            Label(String(localized: "party.invite.contacts"), systemImage: "phone.circle.fill")
        } footer: {
            Text(String(localized: "party.invite.contacts.footer"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var manualSection: some View {
        Section(String(localized: "trip.also_add")) {
            TextField(String(localized: "trip.custom.prompt"), text: $customName)
                .textInputAutocapitalization(.words)
        }
    }

    private var addButtonTitle: String {
        let n = pendingNames.count
        if n <= 1 { return String(localized: "common.add") }
        return String(format: String(localized: "trip.add_n"), locale: .current, n)
    }

    private func bindingForHousehold(_ name: String) -> Binding<Bool> {
        Binding(
            get: { selectedHousehold.contains(name) },
            set: { on in
                if on { selectedHousehold.insert(name) } else { selectedHousehold.remove(name) }
            }
        )
    }

    private func bindingForTreePerson(_ person: FamilyPerson) -> Binding<Bool> {
        Binding(
            get: { selectedTreeIDs.contains(person.persistentModelID) },
            set: { on in
                if on {
                    selectedTreeIDs.insert(person.persistentModelID)
                } else {
                    selectedTreeIDs.remove(person.persistentModelID)
                }
            }
        )
    }

    private func appendContactName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !pickedContactNames.contains(trimmed) {
            pickedContactNames.append(trimmed)
        }
    }

    private func isAlreadyAdded(_ displayName: String) -> Bool {
        let key = normalizedName(displayName)
        if isGuestList {
            return existingGuestNames.contains(key)
        }
        return existingParticipantNames.contains(key)
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func roleForTreePerson(_ person: FamilyPerson) -> String {
        let relation = person.familyRelationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !relation.isEmpty { return relation }
        return roleTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let sharedRole = roleTag.trimmingCharacters(in: .whitespacesAndNewlines)

        if isGuestList {
            var order = (trip.guests ?? []).map(\.sortOrder).max().map { $0 + 1 } ?? 0
            for name in pendingNames {
                let key = normalizedName(name)
                guard !existingGuestNames.contains(key) else { continue }
                let guest = HolidayTripGuest(
                    guestName: name,
                    rsvpStatus: defaultGuestRSVP,
                    sortOrder: order,
                    trip: trip
                )
                modelContext.insert(guest)
                order += 1
            }
        } else {
            var order = (trip.participants ?? []).map(\.sortOrder).max().map { $0 + 1 } ?? 0
            for name in pendingNames {
                let key = normalizedName(name)
                guard !existingParticipantNames.contains(key) else { continue }
                var role = sharedRole
                if let person = treeCandidates.first(where: { $0.displayName == name }) {
                    role = roleForTreePerson(person)
                }
                let participant = HolidayTripParticipant(
                    displayName: name,
                    roleTag: role,
                    sortOrder: order,
                    rsvpStatus: .attending,
                    trip: trip
                )
                modelContext.insert(participant)
                order += 1
            }
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to save party invitees: \(error.localizedDescription)")
            saveFailedMessage = error.localizedDescription
        }
    }
}

// MARK: - Contacts picker

private struct ContactPickerSheet: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onPick: ([String]) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, dismiss: dismiss)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([String]) -> Void
        let dismiss: DismissAction

        init(onPick: @escaping ([String]) -> Void, dismiss: DismissAction) {
            self.onPick = onPick
            self.dismiss = dismiss
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let names = contacts.map { ContactInviteFormatting.displayName(for: $0) }.filter { !$0.isEmpty }
            if !names.isEmpty {
                onPick(names)
            }
            dismiss()
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = ContactInviteFormatting.displayName(for: contact)
            if !name.isEmpty {
                onPick([name])
            }
            dismiss()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            dismiss()
        }
    }
}

private enum ContactInviteFormatting {
    static func displayName(for contact: CNContact) -> String {
        let formatter = CNContactFormatter()
        formatter.style = .fullName
        if let formatted = formatter.string(from: contact)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !formatted.isEmpty {
            return formatted
        }
        let parts = [contact.givenName, contact.familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        let nick = contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return nick
    }
}
