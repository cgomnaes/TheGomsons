//
//  CalendarView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

// MARK: - Kind → colour (icons use `FamilyEventKind.systemImageName`)

extension FamilyEventKind {
    var calendarAccent: Color {
        switch self {
        case .birthday: SimpsonsTheme.pink
        case .party: SimpsonsTheme.orange
        case .holiday: SimpsonsTheme.blue
        case .school: SimpsonsTheme.green
        case .other: Color.secondary
        }
    }
}

private enum CalendarScope: Int, CaseIterable {
    case month
    case year

    var label: String {
        switch self {
        case .month: String(localized: "calendar.scope_month")
        case .year: String(localized: "calendar.scope_year")
        }
    }
}

/// Calendar list/grid row: manual `FamilyEvent` or an annual birthday from the family tree.
private enum CalendarRowItem: Identifiable {
    case event(FamilyEvent)
    case treeBirthday(FamilyPerson)

    var id: String {
        switch self {
        case .event(let e): "e-\(e.persistentModelID)"
        case .treeBirthday(let p): "p-\(p.persistentModelID)"
        }
    }
}

struct CalendarView: View {
    @Environment(\.openFamilyLanding) private var openFamilyLanding
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyEvent.date) private var allEvents: [FamilyEvent]
    @Query(sort: \FamilyPerson.sortOrder) private var allPeople: [FamilyPerson]

    @State private var scope: CalendarScope = .month
    /// First day of the visible month (startOfDay of day 1).
    @State private var anchorMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var showAddEvent = false
    @State private var selectedEvent: FamilyEvent?
    @State private var selectedCalendarPerson: FamilyPerson?
    /// When set, the list below the grid filters to this day (month scope only).
    @State private var selectedDay: Date?

    private var calendar: Calendar { Calendar.current }

    private var treeBirthdaysOnCalendar: [FamilyPerson] {
        allPeople.filter { $0.birthDate != nil && $0.includeBirthdayOnCalendar && !$0.isDeceased }
    }

    private var whatsNextRows: [(item: CalendarRowItem, next: Date)] {
        let now = Date()
        var tuples: [(CalendarRowItem, Date)] = []
        for e in allEvents {
            let next = e.nextOccurrence(after: now.addingTimeInterval(-120))
            if next >= now.addingTimeInterval(-60) {
                tuples.append((.event(e), next))
            }
        }
        for p in treeBirthdaysOnCalendar {
            guard let next = p.nextBirthdayOccurrence(after: now.addingTimeInterval(-120)),
                  next >= now.addingTimeInterval(-60)
            else { continue }
            tuples.append((.treeBirthday(p), next))
        }
        return Array(tuples.sorted { $0.1 < $1.1 }.prefix(5))
    }

    private var dontForgetList: [FamilyEvent] {
        let start = calendar.startOfDay(for: Date())
        return allEvents
            .filter { e in
                guard e.dontForget else { return false }
                return e.nextOccurrence(after: start.addingTimeInterval(-1)) >= start.addingTimeInterval(-1)
            }
            .sorted { a, b in
                a.nextOccurrence(after: start) < b.nextOccurrence(after: start)
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    whatsNextSection
                    dontForgetSection

                    Picker(String(localized: "common.view"), selection: $scope) {
                        ForEach(CalendarScope.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    if scope == .month {
                        monthChrome
                        FamilyMonthGrid(
                            monthStart: anchorMonth,
                            rowsByDay: mergedCalendarRows(monthContaining: anchorMonth),
                            selectedDay: $selectedDay
                        )
                    } else {
                        yearChrome
                        FamilyYearGrid(
                            year: calendar.component(.year, from: anchorMonth),
                            events: allEvents,
                            treePeople: treeBirthdaysOnCalendar,
                            onSelectMonth: { monthStart in
                                anchorMonth = monthStart
                                scope = .month
                            }
                        )
                    }

                    eventsListSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "calendar.title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddEvent = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(String(localized: "calendar.add_event"))
                }
            }
            .sheet(isPresented: $showAddEvent) {
                NavigationStack {
                    FamilyEventEditorView(event: nil) {
                        showAddEvent = false
                    }
                }
            }
            .sheet(item: $selectedEvent) { event in
                NavigationStack {
                    FamilyEventEditorView(event: event) {
                        selectedEvent = nil
                    }
                }
            }
            .onAppear {
                FamilyCalendarNotifications.rescheduleAll(events: allEvents)
                FamilyCalendarNotifications.rescheduleAllPersonBirthdays(allPeople)
            }
            .sheet(item: $selectedCalendarPerson) { person in
                NavigationStack {
                    Form {
                        Toggle(String(localized: "family_tree.birthday_on_calendar"), isOn: Binding(
                            get: { person.includeBirthdayOnCalendar },
                            set: { newValue in
                                person.includeBirthdayOnCalendar = newValue
                                FamilyCalendarNotifications.schedulePersonBirthday(person)
                                try? modelContext.save()
                            }
                        ))
                        .disabled(person.birthDate == nil)
                    }
                    .navigationTitle(person.displayName.isEmpty ? String(localized: "family_tree.title") : person.displayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "common.done")) {
                                selectedCalendarPerson = nil
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - What’s next

    private var whatsNextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "calendar.whats_next"), systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(SimpsonsTheme.green)

            if whatsNextRows.isEmpty {
                Text(String(localized: "calendar.no_events"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(whatsNextRows.enumerated()), id: \.element.item.id) { index, row in
                            Button {
                                switch row.item {
                                case .event(let e): selectedEvent = e
                                case .treeBirthday(let p): selectedCalendarPerson = p
                                }
                            } label: {
                                calendarRowView(
                                    row.item,
                                    showRelativeDay: true,
                                    displayDate: row.next
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                switch row.item {
                                case .event(let e):
                                    Button(String(localized: "common.delete"), role: .destructive) {
                                        deleteEvent(e)
                                    }
                                case .treeBirthday(let p):
                                    Button(String(localized: "calendar.remove_tree_birthday"), role: .destructive) {
                                        hideTreeBirthdayFromCalendar(p)
                                    }
                                }
                            }
                            if index < whatsNextRows.count - 1 {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                }
                .frame(height: 240)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: - Don’t forget

    private var dontForgetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "calendar.dont_forget"), systemImage: "bell.badge.fill")
                .font(.headline)
                .foregroundStyle(SimpsonsTheme.orange)

            if dontForgetList.isEmpty {
                Text(String(localized: "calendar.dont_forget_hint"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dontForgetList.enumerated()), id: \.element.persistentModelID) { index, event in
                        Button {
                            selectedEvent = event
                        } label: {
                            eventRow(
                                event,
                                showRelativeDay: true,
                                displayDate: event.nextOccurrence(after: Date())
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(String(localized: "common.delete"), role: .destructive) {
                                deleteEvent(event)
                            }
                        }
                        if index < dontForgetList.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: - Month / year chrome

    private var monthChrome: some View {
        HStack {
            Button {
                anchorMonth = calendar.date(byAdding: .month, value: -1, to: anchorMonth) ?? anchorMonth
                selectedDay = nil
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(String(localized: "calendar.prev_month"))

            Spacer()
            Text(anchorMonth, format: .dateTime.month(.wide).year())
                .font(.title2.weight(.semibold))
            Spacer()

            Button {
                anchorMonth = calendar.date(byAdding: .month, value: 1, to: anchorMonth) ?? anchorMonth
                selectedDay = nil
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(String(localized: "calendar.next_month"))
        }
        .foregroundStyle(.primary)
    }

    private var yearChrome: some View {
        let year = calendar.component(.year, from: anchorMonth)
        return HStack {
            Button {
                if let y = calendar.date(from: DateComponents(year: year - 1, month: 1, day: 1)) {
                    anchorMonth = y
                }
                selectedDay = nil
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(String(localized: "calendar.prev_year"))

            Spacer()
            Text(String(year))
                .font(.title2.weight(.semibold))
            Spacer()

            Button {
                if let y = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) {
                    anchorMonth = y
                }
                selectedDay = nil
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(String(localized: "calendar.next_year"))
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Event list (scoped)

    private var eventsListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if scope == .month {
                if let day = selectedDay {
                    Text(
                        String(
                            format: String(localized: "calendar.events_on"),
                            day.formatted(date: .abbreviated, time: .omitted)
                        )
                    )
                        .font(.headline)
                } else {
                    Text(String(localized: "calendar.all_month"))
                        .font(.headline)
                }
            } else {
                Text(
                    String(
                        format: String(localized: "calendar.all_year"),
                        calendar.component(.year, from: anchorMonth)
                    )
                )
                    .font(.headline)
            }

            let filtered = filteredCalendarRows
            if filtered.isEmpty {
                Text(String(localized: "calendar.no_period"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                List {
                    ForEach(filtered) { row in
                        Button {
                            switch row {
                            case .event(let e): selectedEvent = e
                            case .treeBirthday(let p): selectedCalendarPerson = p
                            }
                        } label: {
                            calendarRowView(
                                row,
                                showRelativeDay: false,
                                displayDate: listDisplayDate(for: row)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color(.separator).opacity(0.5))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            switch row {
                            case .event(let e):
                                Button(role: .destructive) {
                                    deleteEvent(e)
                                } label: {
                                    Label(String(localized: "common.delete"), systemImage: "trash")
                                }
                            case .treeBirthday(let p):
                                Button(role: .destructive) {
                                    hideTreeBirthdayFromCalendar(p)
                                } label: {
                                    Label(String(localized: "calendar.remove_tree_birthday"), systemImage: "eye.slash")
                                }
                            }
                        }
                        .contextMenu {
                            switch row {
                            case .event(let e):
                                Button(String(localized: "common.delete"), role: .destructive) {
                                    deleteEvent(e)
                                }
                            case .treeBirthday(let p):
                                Button(String(localized: "calendar.remove_tree_birthday"), role: .destructive) {
                                    hideTreeBirthdayFromCalendar(p)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .environment(\.defaultMinListRowHeight, 52)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func deleteEvent(_ event: FamilyEvent) {
        if selectedEvent?.persistentModelID == event.persistentModelID {
            selectedEvent = nil
        }
        let hadOthers: Bool
        if let sd = selectedDay {
            let start = calendar.startOfDay(for: sd)
            let eventsLeft = allEvents.filter {
                $0.persistentModelID != event.persistentModelID && isEvent($0, onCalendarDay: start)
            }
            let treeLeft = treeBirthdaysOnCalendar.filter { isTreeBirthday($0, onCalendarDay: start) }
            hadOthers = !eventsLeft.isEmpty || !treeLeft.isEmpty
        } else {
            hadOthers = true
        }
        FamilyCalendarNotifications.cancel(for: event)
        modelContext.delete(event)
        try? modelContext.save()
        if selectedDay != nil, !hadOthers {
            selectedDay = nil
        }
    }

    private func hideTreeBirthdayFromCalendar(_ person: FamilyPerson) {
        if selectedCalendarPerson?.persistentModelID == person.persistentModelID {
            selectedCalendarPerson = nil
        }
        let hadOthers: Bool
        if let sd = selectedDay {
            let start = calendar.startOfDay(for: sd)
            let eventsLeft = allEvents.filter { isEvent($0, onCalendarDay: start) }
            let treeLeft = treeBirthdaysOnCalendar.filter {
                $0.persistentModelID != person.persistentModelID && isTreeBirthday($0, onCalendarDay: start)
            }
            hadOthers = !eventsLeft.isEmpty || !treeLeft.isEmpty
        } else {
            hadOthers = true
        }
        person.includeBirthdayOnCalendar = false
        FamilyCalendarNotifications.schedulePersonBirthday(person)
        try? modelContext.save()
        if selectedDay != nil, !hadOthers {
            selectedDay = nil
        }
    }

    private var filteredCalendarRows: [CalendarRowItem] {
        if scope == .month {
            if let day = selectedDay {
                let start = calendar.startOfDay(for: day)
                var rows: [CalendarRowItem] = []
                rows += allEvents.filter { isEvent($0, onCalendarDay: start) }.map { .event($0) }
                rows += treeBirthdaysOnCalendar.filter { isTreeBirthday($0, onCalendarDay: start) }.map { .treeBirthday($0) }
                return rows.sorted { sortCalendarRow($0) < sortCalendarRow($1) }
            }
            var rows: [CalendarRowItem] = []
            rows += allEvents.filter { isEventInVisibleMonth($0) }.map { .event($0) }
            rows += treeBirthdaysOnCalendar.filter { isTreeBirthdayInVisibleMonth($0) }.map { .treeBirthday($0) }
            return rows.sorted { sortCalendarRow($0) < sortCalendarRow($1) }
        }
        let y = calendar.component(.year, from: anchorMonth)
        var rows: [CalendarRowItem] = []
        rows += allEvents.filter { isEventInYear($0, y) }.map { .event($0) }
        rows += treeBirthdaysOnCalendar.map { .treeBirthday($0) }
        return rows.sorted { sortCalendarRow($0) < sortCalendarRow($1) }
    }

    private func isTreeBirthday(_ person: FamilyPerson, onCalendarDay dayStart: Date) -> Bool {
        guard let bd = person.birthDate else { return false }
        return calendar.component(.month, from: bd) == calendar.component(.month, from: dayStart)
            && calendar.component(.day, from: bd) == calendar.component(.day, from: dayStart)
    }

    private func isTreeBirthdayInVisibleMonth(_ person: FamilyPerson) -> Bool {
        guard let bd = person.birthDate else { return false }
        return calendar.component(.month, from: bd) == calendar.component(.month, from: anchorMonth)
    }

    private func sortCalendarRow(_ item: CalendarRowItem) -> Date {
        switch item {
        case .event(let e):
            return sortDate(e)
        case .treeBirthday(let p):
            if scope == .month {
                return p.birthdayOccurrence(inMonthContaining: anchorMonth) ?? .distantPast
            }
            let y = calendar.component(.year, from: anchorMonth)
            return p.birthdayOccurrence(inYear: y) ?? .distantPast
        }
    }

    private func listDisplayDate(for item: CalendarRowItem) -> Date? {
        switch item {
        case .event(let e):
            guard e.kind == .birthday else { return nil }
            if scope == .month {
                return e.occurrence(inMonthContaining: anchorMonth)
            }
            let y = calendar.component(.year, from: anchorMonth)
            return e.occurrence(inYear: y)
        case .treeBirthday(let p):
            if scope == .month {
                return p.birthdayOccurrence(inMonthContaining: anchorMonth)
            }
            let y = calendar.component(.year, from: anchorMonth)
            return p.birthdayOccurrence(inYear: y)
        }
    }

    private func mergedCalendarRows(monthContaining monthStart: Date) -> [Date: [CalendarRowItem]] {
        mergeEventsAndTreeRows(events: allEvents, treePeople: treeBirthdaysOnCalendar, monthContaining: monthStart)
    }

    @ViewBuilder
    private func calendarRowView(_ item: CalendarRowItem, showRelativeDay: Bool, displayDate: Date?) -> some View {
        switch item {
        case .event(let event):
            eventRow(event, showRelativeDay: showRelativeDay, displayDate: displayDate)
        case .treeBirthday(let person):
            treeBirthdayRow(person, showRelativeDay: showRelativeDay, displayDate: displayDate)
        }
    }

    private func treeBirthdayRow(_ person: FamilyPerson, showRelativeDay: Bool, displayDate: Date?) -> some View {
        let primary = displayDate ?? person.birthDate ?? Date()
        let name = person.displayName
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: FamilyEventKind.birthday.systemImageName)
                .font(.title3)
                .foregroundStyle(FamilyEventKind.birthday.calendarAccent)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name.isEmpty ? String(localized: "common.untitled") : name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Image(systemName: "person.3.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if showRelativeDay {
                    Text(relativeDayDescription(primary, omitTime: true))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(primary.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let age = person.ageOnBirthday(onCelebrationDay: calendar.startOfDay(for: primary)), age >= 0 {
                    Text(String(format: String(localized: "calendar.turns_age"), locale: .current, age))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func isEventInVisibleMonth(_ e: FamilyEvent) -> Bool {
        if e.kind == .birthday {
            return calendar.component(.month, from: e.date) == calendar.component(.month, from: anchorMonth)
        }
        return calendar.isDate(e.date, equalTo: anchorMonth, toGranularity: .month)
    }

    private func isEventInYear(_ e: FamilyEvent, _ year: Int) -> Bool {
        if e.kind == .birthday { return true }
        return calendar.component(.year, from: e.date) == year
    }

    private func isEvent(_ e: FamilyEvent, onCalendarDay dayStart: Date) -> Bool {
        if e.kind == .birthday {
            return calendar.component(.month, from: e.date) == calendar.component(.month, from: dayStart)
                && calendar.component(.day, from: e.date) == calendar.component(.day, from: dayStart)
        }
        return calendar.isDate(e.date, inSameDayAs: dayStart)
    }

    private func sortDate(_ e: FamilyEvent) -> Date {
        if e.kind == .birthday {
            if scope == .month {
                return e.occurrence(inMonthContaining: anchorMonth) ?? e.date
            }
            let y = calendar.component(.year, from: anchorMonth)
            return e.occurrence(inYear: y) ?? e.date
        }
        return e.date
    }

    @ViewBuilder
    private func eventRow(_ event: FamilyEvent, showRelativeDay: Bool, displayDate: Date? = nil) -> some View {
        let primary = displayDate ?? event.date
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.systemImageName)
                .font(.title3)
                .foregroundStyle(event.kind.calendarAccent)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title.isEmpty ? String(localized: "common.untitled") : event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if event.dontForget {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(SimpsonsTheme.orange)
                    }
                }
                if showRelativeDay {
                    Text(relativeDayDescription(primary, omitTime: event.kind == .birthday))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(primary.formatted(date: .abbreviated, time: event.kind == .birthday ? .omitted : .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if event.kind == .birthday, let age = event.age(onCelebrationDay: calendar.startOfDay(for: primary)), age >= 0 {
                    Text(String(format: String(localized: "calendar.turns_age"), locale: .current, age))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func relativeDayDescription(_ date: Date, omitTime: Bool = false) -> String {
        if omitTime {
            if calendar.isDateInToday(date) { return String(localized: "calendar.today") }
            if calendar.isDateInTomorrow(date) { return String(localized: "calendar.tomorrow") }
            if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day, days > 1, days < 7 {
                return String(
                    format: String(localized: "calendar.in_days"),
                    locale: .current,
                    days,
                    date.formatted(date: .abbreviated, time: .omitted)
                )
            }
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        if calendar.isDateInToday(date) {
            return String(
                format: String(localized: "calendar.today_time"),
                locale: .current,
                date.formatted(date: .omitted, time: .shortened)
            )
        }
        if calendar.isDateInTomorrow(date) {
            return String(
                format: String(localized: "calendar.tomorrow_time"),
                locale: .current,
                date.formatted(date: .omitted, time: .shortened)
            )
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day, days > 1, days < 7 {
            return String(
                format: String(localized: "calendar.in_days"),
                locale: .current,
                days,
                date.formatted(date: .abbreviated, time: .shortened)
            )
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Grouping

/// Maps start-of-day → events, including **annual** birthdays on the correct day in this month.
private func eventsByStartOfDayExpanded(_ events: [FamilyEvent], monthContaining monthStart: Date) -> [Date: [FamilyEvent]] {
    let cal = Calendar.current
    guard let interval = cal.dateInterval(of: .month, for: monthStart) else { return [:] }
    var dict: [Date: [FamilyEvent]] = [:]
    for e in events {
        if e.kind == .birthday {
            if let occ = e.occurrence(inMonthContaining: monthStart) {
                let start = cal.startOfDay(for: occ)
                if start >= interval.start && start < interval.end {
                    dict[start, default: []].append(e)
                }
            }
        } else {
            let start = cal.startOfDay(for: e.date)
            if start >= interval.start && start < interval.end {
                dict[start, default: []].append(e)
            }
        }
    }
    return dict
}

/// Month grid data: manual calendar events plus family-tree birthdays when enabled per person.
private func mergeEventsAndTreeRows(
    events: [FamilyEvent],
    treePeople: [FamilyPerson],
    monthContaining monthStart: Date
) -> [Date: [CalendarRowItem]] {
    let cal = Calendar.current
    guard let interval = cal.dateInterval(of: .month, for: monthStart) else { return [:] }
    var dict: [Date: [CalendarRowItem]] = [:]
    let base = eventsByStartOfDayExpanded(events, monthContaining: monthStart)
    for (d, evs) in base {
        dict[d] = evs.map { .event($0) }
    }
    for p in treePeople {
        guard let occ = p.birthdayOccurrence(inMonthContaining: monthStart) else { continue }
        let start = cal.startOfDay(for: occ)
        if start >= interval.start && start < interval.end {
            dict[start, default: []].append(.treeBirthday(p))
        }
    }
    return dict
}

// MARK: - Month grid

private struct FamilyMonthGrid: View {
    let monthStart: Date
    let rowsByDay: [Date: [CalendarRowItem]]
    @Binding var selectedDay: Date?

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 8) {
            weekdayHeader
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(monthDayCells().enumerated()), id: \.offset) { _, cell in
                    if let day = cell {
                        dayCell(day)
                    } else {
                        Color.clear
                            .frame(minHeight: 52)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols(), id: \.self) { sym in
                Text(sym)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func weekdaySymbols() -> [String] {
        let syms = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(syms[first...] + syms[..<first])
    }

    private func monthDayCells() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: monthStart) else { return [] }
        let first = interval.start
        let range = calendar.range(of: .day, in: .month, for: first)!
        let firstWeekday = calendar.component(.weekday, from: first)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: first) {
                cells.append(d)
            }
        }
        return cells
    }

    private func dayCell(_ day: Date) -> some View {
        let start = calendar.startOfDay(for: day)
        let events = rowsByDay[start] ?? []
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false

        return Button {
            if let s = selectedDay, calendar.isDate(s, inSameDayAs: day) {
                selectedDay = nil
            } else {
                selectedDay = day
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? SimpsonsTheme.green : .primary)

                if !events.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(uniqueKinds(events).prefix(3), id: \.self) { k in
                            Image(systemName: k.systemImageName)
                                .font(.system(size: 9))
                                .foregroundStyle(k.calendarAccent)
                        }
                        if events.count > 3 {
                            Text("+\(events.count - 3)")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 12)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? SimpsonsTheme.green.opacity(0.2) : (isToday ? SimpsonsTheme.green.opacity(0.12) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? SimpsonsTheme.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func uniqueKinds(_ items: [CalendarRowItem]) -> [FamilyEventKind] {
        var seen = Set<FamilyEventKind>()
        var out: [FamilyEventKind] = []
        for item in items {
            let k: FamilyEventKind
            switch item {
            case .event(let e): k = e.kind
            case .treeBirthday: k = .birthday
            }
            if seen.insert(k).inserted {
                out.append(k)
            }
        }
        return out
    }
}

// MARK: - Year grid (12 mini months)

private struct FamilyYearGrid: View {
    let year: Int
    let events: [FamilyEvent]
    let treePeople: [FamilyPerson]
    var onSelectMonth: (Date) -> Void

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(1...12, id: \.self) { month in
                if let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)) {
                    miniMonth(monthStart: monthStart)
                        .onTapGesture {
                            onSelectMonth(monthStart)
                        }
                }
            }
        }
    }

    private func miniMonth(monthStart: Date) -> some View {
        let byDay = mergeEventsAndTreeRows(events: events, treePeople: treePeople, monthContaining: monthStart)
        let title = monthStart.formatted(.dateTime.month(.abbreviated))
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(monthDayCells(for: monthStart).enumerated()), id: \.offset) { _, cell in
                    if let day = cell {
                        let start = calendar.startOfDay(for: day)
                        let dayEvents = byDay[start] ?? []
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 9))
                            .foregroundStyle(calendar.isDateInToday(day) ? SimpsonsTheme.green : .primary)
                            .frame(maxWidth: .infinity, minHeight: 14)
                            .background(
                                Circle()
                                    .fill(dotBackground(for: dayEvents))
                            )
                    } else {
                        Color.clear.frame(height: 14)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func dotBackground(for dayEvents: [CalendarRowItem]) -> Color {
        guard let first = dayEvents.first else {
            return Color.clear
        }
        let kind: FamilyEventKind
        switch first {
        case .event(let e): kind = e.kind
        case .treeBirthday: kind = .birthday
        }
        return kind.calendarAccent.opacity(0.35)
    }

    private func monthDayCells(for monthStart: Date) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: monthStart) else { return [] }
        let first = interval.start
        let range = calendar.range(of: .day, in: .month, for: first)!
        let firstWeekday = calendar.component(.weekday, from: first)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: first) {
                cells.append(d)
            }
        }
        return cells
    }
}

// MARK: - Editor

private struct FamilyEventEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let event: FamilyEvent?
    var onDone: () -> Void

    @State private var confirmDelete = false
    @State private var titleText = ""
    @State private var dateValue = Date()
    @State private var locationText = ""
    @State private var assignedText = ""
    @State private var reminderMinutes = 30
    @State private var kind: FamilyEventKind = .other
    @State private var dontForget = false
    @State private var yearBorn = 1990

    private var isNew: Bool { event == nil }

    private var maxBirthYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "common.field_title"), text: $titleText)
                Group {
                    if kind == .birthday {
                        DatePicker(String(localized: "calendar.birth_date"), selection: $dateValue, displayedComponents: [.date])
                    } else {
                        DatePicker(String(localized: "calendar.date_time"), selection: $dateValue, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Picker(String(localized: "common.type"), selection: $kind) {
                    ForEach(FamilyEventKind.allCases, id: \.self) { k in
                        Label(k.displayTitle, systemImage: k.systemImageName).tag(k)
                    }
                }
                if kind == .birthday {
                    Picker(String(localized: "calendar.born_in"), selection: $yearBorn) {
                        ForEach(Array((1900...maxBirthYear).reversed()), id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                }
            } header: {
                Text(String(localized: "calendar.event"))
            } footer: {
                if kind == .birthday {
                    Text(String(localized: "calendar.event_footer_birthday"))
                }
            }
            Section(String(localized: "calendar.details")) {
                TextField(String(localized: "event.field.location"), text: $locationText)
                TextField(String(localized: "event.field.assigned"), text: $assignedText)
            }
            Section {
                Toggle(String(localized: "calendar.dont_forget"), isOn: $dontForget)
                    .tint(SimpsonsTheme.orange)
            } footer: {
                Text(String(localized: "calendar.dont_forget_footer"))
            }
            Section(String(localized: "calendar.reminder")) {
                Stepper(value: $reminderMinutes, in: 0...24 * 60, step: 5) {
                    if kind == .birthday {
                        Text(
                            reminderMinutes == 0
                                ? String(localized: "calendar.reminder_notify_day")
                                : String(format: String(localized: "calendar.reminder_notify_before"), locale: .current, reminderMinutes)
                        )
                    } else {
                        Text(
                            reminderMinutes == 0
                                ? String(localized: "calendar.reminder_notify_at_event")
                                : String(format: String(localized: "calendar.reminder_notify_before"), locale: .current, reminderMinutes)
                        )
                    }
                }
                Text(
                    kind == .birthday
                        ? String(localized: "calendar.reminder_footer_birthday")
                        : String(localized: "calendar.reminder_footer_general")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !isNew {
                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label(String(localized: "calendar.delete_event"), systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(isNew ? String(localized: "calendar.new_event") : String(localized: "calendar.edit_event"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: kind) { _, new in
            if new == .birthday {
                reminderMinutes = 0
                dateValue = mergedBirthdayDate(monthDayTime: dateValue, year: yearBorn)
            }
        }
        .onChange(of: yearBorn) { _, y in
            guard kind == .birthday else { return }
            dateValue = mergedBirthdayDate(monthDayTime: dateValue, year: y)
        }
        .onChange(of: dateValue) { _, new in
            guard kind == .birthday else { return }
            let cal = Calendar.current
            // Date wheel includes a year; keep it in sync with “Born in” so the wheel isn’t snapped back (e.g. stuck at 1991).
            let yWheel = cal.component(.year, from: new)
            let clampedYear = min(max(yWheel, 1900), maxBirthYear)
            if clampedYear != yearBorn {
                yearBorn = clampedYear
            }
            let merged = mergedBirthdayDate(monthDayTime: new, year: clampedYear)
            if abs(merged.timeIntervalSince1970 - new.timeIntervalSince1970) > 0.5 {
                dateValue = merged
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "common.cancel")) {
                    onDone()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "common.save")) {
                    save()
                }
                .fontWeight(.semibold)
            }
        }
        .confirmationDialog(
            String(localized: "calendar.delete_confirm_title"),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                deleteEventAndDismiss()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "calendar.delete_confirm_msg"))
        }
        .onAppear {
            Task { await FamilyCalendarNotifications.requestAuthorizationIfNeeded() }
            guard let event else {
                dateValue = Date()
                reminderMinutes = 30
                kind = .other
                dontForget = false
                yearBorn = max(1900, maxBirthYear - 35)
                return
            }
            titleText = event.title
            dateValue = event.date
            locationText = event.location
            assignedText = event.assignedTo
            reminderMinutes = event.reminderMinutesBefore
            kind = event.kind
            dontForget = event.dontForget
            yearBorn = event.yearBorn > 0 ? event.yearBorn : Calendar.current.component(.year, from: event.date)
            if event.kind == .birthday {
                dateValue = mergedBirthdayDate(monthDayTime: dateValue, year: yearBorn)
            }
        }
    }

    private func mergedBirthdayDate(monthDayTime: Date, year: Int) -> Date {
        let cal = Calendar.current
        var c = cal.dateComponents([.month, .day], from: monthDayTime)
        c.year = year
        c.hour = 0
        c.minute = 0
        c.second = 0
        return cal.date(from: c).map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: monthDayTime)
    }

    private func deleteEventAndDismiss() {
        guard let event else { return }
        FamilyCalendarNotifications.cancel(for: event)
        modelContext.delete(event)
        do {
            try modelContext.save()
            onDone()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to delete event: \(error.localizedDescription)")
        }
    }

    private func save() {
        Task { await FamilyCalendarNotifications.requestAuthorizationIfNeeded() }

        let target: FamilyEvent
        if let event {
            target = event
        } else {
            target = FamilyEvent()
            modelContext.insert(target)
        }

        target.title = titleText
        target.location = locationText
        target.assignedTo = assignedText
        target.reminderMinutesBefore = reminderMinutes
        target.kind = kind
        target.dontForget = dontForget
        if kind == .birthday {
            let y = min(max(yearBorn, 1900), maxBirthYear)
            target.yearBorn = y
            target.date = mergedBirthdayDate(monthDayTime: dateValue, year: y)
        } else {
            target.yearBorn = 0
            target.date = dateValue
        }

        do {
            try modelContext.save()
            FamilyCalendarNotifications.schedule(for: target)
            onDone()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to save event: \(error.localizedDescription)")
        }
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: [FamilyEvent.self, FamilyPerson.self], inMemory: true)
}
