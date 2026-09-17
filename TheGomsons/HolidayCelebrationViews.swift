//
//  HolidayCelebrationViews.swift
//  TheGomsons
//
//  Celebrations hub — party planner (RSVPs, menu, venue, honoree), separate from trips.
//

import SwiftData
import SwiftUI

// MARK: - Celebrations list

struct HolidayCelebrationsListContent: View {
    enum TimeFilter {
        case upcoming
        case past
    }

    let timeFilter: TimeFilter

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \HolidayTrip.startDate, order: .reverse) private var allTrips: [HolidayTrip]

    private var celebrations: [HolidayTrip] {
        let filtered = allTrips.filter { $0.isCelebration }
        switch timeFilter {
        case .upcoming:
            return filtered.filter { !$0.isPastTrip }.sorted { $0.startDate < $1.startDate }
        case .past:
            return filtered.filter(\.isPastTrip).sorted { $0.startDate > $1.startDate }
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60.0)) { context in
            let _ = context.date
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(celebrations) { celebration in
                        NavigationLink {
                            HolidayCelebrationDetailView(trip: celebration)
                        } label: {
                            HolidayCelebrationCard(trip: celebration)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteCelebration(celebration)
                            } label: {
                                Label(String(localized: "common.delete"), systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .background(celebrationListBackground)
            .overlay {
                if celebrations.isEmpty {
                    CelebrationListEmptyState(
                        title: emptyTitle,
                        description: emptyDescription
                    )
                }
            }
        }
    }

    private var celebrationListBackground: some View {
        LinearGradient(
            colors: [
                Color(hue: 0.88, saturation: 0.35, brightness: 0.22),
                Color(hue: 0.78, saturation: 0.4, brightness: 0.28),
                Color(.systemGroupedBackground),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func deleteCelebration(_ trip: HolidayTrip) {
        modelContext.delete(trip)
        try? modelContext.save()
    }

    private var emptyTitle: String {
        switch timeFilter {
        case .upcoming: String(localized: "celebration.empty.upcoming")
        case .past: String(localized: "celebration.empty.past")
        }
    }

    private var emptyDescription: String {
        switch timeFilter {
        case .upcoming: String(localized: "celebration.empty.desc.upcoming")
        case .past: String(localized: "celebration.empty.desc.past")
        }
    }
}

// MARK: - Celebration card

struct HolidayCelebrationCard: View {
    let trip: HolidayTrip

    private var sortedGuests: [HolidayTripGuest] {
        (trip.guests ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedFamily: [HolidayTripParticipant] {
        (trip.participants ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var familyAttending: Int {
        sortedFamily.filter { $0.rsvpStatus == .attending }.count
    }

    private var guestsAttending: Int {
        sortedGuests.filter { $0.rsvpStatus == .attending }.count
    }

    private var totalInvited: Int {
        sortedFamily.count + sortedGuests.count
    }

    private var totalAttending: Int {
        familyAttending + guestsAttending
    }

    private var subjectLine: String {
        trip.celebrationSubject.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var venueLine: String {
        trip.celebrationVenue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var menuLine: String {
        trip.celebrationMenu.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let ui = trip.coverUIImage {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        CelebrationHeroPlaceholder()
                    }
                }
                .frame(height: 180)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 180)

                VStack(alignment: .leading, spacing: 6) {
                    Label(String(localized: "trip.kind.celebration"), systemImage: "party.popper.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.22), in: Capsule())

                    Text(trip.tripName.isEmpty ? String(localized: "celebration.untitled") : trip.tripName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    if !subjectLine.isEmpty {
                        Text(subjectLine)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(2)
                    }

                    Label(celebrationDatePhrase, systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(16)
            }

            VStack(alignment: .leading, spacing: 10) {
                CelebrationInfoChip(
                    icon: "calendar",
                    text: celebrationDatePhrase,
                    tint: SimpsonsTheme.skyBlue
                )

                if venueLine.isEmpty {
                    CelebrationHintChip(
                        icon: "mappin.and.ellipse",
                        text: String(localized: "celebration.hint.add_venue"),
                        tint: SimpsonsTheme.orange
                    )
                } else {
                    CelebrationInfoChip(
                        icon: "mappin.and.ellipse",
                        text: venueLine,
                        tint: SimpsonsTheme.orange
                    )
                }

                if totalInvited == 0 {
                    CelebrationHintChip(
                        icon: "person.2.badge.plus",
                        text: String(localized: "celebration.hint.invite_guests"),
                        tint: SimpsonsTheme.purple
                    )
                } else {
                    CelebrationInfoChip(
                        icon: "person.2.fill",
                        text: String(
                            format: String(localized: "celebration.rsvp.summary"),
                            locale: .current,
                            totalAttending,
                            totalInvited
                        ),
                        tint: SimpsonsTheme.purple
                    )
                }

                if menuLine.isEmpty {
                    CelebrationHintChip(
                        icon: "fork.knife",
                        text: String(localized: "celebration.hint.plan_menu"),
                        tint: SimpsonsTheme.pink
                    )
                } else {
                    CelebrationInfoChip(
                        icon: "fork.knife",
                        text: menuLine,
                        tint: SimpsonsTheme.pink,
                        lineLimit: 2
                    )
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: SimpsonsTheme.purple.opacity(0.22), radius: 16, y: 8)
    }

    private var celebrationDatePhrase: String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: trip.startDate)
        let end = cal.startOfDay(for: trip.endDate)
        if start == end {
            return trip.startDate.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(trip.startDate.formatted(date: .abbreviated, time: .omitted)) – \(trip.endDate.formatted(date: .abbreviated, time: .omitted))"
    }
}

// MARK: - Celebration detail (party planner)

struct HolidayCelebrationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: HolidayTrip

    @State private var showEdit = false
    @State private var showAddFamily = false
    @State private var showDeleteConfirm = false
    @State private var participantToEdit: HolidayTripParticipant?

    private var sortedFamily: [HolidayTripParticipant] {
        (trip.participants ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedGuests: [HolidayTripGuest] {
        (trip.guests ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var familyAttending: Int { sortedFamily.filter { $0.rsvpStatus == .attending }.count }
    private var guestsAttending: Int { sortedGuests.filter { $0.rsvpStatus == .attending }.count }

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(geo.size.width, 1)
            ScrollView {
                VStack(spacing: 0) {
                    celebrationHero(width: contentWidth)

                    VStack(alignment: .leading, spacing: 28) {
                        celebratingSection
                        whenSection
                        venueSection
                        menuSection
                        rsvpOverviewSection
                        CelebrationFamilyAttendeesSection(
                            trip: trip,
                            showAddFamily: $showAddFamily,
                            participantToEdit: $participantToEdit
                        )
                        HolidayCelebrationGuestsSection(trip: trip)
                        celebrationNotesSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .frame(width: contentWidth, alignment: .leading)
                }
                .frame(width: contentWidth, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEdit = true
                    } label: {
                        Label(String(localized: "celebration.edit"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(String(localized: "common.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            HolidayCelebrationEditorSheet(trip: trip)
        }
        .sheet(isPresented: $showAddFamily) {
            AddTripParticipantSheet(trip: trip, celebrationRSVP: true)
        }
        .sheet(item: $participantToEdit) { participant in
            EditTripParticipantSheet(participant: participant, celebrationRSVP: true)
        }
        .confirmationDialog(
            String(localized: "celebration.delete_confirm"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                modelContext.delete(trip)
                try? modelContext.save()
                dismiss()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func celebrationHero(width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Group {
                if let ui = trip.coverUIImage {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    CelebrationHeroPlaceholder()
                }
            }
            .frame(width: width, height: 260)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(width: width, height: 260)

            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "trip.kind.celebration"), systemImage: "party.popper.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())

                    Text(trip.tripName.isEmpty ? String(localized: "celebration.untitled") : trip.tripName)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)

                if !trip.celebrationSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(trip.celebrationSubject)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                }

                Label(celebrationDateDisplayPhrase, systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: width, alignment: .leading)
            .padding(24)
        }
        .frame(width: width, height: 260)
        .clipped()
    }

    private var celebratingSection: some View {
        CelebrationPlannerField(
            title: String(localized: "celebration.subject.label"),
            hint: String(localized: "celebration.subject.hint"),
            icon: "heart.fill"
        ) {
            TextField(String(localized: "celebration.subject.placeholder"), text: $trip.celebrationSubject, axis: .vertical)
                .lineLimit(2 ... 4)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var whenSection: some View {
        CelebrationPlannerField(
            title: String(localized: "celebration.when"),
            hint: String(localized: "celebration.when.hint"),
            icon: "calendar"
        ) {
            CelebrationInfoChip(
                icon: "calendar",
                text: celebrationDateDisplayPhrase,
                tint: SimpsonsTheme.skyBlue
            )
        }
    }

    private var venueSection: some View {
        CelebrationPlannerField(
            title: String(localized: "celebration.venue"),
            hint: String(localized: "celebration.venue.hint"),
            icon: "building.2.fill"
        ) {
            TextField(String(localized: "celebration.venue.placeholder"), text: $trip.celebrationVenue, axis: .vertical)
                .lineLimit(2 ... 4)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var menuSection: some View {
        CelebrationPlannerField(
            title: String(localized: "celebration.menu"),
            hint: String(localized: "celebration.menu.hint"),
            icon: "fork.knife"
        ) {
            TextEditor(text: $trip.celebrationMenu)
                .frame(minHeight: 100)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))
                }
        }
    }

    private var rsvpOverviewSection: some View {
        Group {
            if sortedFamily.isEmpty && sortedGuests.isEmpty {
                CelebrationEmptyPanel(
                    icon: "person.2.badge.plus",
                    title: String(localized: "celebration.rsvp.empty.title"),
                    subtitle: String(localized: "celebration.rsvp.empty.hint"),
                    tint: SimpsonsTheme.purple
                )
            } else {
                HStack(spacing: 12) {
                    rsvpChip(
                        count: familyAttending,
                        total: sortedFamily.count,
                        label: String(localized: "celebration.rsvp.family"),
                        color: SimpsonsTheme.pink
                    )
                    rsvpChip(
                        count: guestsAttending,
                        total: sortedGuests.count,
                        label: String(localized: "celebration.rsvp.guests"),
                        color: SimpsonsTheme.purple
                    )
                }
            }
        }
    }

    private func rsvpChip(count: Int, total: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if total == 0 {
                Text("—")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(color.opacity(0.5))
                Text(String(localized: "celebration.hint.invite_guests"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("\(count)/\(total)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(color)
                Text(String(localized: "celebration.rsvp.attending"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.12))
        }
    }

    private var celebrationDateDisplayPhrase: String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: trip.startDate)
        let end = cal.startOfDay(for: trip.endDate)
        let today = cal.startOfDay(for: Date())
        if start == end && start == today {
            return String(localized: "celebration.date.today")
        }
        return celebrationDateLongPhrase
    }

    private var celebrationNotesSection: some View {
        CelebrationPlannerField(
            title: String(localized: "celebration.notes"),
            hint: String(localized: "celebration.notes.hint"),
            icon: "note.text"
        ) {
            TextEditor(text: $trip.notes)
                .frame(minHeight: 88)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))
                }
        }
    }

    private var celebrationDateLongPhrase: String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: trip.startDate)
        let end = cal.startOfDay(for: trip.endDate)
        if start == end {
            return trip.startDate.formatted(date: .long, time: .omitted)
        }
        let a = trip.startDate.formatted(date: .long, time: .omitted)
        let b = trip.endDate.formatted(date: .long, time: .omitted)
        return "\(a) → \(b)"
    }
}

private struct CelebrationPlannerField<Content: View>: View {
    let title: String
    let hint: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Family attendees with RSVP

struct CelebrationFamilyAttendeesSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: HolidayTrip
    @Binding var showAddFamily: Bool
    @Binding var participantToEdit: HolidayTripParticipant?

    private var sortedFamily: [HolidayTripParticipant] {
        (trip.participants ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "celebration.family_attendees"))
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "celebration.family_attendees.hint"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    showAddFamily = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
            }

            if sortedFamily.isEmpty {
                CelebrationEmptyPanel(
                    icon: "person.3.fill",
                    title: String(localized: "celebration.family_empty.title"),
                    subtitle: String(localized: "celebration.family_empty.hint"),
                    tint: SimpsonsTheme.pink
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(sortedFamily, id: \.persistentModelID) { person in
                        CelebrationFamilyRSVPRow(participant: person) {
                            participantToEdit = person
                        }
                        if person.persistentModelID != sortedFamily.last?.persistentModelID {
                            Divider()
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                }
            }
        }
    }
}

private struct CelebrationFamilyRSVPRow: View {
    @Bindable var participant: HolidayTripParticipant
    var onEdit: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            rsvpRowHorizontal
            rsvpRowVertical
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var nameBlock: some View {
        Button {
            onEdit()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    participant.displayName.isEmpty
                        ? String(localized: "common.unnamed")
                        : participant.displayName
                )
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                if !participant.roleTag.isEmpty {
                    Text(participant.roleTag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rsvpPicker: some View {
        HolidayRSVPStatusPicker(
            status: Binding(
                get: { participant.rsvpStatus },
                set: { participant.rsvpStatus = $0 }
            ),
            style: .menu
        )
    }

    private var rsvpRowHorizontal: some View {
        HStack(spacing: 12) {
            nameBlock
            Spacer(minLength: 8)
            rsvpPicker
                .frame(maxWidth: 168)
        }
    }

    private var rsvpRowVertical: some View {
        VStack(alignment: .leading, spacing: 10) {
            nameBlock
            rsvpPicker
        }
    }
}

// MARK: - Celebration editor

struct HolidayCelebrationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var trip: HolidayTrip?
    var defaultsToFuture: Bool = true

    @State private var eventName = ""
    @State private var celebrationSubject = ""
    @State private var celebrationVenue = ""
    @State private var celebrationMenu = ""
    @State private var notes = ""
    @State private var start: Date
    @State private var end: Date
    @State private var singleDayEvent = true
    @State private var coverImageData: Data?
    @State private var coverPlaceName = ""
    @State private var coverLatitude = 0.0
    @State private var coverLongitude = 0.0
    @State private var saveFailedMessage: String?

    init(trip: HolidayTrip? = nil, defaultsToFuture: Bool = true) {
        self.trip = trip
        self.defaultsToFuture = defaultsToFuture
        if let trip {
            _eventName = State(initialValue: trip.tripName)
            _celebrationSubject = State(initialValue: trip.celebrationSubject)
            _celebrationVenue = State(initialValue: trip.celebrationVenue)
            _celebrationMenu = State(initialValue: trip.celebrationMenu)
            _notes = State(initialValue: trip.notes)
            let cal = Calendar.current
            let s = cal.startOfDay(for: trip.startDate)
            let e = cal.startOfDay(for: trip.endDate)
            _start = State(initialValue: s)
            _end = State(initialValue: e < s ? s : e)
            _singleDayEvent = State(initialValue: s == e)
            _coverImageData = State(initialValue: trip.coverImageData)
            _coverPlaceName = State(initialValue: trip.coverPlaceName)
            _coverLatitude = State(initialValue: trip.coverLatitude)
            _coverLongitude = State(initialValue: trip.coverLongitude)
        } else {
            let cal = Calendar.current
            let now = Date()
            let t = cal.startOfDay(for: now)
            _start = State(initialValue: t)
            _end = State(initialValue: t)
            _singleDayEvent = State(initialValue: true)
        }
    }

    private var isEditing: Bool { trip != nil }

    private var trimmedEventName: String {
        eventName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "celebration.editor.event_section")) {
                    TextField(String(localized: "celebration.event_name"), text: $eventName, prompt: Text(String(localized: "celebration.event_name.prompt")))
                    TextField(String(localized: "celebration.subject.label"), text: $celebrationSubject, prompt: Text(String(localized: "celebration.subject.placeholder")), axis: .vertical)
                        .lineLimit(2 ... 4)
                }

                HolidayCoverImageFormSection(
                    coverImageData: $coverImageData,
                    coverPlaceName: $coverPlaceName,
                    coverLatitude: $coverLatitude,
                    coverLongitude: $coverLongitude,
                    footerText: String(localized: "celebration.cover.footer")
                )

                Section(String(localized: "celebration.when")) {
                    Toggle(String(localized: "celebration.single_day"), isOn: $singleDayEvent)
                    DatePicker(
                        singleDayEvent ? String(localized: "celebration.date") : String(localized: "trip.date.start"),
                        selection: $start,
                        in: isEditing ? Date.distantPast ... Date.distantFuture : (defaultsToFuture ? todayStart ... Date.distantFuture : Date.distantPast ... todayStart),
                        displayedComponents: .date
                    )
                    .onChange(of: start) { _, newStart in
                        let s = Calendar.current.startOfDay(for: newStart)
                        start = s
                        if singleDayEvent { end = s }
                        else if end < s { end = s }
                    }
                    if !singleDayEvent {
                        DatePicker(String(localized: "trip.date.end"), selection: $end, in: start ... Date.distantFuture, displayedComponents: .date)
                    }
                }

                Section(String(localized: "celebration.venue")) {
                    TextField(String(localized: "celebration.venue.placeholder"), text: $celebrationVenue, axis: .vertical)
                        .lineLimit(2 ... 4)
                }

                Section(String(localized: "celebration.menu")) {
                    TextEditor(text: $celebrationMenu)
                        .frame(minHeight: 100)
                }

                Section(String(localized: "celebration.notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                if !isEditing {
                    Section {
                        Text(String(localized: "celebration.editor.footer"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isEditing ? String(localized: "celebration.edit") : String(localized: "celebration.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? String(localized: "common.save") : String(localized: "common.create")) {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmedEventName.isEmpty)
                }
            }
            .onChange(of: singleDayEvent) { _, isSingle in
                if isSingle {
                    end = Calendar.current.startOfDay(for: start)
                }
            }
            .alert(String(localized: "trip.couldnt_save"), isPresented: Binding(
                get: { saveFailedMessage != nil },
                set: { if !$0 { saveFailedMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) { saveFailedMessage = nil }
            } message: {
                Text(saveFailedMessage ?? "")
            }
        }
    }

    private func save() {
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        let e = singleDayEvent ? s : cal.startOfDay(for: end)
        let finalEnd = e < s ? s : e

        if let existing = trip {
            existing.tripName = trimmedEventName
            existing.startDate = s
            existing.endDate = finalEnd
            existing.celebrationSubject = celebrationSubject
            existing.celebrationVenue = celebrationVenue
            existing.celebrationMenu = celebrationMenu
            existing.notes = notes
            existing.coverImageData = coverImageData
            existing.coverPlaceName = coverPlaceName
            existing.coverLatitude = coverLatitude
            existing.coverLongitude = coverLongitude
            existing.tripKind = .celebration
            existing.linkedProperty = nil
        } else {
            let newCelebration = HolidayTrip(
                tripName: trimmedEventName,
                startDate: s,
                endDate: finalEnd,
                tripKind: .celebration,
                notes: notes,
                celebrationSubject: celebrationSubject,
                celebrationVenue: celebrationVenue,
                celebrationMenu: celebrationMenu,
                coverImageData: coverImageData,
                coverPlaceName: coverPlaceName,
                coverLatitude: coverLatitude,
                coverLongitude: coverLongitude
            )
            modelContext.insert(newCelebration)
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveFailedMessage = error.localizedDescription
        }
    }
}

struct AddHolidayCelebrationSheet: View {
    var defaultsToFuture: Bool = true

    var body: some View {
        HolidayCelebrationEditorSheet(trip: nil, defaultsToFuture: defaultsToFuture)
    }
}

// MARK: - Celebration visuals (hero, chips, empty states)

struct CelebrationHeroPlaceholder: View {
    var body: some View {
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    .init(0, 0), .init(0.5, 0), .init(1, 0),
                    .init(0, 0.5), .init(0.55, 0.45), .init(1, 0.5),
                    .init(0, 1), .init(0.5, 1), .init(1, 1),
                ],
                colors: [
                    SimpsonsTheme.purple.opacity(0.85),
                    SimpsonsTheme.pink.opacity(0.75),
                    SimpsonsTheme.skyBlue.opacity(0.7),
                    SimpsonsTheme.orange.opacity(0.65),
                    SimpsonsTheme.purple.opacity(0.8),
                    SimpsonsTheme.pink.opacity(0.7),
                    SimpsonsTheme.blue.opacity(0.75),
                    SimpsonsTheme.purple.opacity(0.7),
                    SimpsonsTheme.orange.opacity(0.6),
                ]
            )

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Image(systemName: "party.popper.fill")
                    .font(.system(size: min(w, h) * 0.22, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                    .position(x: w * 0.72, y: h * 0.38)
                Image(systemName: "sparkles")
                    .font(.system(size: min(w, h) * 0.14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.28))
                    .position(x: w * 0.22, y: h * 0.32)
                Image(systemName: "gift.fill")
                    .font(.system(size: min(w, h) * 0.12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.25))
                    .position(x: w * 0.48, y: h * 0.55)
            }
        }
    }
}

struct CelebrationInfoChip: View {
    let icon: String
    let text: String
    let tint: Color
    var lineLimit: Int = 3

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.15), in: Circle())
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
        }
    }
}

struct CelebrationHintChip: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint.opacity(0.7))
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.1), in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground).opacity(0.6))
                )
        }
    }
}

struct CelebrationEmptyPanel: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.22), tint.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                }
        }
    }
}

struct CelebrationListEmptyState: View {
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [SimpsonsTheme.purple.opacity(0.35), SimpsonsTheme.pink.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .padding(32)
    }
}
