//
//  HolidaysRootView.swift
//  TheGomsons
//

import CoreLocation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

// MARK: - Trip lists (upcoming vs past)

/// Upcoming or past trips; same full trip model—classification is by end date vs today.
struct HolidayTripsListContent: View {
    enum Filter {
        case upcoming
        case past
    }

    let filter: Filter

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \HolidayTrip.startDate, order: .reverse) private var allTrips: [HolidayTrip]

    private var trips: [HolidayTrip] {
        switch filter {
        case .upcoming:
            allTrips.filter { !$0.isPastTrip }.sorted { $0.startDate < $1.startDate }
        case .past:
            allTrips.filter(\.isPastTrip).sorted { $0.startDate > $1.startDate }
        }
    }

    var body: some View {
        // Re-evaluate past vs upcoming as calendar time passes (no manual “move” step).
        TimelineView(.periodic(from: .now, by: 60.0)) { context in
            let _ = context.date
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(trips) { trip in
                        NavigationLink {
                            HolidayTripDetailView(trip: trip)
                        } label: {
                            HolidayTripCard(trip: trip)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteTrip(trip)
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
            .background {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.09, blue: 0.18),
                        Color(red: 0.12, green: 0.14, blue: 0.28),
                        Color(.systemGroupedBackground),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .overlay {
                if trips.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: filter == .upcoming ? "calendar.badge.clock" : "airplane.departure",
                        description: Text(emptyDescription)
                    )
                    .background(.thinMaterial.opacity(0.001))
                }
            }
        }
    }

    private func deleteTrip(_ trip: HolidayTrip) {
        modelContext.delete(trip)
        do {
            try modelContext.save()
        } catch {
            print("[TheGomsons] Failed to delete trip: \(error.localizedDescription)")
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .upcoming: String(localized: "trips.empty.upcoming")
        case .past: String(localized: "trips.empty.past")
        }
    }

    private var emptyDescription: String {
        switch filter {
        case .upcoming:
            String(localized: "trips.empty.desc.upcoming")
        case .past:
            String(localized: "trips.empty.desc.past")
        }
    }
}

extension HolidayTripsListContent {
    /// Previews and legacy call sites default to the past-trips list.
    init() {
        self.init(filter: .past)
    }
}

// MARK: - Trip card (list)

struct HolidayTripCard: View {
    let trip: HolidayTrip

