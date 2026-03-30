//
//  HolidaysRootView.swift
//  TheGomsons
//

import CoreLocation
import SwiftData
import SwiftUI
import UIKit

// MARK: - Past trips (embedded in Holiday Hub)

/// Trip list for the **Past Trips** segment; expects an outer `NavigationStack` (see `HolidaysView`).
struct HolidaysPastTripsContent: View {
    @Query(sort: \HolidayTrip.startDate, order: .reverse) private var trips: [HolidayTrip]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(trips) { trip in
                    NavigationLink {
                        HolidayTripDetailView(trip: trip)
                    } label: {
                        HolidayTripCard(trip: trip)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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
                    "No trips yet",
                    systemImage: "airplane.departure",
                    description: Text("Log where you’ve been and who came along—photos, stops, and family faces in one place.")
                )
                .background(.thinMaterial.opacity(0.001))
            }
        }
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
                .frame(height: 160)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 160)

                VStack(alignment: .leading, spacing: 6) {
                    Text(trip.tripName.isEmpty ? "Untitled trip" : trip.tripName)
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
                    Label("Add who went", systemImage: "person.3.sequence.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 0) {
                        Text("Crew")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.6)
                        Spacer()
                    }
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
                        Text("\((trip.destinations ?? []).count) stop\((trip.destinations ?? []).count == 1 ? "" : "s")")
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}

// MARK: - Detail

struct HolidayTripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: HolidayTrip

    @State private var showAddTraveler = false
    @State private var showAddStop = false

    private var sortedParticipants: [HolidayTripParticipant] {
        (trip.participants ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedDestinations: [HolidayDestination] {
        (trip.destinations ?? []).sorted { $0.arrivalDate < $1.arrivalDate }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
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
                    .frame(height: 280)
                    .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: 280)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(trip.tripName.isEmpty ? "Trip" : trip.tripName)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                        Text(dateRangePhrase)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }

                VStack(alignment: .leading, spacing: 28) {
                    familySection

                    destinationsSection
                }
                .padding(24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddTraveler) {
            AddTripParticipantSheet(trip: trip)
        }
        .sheet(isPresented: $showAddStop) {
            AddHolidayDestinationSheet(trip: trip)
        }
    }

    private var dateRangePhrase: String {
        let a = trip.startDate.formatted(date: .long, time: .omitted)
        let b = trip.endDate.formatted(date: .long, time: .omitted)
        return "\(a) → \(b)"
    }

    private var familySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Who went")
                        .font(.title2.weight(.bold))
                    Text("Your holiday crew—tap the + to add someone.")
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
                .accessibilityLabel("Add travelers")
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
                            Text("No one added yet")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 148), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(Array(sortedParticipants.enumerated()), id: \.element.persistentModelID) { index, person in
                        TravelerGlassCard(
                            name: person.displayName,
                            roleTag: person.roleTag,
                            index: index
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(person)
                            } label: {
                                Label("Remove from trip", systemImage: "person.fill.xmark")
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
                    Text("Stops")
                        .font(.title2.weight(.bold))
                    Text("Add a pin with coordinates to show it on the holiday world map.")
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
                .accessibilityLabel("Add stop")
            }

            if sortedDestinations.isEmpty {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .frame(height: 88)
                    .overlay {
                        Text("No stops yet—tap + to add a place you visited.")
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
                Text(name.isEmpty ? "Name" : name)
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
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(destination.locationName.isEmpty ? "Stop" : destination.locationName)
                    .font(.headline)
                Text("\(destination.arrivalDate.formatted(date: .abbreviated, time: .omitted)) – \(destination.departureDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !destination.activities.isEmpty {
                    Text(destination.activities)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Place") {
                    TextField("Location name", text: $locationName)
                    Button {
                        Task { await lookUpPlace() }
                    } label: {
                        if isLookingUp {
                            HStack {
                                ProgressView()
                                Text("Looking up…")
                            }
                        } else {
                            Label("Look up coordinates from name", systemImage: "mappin.and.ellipse")
                        }
                    }
                    .disabled(trimmedPlaceName.isEmpty || isLookingUp || isSaving)
                    TextField("Latitude", text: $latText, prompt: Text("Filled by lookup or type e.g. 59.9139"))
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Longitude", text: $lonText, prompt: Text("Filled by lookup or type e.g. 10.7522"))
                        .keyboardType(.numbersAndPunctuation)
                }
                Section {
                    Text("Tip: enter a place name and tap look up, or paste coordinates from Maps. The world map only shows stops with real coordinates—not 0,0.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Dates") {
                    DatePicker("Arrival", selection: $arrival, displayedComponents: .date)
                    DatePicker("Departure", selection: $departure, displayedComponents: .date)
                }
                Section("Notes") {
                    TextField("Activities / notes (optional)", text: $activities, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("Add stop")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                arrival = trip.startDate
                departure = trip.endDate
            }
            .alert("Couldn’t find place", isPresented: Binding(
                get: { lookupAlertMessage != nil },
                set: { if !$0 { lookupAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { lookupAlertMessage = nil }
            } message: {
                Text(lookupAlertMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
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
        let dest = HolidayDestination(
            locationName: trimmedPlaceName,
            latitude: coord.lat,
            longitude: coord.lon,
            arrivalDate: arrival,
            departureDate: departure,
            activities: activities,
            trip: trip
        )
        await MainActor.run {
            modelContext.insert(dest)
            dismiss()
        }
    }
}

struct AddHolidayTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Name", text: $name)
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                    DatePicker("End", selection: $end, displayedComponents: .date)
                }
            }
            .navigationTitle("New trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trip = HolidayTrip(tripName: name, startDate: start, endDate: end)
                        modelContext.insert(trip)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
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
                Section("Family") {
                    Text("Turn on everyone who went—then tap Add once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(familyNames, id: \.self) { name in
                        Toggle(isOn: bindingForFamily(name)) {
                            Text(name)
                                .font(.body.weight(.medium))
                        }
                    }
                }
                Section("Also add (optional)") {
                    TextField("e.g. Grandma, Alex", text: $customName)
                    Button {
                        customName = "Guest"
                    } label: {
                        Label("Use “Guest”", systemImage: "person.fill.questionmark")
                    }
                }
                Section("Role for everyone added (optional)") {
                    TextField("Shown under each name", text: $roleTag, prompt: Text("e.g. Teen, toddler"))
                }
            }
            .navigationTitle("Add travelers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addButtonTitle) {
                        addParticipants()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canAdd)
                }
            }
        }
    }

    private var addButtonTitle: String {
        let n = namesToInsert.count
        if n <= 1 { return "Add" }
        return "Add \(n)"
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
        dismiss()
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

private extension HolidayTrip {
    var coverUIImage: UIImage? {
        guard let data = coverImageData else { return nil }
        return UIImage(data: data)
    }
}

#Preview("Past trips content") {
    NavigationStack {
        HolidaysPastTripsContent()
            .navigationTitle("Past Trips")
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
