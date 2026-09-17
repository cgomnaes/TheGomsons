//
//  HolidayCelebrationGuestsView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

struct HolidayCelebrationGuestsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: HolidayTrip

    @State private var showAddGuest = false
    @State private var showInviteGuests = false
    @State private var guestToEdit: HolidayTripGuest?

    private var sortedGuests: [HolidayTripGuest] {
        (trip.guests ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var attendingCount: Int {
        sortedGuests.filter { $0.rsvpStatus == .attending }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "celebration.guest_list"))
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "celebration.guest_list.hint"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !sortedGuests.isEmpty {
                        Text(
                            String(
                                format: String(localized: "trip.guests_attending_count"),
                                locale: .current,
                                attendingCount,
                                sortedGuests.count
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button {
                        showInviteGuests = true
                    } label: {
                        Label(String(localized: "party.invite.from_sources"), systemImage: "person.crop.circle.badge.plus")
                    }
                    Button {
                        showAddGuest = true
                    } label: {
                        Label(String(localized: "party.invite.type_name"), systemImage: "character.cursor.ibeam")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(String(localized: "trip.add_guest.a11y"))
            }

            if sortedGuests.isEmpty {
                CelebrationEmptyPanel(
                    icon: "person.crop.circle.badge.plus",
                    title: String(localized: "celebration.guests_empty.title"),
                    subtitle: String(localized: "celebration.guests_empty.hint"),
                    tint: SimpsonsTheme.purple
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(sortedGuests, id: \.persistentModelID) { guest in
                        Button {
                            guestToEdit = guest
                        } label: {
                            HolidayGuestRow(guest: guest)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                guestToEdit = guest
                            } label: {
                                Label(String(localized: "trip.edit_guest"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                modelContext.delete(guest)
                                try? modelContext.save()
                            } label: {
                                Label(String(localized: "trip.remove_guest"), systemImage: "person.fill.xmark")
                            }
                        }
                        if guest.persistentModelID != sortedGuests.last?.persistentModelID {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                }
            }
        }
        .sheet(isPresented: $showInviteGuests) {
            HolidayPartyInviteSheet(target: .guestList(trip))
        }
        .sheet(isPresented: $showAddGuest) {
            HolidayTripGuestEditorSheet(trip: trip)
        }
        .sheet(item: $guestToEdit) { guest in
            HolidayTripGuestEditorSheet(trip: trip, guest: guest)
        }
    }
}

private struct HolidayGuestRow: View {
    let guest: HolidayTripGuest

    private var trimmedName: String {
        guest.guestName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var status: HolidayRSVPStatus { guest.rsvpStatus }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.systemImage)
                .font(.title3)
                .foregroundStyle(rsvpStatusColor(status))
            VStack(alignment: .leading, spacing: 2) {
                Text(trimmedName.isEmpty ? String(localized: "trip.guest_unnamed") : trimmedName)
                    .font(.headline)
                Text(status.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func rsvpStatusColor(_ status: HolidayRSVPStatus) -> Color {
        switch status {
        case .attending: .green
        case .notAttending: .secondary
        case .maybe: .orange
        }
    }
}

/// Three-way RSVP control (Coming / Maybe / Not coming).
struct HolidayRSVPStatusPicker: View {
    @Binding var status: HolidayRSVPStatus
    var style: HolidayRSVPStatusPickerStyle = .segmented

    enum HolidayRSVPStatusPickerStyle {
        case segmented
        case menu
    }

    var body: some View {
        Group {
            switch style {
            case .segmented:
                ViewThatFits {
                    segmentedPicker
                    menuPicker
                }
            case .menu:
                menuPicker
            }
        }
    }

    private var segmentedPicker: some View {
        Picker(String(localized: "trip.guest.rsvp"), selection: $status) {
            ForEach(HolidayRSVPStatus.allCases) { option in
                Text(option.displayTitle).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    private var menuPicker: some View {
        Picker(String(localized: "trip.guest.rsvp"), selection: $status) {
            ForEach(HolidayRSVPStatus.allCases) { option in
                Label(option.displayTitle, systemImage: option.systemImage).tag(option)
            }
        }
        .pickerStyle(.menu)
    }
}

struct HolidayTripGuestEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let trip: HolidayTrip
    var guest: HolidayTripGuest?

    @State private var guestName: String
    @State private var rsvpStatus: HolidayRSVPStatus
    @State private var saveFailedMessage: String?
    @State private var confirmRemove = false

    init(trip: HolidayTrip, guest: HolidayTripGuest? = nil) {
        self.trip = trip
        self.guest = guest
        if let guest {
            _guestName = State(initialValue: guest.guestName)
            _rsvpStatus = State(initialValue: guest.rsvpStatus)
        } else {
            _guestName = State(initialValue: "")
            _rsvpStatus = State(initialValue: .attending)
        }
    }

    private var isEditing: Bool { guest != nil }

    private var trimmedName: String {
        guestName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayName: String {
        trimmedName.isEmpty ? String(localized: "trip.this_guest") : trimmedName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "trip.guest.section")) {
                    TextField(String(localized: "common.name"), text: $guestName)
                    HolidayRSVPStatusPicker(status: $rsvpStatus)
                }
                if isEditing {
                    Section {
                        Button(String(localized: "trip.remove_guest"), role: .destructive) {
                            confirmRemove = true
                        }
                    }
                }
            }
            .navigationTitle(
                isEditing
                    ? String(localized: "trip.edit_guest_nav")
                    : String(localized: "trip.add_guest_nav")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? String(localized: "common.save") : String(localized: "common.add")) {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmedName.isEmpty)
                }
            }
            .alert(String(localized: "trip.couldnt_save_short"), isPresented: Binding(
                get: { saveFailedMessage != nil },
                set: { if !$0 { saveFailedMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) { saveFailedMessage = nil }
            } message: {
                Text(saveFailedMessage ?? "")
            }
            .confirmationDialog(
                String(
                    format: String(localized: "trip.remove_guest_confirm"),
                    locale: .current,
                    displayName
                ),
                isPresented: $confirmRemove,
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.remove"), role: .destructive) {
                    removeGuest()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            }
        }
    }

    private func save() {
        if let guest {
            guest.guestName = trimmedName
            guest.rsvpStatus = rsvpStatus
        } else {
            let sortOrder = (trip.guests ?? []).map(\.sortOrder).max().map { $0 + 1 } ?? 0
            let newGuest = HolidayTripGuest(
                guestName: trimmedName,
                rsvpStatus: rsvpStatus,
                sortOrder: sortOrder,
                trip: trip
            )
            modelContext.insert(newGuest)
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to save guest: \(error.localizedDescription)")
            saveFailedMessage = error.localizedDescription
        }
    }

    private func removeGuest() {
        guard let guest else { return }
        modelContext.delete(guest)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to remove guest: \(error.localizedDescription)")
            saveFailedMessage = error.localizedDescription
        }
    }
}