    private var sortedParticipants: [HolidayTripParticipant] {
        (trip.participants ?? []).sorted { $0.sortOrder < $1.sortOrder }
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
                        LinearGradient(
                            colors: [
                                Color(hue: 0.58, saturation: 0.45, brightness: 0.55),
                                Color(hue: 0.72, saturation: 0.5, brightness: 0.4),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 44, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
                .frame(height: 220)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 220)

                VStack(alignment: .leading, spacing: 6) {
                    Text(trip.tripName.isEmpty ? String(localized: "trip.untitled") : trip.tripName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    Text("\(trip.startDate.formatted(date: .abbreviated, time: .omitted)) – \(trip.endDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(16)
            }

            VStack(alignment: .leading, spacing: 12) {
                if sortedParticipants.isEmpty {
                    Label(trip.isPastTrip ? String(localized: "trip.add_who_went") : String(localized: "trip.add_who_going"), systemImage: "person.3.sequence.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: -10) {
                            ForEach(Array(sortedParticipants.enumerated()), id: \.element.persistentModelID) { index, person in
                                FamilyAvatarBubble(
                                    name: person.displayName,
                                    index: index,
                                    size: 44
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color(.systemBackground), lineWidth: 3)
                                )
                                .zIndex(Double(sortedParticipants.count - index))
                            }
                        }
                        .padding(.trailing, 8)
                    }

                    HStack(spacing: 6) {
                        ForEach(sortedParticipants.prefix(4)) { p in
                            Text(p.displayName.isEmpty ? "?" : p.displayName)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        if sortedParticipants.count > 4 {
                            Text("+\(sortedParticipants.count - 4)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !(trip.destinations ?? []).isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text({
                            let c = (trip.destinations ?? []).count
                            let key = c == 1 ? "trip.stops_count" : "trip.stops_count_plural"
                            return String(format: String(localized: String.LocalizationValue(key)), locale: .current, c)
                        }())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}

// MARK: - Detail

struct HolidayTripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: HolidayTrip

    @State private var showAddTraveler = false
    @State private var showAddStop = false
    @State private var showEditTrip = false
    @State private var showDeleteTripConfirm = false
    @State private var participantToEdit: HolidayTripParticipant?

    private var sortedParticipants: [HolidayTripParticipant] {
        (trip.participants ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedDestinations: [HolidayDestination] {
        (trip.destinations ?? []).sorted { $0.arrivalDate < $1.arrivalDate }
    }

    /// Hero uses the same width as the scroll column so cover + title can’t lay out wider than the screen (fixes left clipping).
    @ViewBuilder
    private func tripHeroBlock(width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Group {
                if let ui = trip.coverUIImage {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: [
                            .init(0, 0), .init(0.5, 0), .init(1, 0),
                            .init(0, 0.5), .init(0.55, 0.45), .init(1, 0.5),
                            .init(0, 1), .init(0.5, 1), .init(1, 1),
                        ],
                        colors: [
                            Color(hue: 0.62, saturation: 0.55, brightness: 0.45),
                            Color(hue: 0.75, saturation: 0.4, brightness: 0.5),
                            Color(hue: 0.52, saturation: 0.5, brightness: 0.4),
                            Color(hue: 0.68, saturation: 0.45, brightness: 0.38),
                            Color(hue: 0.58, saturation: 0.5, brightness: 0.48),
                            Color(hue: 0.8, saturation: 0.35, brightness: 0.42),
                            Color(hue: 0.6, saturation: 0.55, brightness: 0.32),
                            Color(hue: 0.72, saturation: 0.4, brightness: 0.35),
                            Color(hue: 0.55, saturation: 0.5, brightness: 0.4),
                        ]
                    )
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 56, weight: .thin))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                }
            }
            .frame(width: width)
            .frame(height: 280)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(width: width)
            .frame(height: 280)

            VStack(alignment: .leading, spacing: 8) {
                Text(trip.tripName.isEmpty ? String(localized: "trip.title_fallback") : trip.tripName)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.85)
                Text(dateRangePhrase)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
            }
            .frame(width: width, alignment: .leading)
            .padding(24)
        }
        .frame(width: width, height: 280)
        .clipped()
    }

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(geo.size.width, 1)
            ScrollView {
                VStack(spacing: 0) {
                    tripHeroBlock(width: contentWidth)

                    VStack(alignment: .leading, spacing: 28) {
                        if !trip.isPastTrip {
                            HolidayTripPlanningSection(trip: trip)
                        }

                        notesSection

                        if trip.isPastTrip {
                            HolidayTripReviewSection(trip: trip)
                        }

                        travelDetailsSection

                        familySection

                        destinationsSection
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
                        showEditTrip = true
                    } label: {
                        Label(String(localized: "trip.edit_trip"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteTripConfirm = true
                    } label: {
                        Label(String(localized: "trip.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(String(localized: "trip.actions.a11y"))
            }
        }
        .confirmationDialog(
            trip.isPastTrip
                ? String(localized: "trip.delete_confirm_past")
                : String(localized: "trip.delete_confirm_upcoming"),
            isPresented: $showDeleteTripConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "trip.delete"), role: .destructive) {
                deleteTripAndDismiss()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showAddTraveler) {
            AddTripParticipantSheet(trip: trip)
        }
        .sheet(item: $participantToEdit) { participant in
            EditTripParticipantSheet(participant: participant)
        }
        .sheet(isPresented: $showAddStop) {
            AddHolidayDestinationSheet(trip: trip)
        }
        .sheet(isPresented: $showEditTrip) {
            HolidayTripEditorSheet(trip: trip)
        }
    }

    private func deleteTripAndDismiss() {
        modelContext.delete(trip)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to delete trip: \(error.localizedDescription)")
        }
    }

    private var dateRangePhrase: String {
        let a = trip.startDate.formatted(date: .long, time: .omitted)
        let b = trip.endDate.formatted(date: .long, time: .omitted)
        return "\(a) → \(b)"
    }

    private var isPastTrip: Bool {
        trip.isPastTrip
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "trip.notes"))
                .font(.title2.weight(.bold))
            Text(String(localized: "trip.notes.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $trip.notes)
                .font(.body)
                .frame(minHeight: 120)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var travelDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "trip.travel_stay"))
                .font(.title2.weight(.bold))
            VStack(alignment: .leading, spacing: 14) {
                tripTravelField(title: String(localized: "trip.airline"), text: $trip.airlineName, prompt: String(localized: "common.optional"))
                tripTravelField(title: String(localized: "trip.reference"), text: $trip.bookingReference, prompt: String(localized: "trip.reference.prompt"))
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "trip.main_accommodation"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "trip.accommodation.prompt"), text: $trip.mainAccommodation, axis: .vertical)
                        .lineLimit(2 ... 6)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tripTravelField(title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var familySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isPastTrip ? String(localized: "trip.who_went") : String(localized: "trip.who_going"))
                        .font(.title2.weight(.bold))
                    Text(String(localized: "trip.travelers.hint"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showAddTraveler = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(String(localized: "trip.travelers.a11y"))
            }

            if sortedParticipants.isEmpty {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 120)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "person.3.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "trip.no_travelers"))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    ForEach(Array(sortedParticipants.enumerated()), id: \.element.persistentModelID) { index, person in
                        Button {
                            participantToEdit = person
                        } label: {
                            TravelerGlassCard(
                                name: person.displayName,
                                roleTag: person.roleTag,
                                index: index
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                participantToEdit = person
                            } label: {
                                Label(String(localized: "trip.edit_name"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                modelContext.delete(person)
                                try? modelContext.save()
                            } label: {
                                Label(String(localized: "trip.remove_from_trip"), systemImage: "person.fill.xmark")
                            }
                        }
                    }
                }
            }
        }
    }

    private var destinationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "trip.stops"))
                        .font(.title2.weight(.bold))
                    Text(String(localized: "trip.stops.map_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button {
                    showAddStop = true
                } label: {
                    Image(systemName: "mappin.and.ellipse.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.multicolor)
                }
                .accessibilityLabel(String(localized: "trip.add_stop.a11y"))
            }

            if sortedDestinations.contains(where: \.hasPlottableCoordinate) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isPastTrip ? String(localized: "trip.map.past") : String(localized: "trip.map.route"))
                        .font(.title2.weight(.bold))
                    Text(isPastTrip ? String(localized: "trip.map.past_desc") : String(localized: "trip.map.route_desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HolidayTripStopsMapView(trip: trip)
                        .frame(maxWidth: .infinity)
                        .clipped()
                }
            }

            if sortedDestinations.isEmpty {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .frame(height: 88)
                    .overlay {
                        Text(isPastTrip ? String(localized: "trip.no_stops.past") : String(localized: "trip.no_stops.future"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sortedDestinations.enumerated()), id: \.element.persistentModelID) { idx, dest in
                        DestinationTimelineRow(
                            destination: dest,
                            isFirst: idx == 0,
                            isLast: idx == sortedDestinations.count - 1
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Avatar bubble

private struct FamilyAvatarBubble: View {
    let name: String
    let index: Int
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: AvatarPalette.pair(for: name, index: index),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(name.trimmingCharacters(in: .whitespacesAndNewlines).initials(max: 2))
                .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

private struct TravelerGlassCard: View {
    let name: String
    let roleTag: String
    let index: Int

    var body: some View {
        VStack(spacing: 12) {
            FamilyAvatarBubble(name: name.isEmpty ? "?" : name, index: index, size: 64)
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                }
                .shadow(color: AvatarPalette.pair(for: name, index: index)[0].opacity(0.45), radius: 12, y: 6)

            VStack(spacing: 4) {
                Text(name.isEmpty ? String(localized: "trip.name") : name)
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !roleTag.isEmpty {
                    Text(roleTag)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.35),
                                    .white.opacity(0.06),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
    }
}

// MARK: - Timeline row

private struct DestinationTimelineRow: View {
    let destination: HolidayDestination
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                if !isFirst {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 2, height: 12)
                }
                Circle()
                    .fill(Color.accentColor.gradient)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .strokeBorder(Color(.systemBackground), lineWidth: 2)
                    }
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 2, height: 44)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(destination.locationName.isEmpty ? String(localized: "trip.stop_title") : destination.locationName)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(destination.arrivalDate.formatted(date: .abbreviated, time: .omitted)) – \(destination.departureDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !destination.activities.isEmpty {
                    Text(destination.activities)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? 0 : 20)
        }
    }
}

// MARK: - Sheets

struct AddHolidayDestinationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let trip: HolidayTrip

    @State private var locationName = ""
    @State private var latText = ""
    @State private var lonText = ""
    @State private var activities = ""
    @State private var arrival = Date()
    @State private var departure = Date()
    @State private var isLookingUp = false
    @State private var isSaving = false
    @State private var lookupAlertMessage: String?
    @State private var saveFailedMessage: String?

    private var trimmedPlaceName: String {
        locationName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedCoordinate: (lat: Double, lon: Double)? {
        let latClean = latText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        let lonClean = lonText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lat = Double(latClean), let lon = Double(lonClean),
              lat >= -90, lat <= 90, lon >= -180, lon <= 180
        else { return nil }
        return (lat, lon)
    }

    private var canSave: Bool {
        !trimmedPlaceName.isEmpty && !isSaving
    }

    private var tripStartDay: Date {
        let cal = Calendar.current
        let s = cal.startOfDay(for: trip.startDate)
        let e = cal.startOfDay(for: trip.endDate)
        return min(s, e)
    }

    private var tripEndDay: Date {
        let cal = Calendar.current
        let s = cal.startOfDay(for: trip.startDate)
        let e = cal.startOfDay(for: trip.endDate)
        return max(s, e)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "trip.place.place")) {
                    TextField(String(localized: "trip.place.city"), text: $locationName)
                    HolidayMapPlaceSearchBlock(
                        searchQuery: $locationName,
                        onPick: { candidate in
                            locationName = candidate.resolvedName
                            latText = String(format: "%.5f", candidate.coordinate.latitude)
                            lonText = String(format: "%.5f", candidate.coordinate.longitude)
                        },
                        isDisabled: isSaving
                    )
                    Button {
                        Task { await lookUpPlace() }
                    } label: {
                        if isLookingUp {
                            HStack {
                                ProgressView()
                                Text(String(localized: "trip.place.lookup"))
                            }
                        } else {
                            Label(String(localized: "trip.place.fill_coords"), systemImage: "mappin.and.ellipse")
                        }
                    }
                    .disabled(trimmedPlaceName.isEmpty || isLookingUp || isSaving)
                    TextField(String(localized: "trip.latitude"), text: $latText, prompt: Text(String(localized: "trip.lat.prompt")))
                        .keyboardType(.numbersAndPunctuation)
                    TextField(String(localized: "trip.longitude"), text: $lonText, prompt: Text(String(localized: "trip.lon.prompt")))
                        .keyboardType(.numbersAndPunctuation)
                }
                Section {
                    Text(String(localized: "trip.place.footer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section(String(localized: "trip.dates")) {
                    DatePicker(String(localized: "trip.arrival"), selection: $arrival, in: tripStartDay ... tripEndDay, displayedComponents: .date)
                        .onChange(of: arrival) { _, newArrival in
                            let cal = Calendar.current
                            let a = cal.startOfDay(for: newArrival)
                            let d = cal.startOfDay(for: departure)
                            if d < a { departure = a }
                        }
                    DatePicker(String(localized: "trip.departure"), selection: $departure, in: arrival ... tripEndDay, displayedComponents: .date)
                        .onChange(of: departure) { _, newDeparture in
                            let cal = Calendar.current
                            let a = cal.startOfDay(for: arrival)
                            let d = cal.startOfDay(for: newDeparture)
                            if d < a { arrival = d }
                        }
                }
                Section(String(localized: "trip.notes")) {
                    TextField(String(localized: "trip.activities"), text: $activities, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(String(localized: "trip.add_stop_nav"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let cal = Calendar.current
                let s = cal.startOfDay(for: trip.startDate)
                var e = cal.startOfDay(for: trip.endDate)
                if e < s { e = s }
                let a = s
                var d = e
                if d < a { d = a }
                arrival = a
                departure = d
            }
            .alert(String(localized: "trip.alert.find_place"), isPresented: Binding(
                get: { lookupAlertMessage != nil },
                set: { if !$0 { lookupAlertMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) { lookupAlertMessage = nil }
            } message: {
                Text(lookupAlertMessage ?? "")
            }
            .alert(String(localized: "trip.alert.save_stop"), isPresented: Binding(
                get: { saveFailedMessage != nil },
                set: { if !$0 { saveFailedMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) { saveFailedMessage = nil }
            } message: {
                Text(saveFailedMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add")) {
                        Task { await saveStop() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }

    private func lookUpPlace() async {
        isLookingUp = true
        defer { isLookingUp = false }
        do {
            let coord = try await HolidayGeocoding.coordinate(for: trimmedPlaceName)
            latText = String(format: "%.5f", coord.latitude)
            lonText = String(format: "%.5f", coord.longitude)
        } catch {
            lookupAlertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveStop() async {
        isSaving = true
        defer { isSaving = false }
        let coord: (lat: Double, lon: Double)
        if let manual = parsedCoordinate {
            coord = manual
        } else {
            do {
                let c = try await HolidayGeocoding.coordinate(for: trimmedPlaceName)
                coord = (c.latitude, c.longitude)
                latText = String(format: "%.5f", c.latitude)
                lonText = String(format: "%.5f", c.longitude)
            } catch {
                lookupAlertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
        }
        let cal = Calendar.current
        let a = cal.startOfDay(for: arrival)
        var d = cal.startOfDay(for: departure)
        if d < a { d = a }
        let dest = HolidayDestination(
            locationName: trimmedPlaceName,
            latitude: coord.lat,
            longitude: coord.lon,
            arrivalDate: a,
            departureDate: d,
            activities: activities,
            trip: trip
        )
        await MainActor.run {
            modelContext.insert(dest)
            do {
                try modelContext.save()
                dismiss()
            } catch {
                print("[TheGomsons] Failed to save holiday destination: \(error.localizedDescription)")
                saveFailedMessage = error.localizedDescription
            }
        }
    }
}

/// Create a new trip (`trip == nil`) or edit name, dates, and header photo.
struct HolidayTripEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// When creating: `nil`. When editing: the trip to update.
    var trip: HolidayTrip?

    /// When true, default date range is in the future (upcoming trip). When false, defaults to a recent past range for logging. Ignored when editing.
    var defaultsToFuture: Bool

    @State private var name = ""
    @State private var start: Date
    @State private var end: Date
    @State private var coverImageData: Data?
    @State private var notes = ""
    @State private var airlineName = ""
    @State private var bookingReference = ""
    @State private var mainAccommodation = ""
    @State private var coverPlaceName = ""
    @State private var coverLatitude = 0.0
    @State private var coverLongitude = 0.0
    @State private var saveFailedMessage: String?
    @State private var editingParticipant: HolidayTripParticipant?
    @State private var showAddTravelersInEditor = false

    init(trip: HolidayTrip? = nil, defaultsToFuture: Bool = true) {
        self.trip = trip
        self.defaultsToFuture = defaultsToFuture
        if let trip {
            _name = State(initialValue: trip.tripName)
            let cal = Calendar.current
            let s0 = cal.startOfDay(for: trip.startDate)
            let e0 = cal.startOfDay(for: trip.endDate)
            let s = s0
            let e = e0 < s0 ? s0 : e0
            _start = State(initialValue: s)
            _end = State(initialValue: e)
            _coverImageData = State(initialValue: trip.coverImageData)
            _notes = State(initialValue: trip.notes)
            _airlineName = State(initialValue: trip.airlineName)
            _bookingReference = State(initialValue: trip.bookingReference)
            _mainAccommodation = State(initialValue: trip.mainAccommodation)
            _coverPlaceName = State(initialValue: trip.coverPlaceName)
            _coverLatitude = State(initialValue: trip.coverLatitude)
            _coverLongitude = State(initialValue: trip.coverLongitude)
        } else {
            _name = State(initialValue: "")
            let cal = Calendar.current
            let now = Date()
            if defaultsToFuture {
                let t = cal.startOfDay(for: now)
                _start = State(initialValue: t)
                _end = State(initialValue: t)
            } else {
                let e = cal.date(byAdding: .day, value: -1, to: now).map { cal.startOfDay(for: $0) } ?? now
                let s = cal.date(byAdding: .day, value: -8, to: e).map { cal.startOfDay(for: $0) } ?? e
                _start = State(initialValue: s)
                _end = State(initialValue: e)
            }
            _notes = State(initialValue: "")
            _airlineName = State(initialValue: "")
            _bookingReference = State(initialValue: "")
            _mainAccommodation = State(initialValue: "")
            _coverPlaceName = State(initialValue: "")
            _coverLatitude = State(initialValue: 0)
            _coverLongitude = State(initialValue: 0)
        }
    }

    private var isEditing: Bool { trip != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Start of “today” in the current calendar (upcoming trips cannot start before this when creating).
    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Start date bounds: editing = full range; new upcoming = today onward; new past trip = through today.
    private var startPickerRange: ClosedRange<Date> {
        if isEditing { Date.distantPast ... Date.distantFuture }
        else if defaultsToFuture { todayStart ... Date.distantFuture }
        else { Date.distantPast ... todayStart }
    }

    /// End date is always on or after start; new past trips cannot end after today.
    private var endPickerRange: ClosedRange<Date> {
        if isEditing { start ... Date.distantFuture }
        else if defaultsToFuture { start ... Date.distantFuture }
        else { start ... todayStart }
    }

    private var editorParticipantsSorted: [HolidayTripParticipant] {
        guard let trip else { return [] }
        return (trip.participants ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "trip.section")) {
                    TextField(String(localized: "trip.trip.name"), text: $name, prompt: Text(String(localized: "trip.trip.prompt")))
                }
                HolidayCoverImageFormSection(
                    coverImageData: $coverImageData,
                    coverPlaceName: $coverPlaceName,
                    coverLatitude: $coverLatitude,
                    coverLongitude: $coverLongitude,
                    footerText: String(localized: "trip.cover.footer")
                )
                Section(String(localized: "trip.dates")) {
                    DatePicker(String(localized: "trip.date.start"), selection: $start, in: startPickerRange, displayedComponents: .date)
                        .onChange(of: start) { _, newStart in
                            let cal = Calendar.current
                            let s = cal.startOfDay(for: newStart)
                            start = s
                            var e = cal.startOfDay(for: end)
                            if e < s { e = s }
                            if !isEditing, !defaultsToFuture {
                                let t = cal.startOfDay(for: Date())
                                if e > t { e = t }
                            }
                            end = e
                        }
                    DatePicker(String(localized: "trip.date.end"), selection: $end, in: endPickerRange, displayedComponents: .date)
                        .onChange(of: end) { _, newEnd in
                            let cal = Calendar.current
                            var s = cal.startOfDay(for: start)
                            var e = cal.startOfDay(for: newEnd)
                            if !isEditing, !defaultsToFuture {
                                let t = cal.startOfDay(for: Date())
                                if e > t { e = t }
                            }
                            if e < s { s = e }
                            start = s
                            end = e
                        }
                }
                Section(String(localized: "trip.travel.stay.section")) {
                    TextField(String(localized: "trip.airline"), text: $airlineName)
                    TextField(String(localized: "trip.reference.field"), text: $bookingReference)
                    TextField(String(localized: "trip.main_accommodation"), text: $mainAccommodation, axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                Section(String(localized: "trip.notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }
                if isEditing, trip != nil {
                    Section(String(localized: "trip.travellers")) {
                        if editorParticipantsSorted.isEmpty {
                            Text(String(localized: "trip.travellers.none.hint"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(editorParticipantsSorted, id: \.persistentModelID) { p in
                                Button {
                                    editingParticipant = p
                                } label: {
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(p.displayName.isEmpty ? String(localized: "common.unnamed") : p.displayName)
                                            if !p.roleTag.isEmpty {
                                                Text(p.roleTag)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        Button {
                            showAddTravelersInEditor = true
                        } label: {
                            Label(String(localized: "trip.add_travellers"), systemImage: "person.badge.plus")
                        }
                    }
                }
                if !isEditing {
                    if defaultsToFuture {
                        Section {
                            Text(String(localized: "trip.travellers.footer.future"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section {
                            Text(String(localized: "trip.travellers.footer.past"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? String(localized: "trip.edit_trip") : (defaultsToFuture ? String(localized: "trip.new_trip") : String(localized: "trip.log_past")))
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
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                normalizeEditorDates()
            }
            .alert(String(localized: "trip.couldnt_save"), isPresented: Binding(
                get: { saveFailedMessage != nil },
                set: { if !$0 { saveFailedMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) { saveFailedMessage = nil }
            } message: {
                Text(saveFailedMessage ?? "")
            }
            .sheet(isPresented: $showAddTravelersInEditor) {
                if let trip {
                    AddTripParticipantSheet(trip: trip)
                }
            }
            .sheet(item: $editingParticipant) { p in
                EditTripParticipantSheet(participant: p)
            }
        }
    }

    private func normalizeEditorDates() {
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        var e = cal.startOfDay(for: end)
        if e < s { e = s }
        start = s
        end = e
    }

    private func save() {
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        var e = cal.startOfDay(for: end)
        if e < s { e = s }

        if let existing = trip {
            existing.tripName = trimmedName
            existing.startDate = s
            existing.endDate = e
            existing.notes = notes
            existing.coverImageData = coverImageData
            existing.airlineName = airlineName
            existing.bookingReference = bookingReference
            existing.mainAccommodation = mainAccommodation
            existing.coverPlaceName = coverPlaceName
            existing.coverLatitude = coverLatitude
            existing.coverLongitude = coverLongitude
        } else {
            let newTrip = HolidayTrip(
                tripName: trimmedName,
                startDate: s,
                endDate: e,
                notes: notes,
                airlineName: airlineName,
                bookingReference: bookingReference,
                mainAccommodation: mainAccommodation,
                coverImageData: coverImageData,
                coverPlaceName: coverPlaceName,
                coverLatitude: coverLatitude,
                coverLongitude: coverLongitude
            )
            modelContext.insert(newTrip)
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to save holiday trip: \(error.localizedDescription)")
            saveFailedMessage = error.localizedDescription
        }
    }
}

/// Presents `HolidayTripEditorSheet` in create mode (same defaults as before).
struct AddHolidayTripSheet: View {
    var defaultsToFuture: Bool

    var body: some View {
        HolidayTripEditorSheet(trip: nil, defaultsToFuture: defaultsToFuture)
    }
}

private struct EditTripParticipantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var participant: HolidayTripParticipant

    @State private var displayName: String
    @State private var roleTag: String
    @State private var saveFailedMessage: String?
    @State private var confirmRemove = false

    init(participant: HolidayTripParticipant) {
        self.participant = participant
        _displayName = State(initialValue: participant.displayName)
        _roleTag = State(initialValue: participant.roleTag)
    }

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "trip.traveller.section")) {
                    TextField(String(localized: "common.name"), text: $displayName)
                    TextField(String(localized: "trip.role.optional"), text: $roleTag, prompt: Text(String(localized: "trip.role.prompt")))
                }
                Section {
                    Button(String(localized: "trip.remove_from_trip"), role: .destructive) {
                        confirmRemove = true
                    }
                }
            }
            .navigationTitle(String(localized: "trip.traveller.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) {
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
                String(format: String(localized: "trip.remove_participant"), locale: .current, trimmedName.isEmpty ? String(localized: "trip.this_person") : trimmedName),
                isPresented: $confirmRemove,
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.remove"), role: .destructive) {
                    removeParticipant()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            }
        }
    }

    private func save() {
        participant.displayName = trimmedName
        participant.roleTag = roleTag.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to save traveller: \(error.localizedDescription)")
            saveFailedMessage = error.localizedDescription
        }
    }

    private func removeParticipant() {
        modelContext.delete(participant)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to remove traveller: \(error.localizedDescription)")
            saveFailedMessage = error.localizedDescription
        }
    }
}

private struct AddTripParticipantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let trip: HolidayTrip

    @State private var selectedFamily: Set<String> = []
    @State private var customName = ""
    @State private var roleTag = ""
    @State private var saveFailedMessage: String?

    private let familyNames = ["Pappa", "Mamma", "CC", "Herman"]

    private var trimmedCustom: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        !selectedFamily.isEmpty || !trimmedCustom.isEmpty
    }

    /// Names to insert, in a stable order: family list order first, then custom if present and not redundant.
    private var namesToInsert: [String] {
        var names: [String] = []
        for n in familyNames where selectedFamily.contains(n) {
            names.append(n)
        }
        if !trimmedCustom.isEmpty, !names.contains(trimmedCustom) {
            names.append(trimmedCustom)
        }
        return names
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "trip.family")) {
                    Text(trip.isPastTrip ? String(localized: "trip.family.hint.past") : String(localized: "trip.family.hint.future"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(familyNames, id: \.self) { name in
                        Toggle(isOn: bindingForFamily(name)) {
                            Text(name)
                                .font(.body.weight(.medium))
                        }
                    }
                }
                Section(String(localized: "trip.also_add")) {
                    TextField(String(localized: "trip.custom.prompt"), text: $customName)
                    Button {
                        customName = String(localized: "trip.guest_name")
                    } label: {
                        Label(String(localized: "trip.use_guest"), systemImage: "person.fill.questionmark")
                    }
                }
                Section(String(localized: "trip.role_all")) {
                    TextField(String(localized: "trip.shown_under"), text: $roleTag, prompt: Text(String(localized: "trip.role.prompt2")))
                }
            }
            .navigationTitle(String(localized: "trip.add_travelers.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addButtonTitle) {
                        addParticipants()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canAdd)
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

    private var addButtonTitle: String {
        let n = namesToInsert.count
        if n <= 1 { return String(localized: "common.add") }
        return String(format: String(localized: "trip.add_n"), locale: .current, n)
    }

    private func bindingForFamily(_ name: String) -> Binding<Bool> {
        Binding(
            get: { selectedFamily.contains(name) },
            set: { on in
                if on {
                    selectedFamily.insert(name)
                } else {
                    selectedFamily.remove(name)
                }
            }
        )
    }

    private func addParticipants() {
        let role = roleTag.trimmingCharacters(in: .whitespacesAndNewlines)
        var order = ((trip.participants ?? []).map(\.sortOrder).max() ?? -1) + 1
        for name in namesToInsert {
            let p = HolidayTripParticipant(
                displayName: name,
                roleTag: role,
                sortOrder: order,
                trip: trip
            )
            modelContext.insert(p)
            order += 1
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to save trip participants: \(error.localizedDescription)")
            saveFailedMessage = error.localizedDescription
        }
    }
}

// MARK: - Palette & string helpers

private enum AvatarPalette {
    static func pair(for name: String, index: Int) -> [Color] {
        let seeds: [(Double, Double)] = [
            (0.58, 0.72), (0.08, 0.18), (0.45, 0.58), (0.78, 0.88),
            (0.32, 0.48), (0.92, 0.08), (0.52, 0.65), (0.15, 0.35),
        ]
        let i = abs(name.hashValue &+ index) % seeds.count
        let (a, b) = seeds[i]
        return [
            Color(hue: a, saturation: 0.55, brightness: 0.85),
            Color(hue: b, saturation: 0.6, brightness: 0.55),
        ]
    }
}

private extension String {
    func initials(max: Int) -> String {
        let parts = split(separator: " ").filter { !$0.isEmpty }
        if parts.isEmpty {
            let c = prefix(1)
            return String(c).uppercased()
        }
        let take = min(max, parts.count)
        return parts.prefix(take).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

// MARK: - Past-trip review (text + up to 3 photos)

private struct HolidayTripReviewSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: HolidayTrip

    @State private var pickerItem: PhotosPickerItem?
    @State private var pickerTargetSlot: Int?
    @State private var photoViewer: ReviewPhotoViewerItem?

    private let maxPhotos = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "trip.review"))
                .font(.title2.weight(.bold))
            Text(String(localized: "trip.review.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $trip.reviewText)
                .font(.body)
                .frame(minHeight: 110)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 1)
                }
                .onChange(of: trip.reviewText) { _, _ in
                    try? modelContext.save()
                }

            Text(String(localized: "trip.review.photos"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(0..<maxPhotos, id: \.self) { index in
                    reviewPhotoSlot(at: index)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: pickerItem) { _, item in
            Task { await importPickedPhoto(item) }
        }
        .fullScreenCover(item: $photoViewer) { item in
            HolidayTripReviewPhotoViewer(imageData: item.data) {
                photoViewer = nil
            }
        }
    }

    @ViewBuilder
    private func reviewPhotoSlot(at index: Int) -> some View {
        if let data = trip.reviewPhotoData(at: index), let ui = UIImage(data: data) {
            ZStack(alignment: .topTrailing) {
                Button {
                    photoViewer = ReviewPhotoViewerItem(data: data)
                } label: {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "trip.review.photo_a11y"))

                Button {
                    trip.setReviewPhotoData(nil, at: index)
                    try? modelContext.save()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .font(.title3)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "trip.review.remove_photo"))
            }
            .frame(maxWidth: .infinity)
        } else {
            PhotosPicker(
                selection: Binding(
                    get: { pickerTargetSlot == index ? pickerItem : nil },
                    set: { newValue in
                        pickerTargetSlot = index
                        pickerItem = newValue
                    }
                ),
                matching: .images,
                photoLibrary: .shared()
            ) {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                    Text(String(localized: "trip.review.slot"))
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(Color(.separator))
                }
            }
            .accessibilityLabel(String(localized: "trip.review.add_photo"))
            .frame(maxWidth: .infinity)
        }
    }

    private func importPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let slot = pickerTargetSlot ?? trip.firstEmptyReviewPhotoSlot
        guard let slot else {
            await MainActor.run {
                pickerItem = nil
                pickerTargetSlot = nil
            }
            return
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.85)
        else {
            await MainActor.run {
                pickerItem = nil
                pickerTargetSlot = nil
            }
            return
        }
        await MainActor.run {
            trip.setReviewPhotoData(jpeg, at: slot)
            try? modelContext.save()
            pickerItem = nil
            pickerTargetSlot = nil
        }
    }
}

private struct ReviewPhotoViewerItem: Identifiable {
    let id = UUID()
    let data: Data
}

private struct HolidayTripReviewPhotoViewer: View {
    let imageData: Data
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let ui = UIImage(data: imageData) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                } else {
                    ContentUnavailableView(
                        String(localized: "trip.review.photo_missing"),
                        systemImage: "photo"
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.done")) {
                        onClose()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension HolidayTrip {
    var coverUIImage: UIImage? {
        guard let data = coverImageData else { return nil }
        return UIImage(data: data)
    }
}

#Preview("Past trips content") {
    NavigationStack {
        HolidayTripsListContent()
            .navigationTitle(String(localized: "trip.past_trips_title"))
    }
    .modelContainer(
        for: [
            HolidayTrip.self,
            HolidayDestination.self,
            HolidayTripParticipant.self,
        ],
        inMemory: true
    )
}

