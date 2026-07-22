//
//  HolidayPlanningView.swift
//  TheGomsons
//

import CoreLocation
import SwiftData
import SwiftUI
import UIKit

/// Proposals and family voting—when all four vote thumbs-up, the idea shows “Let’s do it!”.
struct HolidayPlanningView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("holidayChatFamilyShortcut") private var shortcutRaw: String = HolidayFamilyVoter.pappa.rawValue

    @Query(sort: \VacationIdea.proposedDestination, order: .forward) private var ideas: [VacationIdea]

    @State private var showProposeIdea = false
    @State private var ideaToEdit: VacationIdea?
    @State private var ideaPendingDelete: VacationIdea?

    private var sortedIdeas: [VacationIdea] {
        ideas.sorted {
            if $0.hasUnanimousFamilyVotes != $1.hasUnanimousFamilyVotes {
                return $0.hasUnanimousFamilyVotes && !$1.hasUnanimousFamilyVotes
            }
            if $0.voteCount != $1.voteCount { return $0.voteCount > $1.voteCount }
            return $0.proposedDestination.localizedCaseInsensitiveCompare($1.proposedDestination) == .orderedAscending
        }
    }

    private var senderNameForMessages: String {
        HolidayFamilyVoter(rawValue: shortcutRaw)?.rawValue ?? HolidayFamilyVoter.pappa.rawValue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "planning.proposals"))
                            .font(.headline)
                        Text(String(localized: "planning.vote_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        showProposeIdea = true
                    } label: {
                        Label(String(localized: "planning.propose"), systemImage: "lightbulb.max.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "planning.voting_as"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(HolidayFamilyVoter.allCases) { user in
                                let selected = user.rawValue == shortcutRaw
                                Button {
                                    shortcutRaw = user.rawValue
                                } label: {
                                    Text(user.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background {
                                            Capsule()
                                                .fill(selected ? Color.accentColor : Color(.tertiarySystemFill))
                                        }
                                        .foregroundStyle(selected ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if sortedIdeas.isEmpty {
                    ContentUnavailableView(
                        String(localized: "planning.empty_title"),
                        systemImage: "hand.thumbsup.circle",
                        description: Text(String(localized: "planning.idea_footer"))
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(sortedIdeas) { idea in
                            VacationIdeaVoteCard(
                                idea: idea,
                                currentVoterName: senderNameForMessages,
                                onEdit: { ideaToEdit = idea },
                                onDelete: { ideaPendingDelete = idea }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showProposeIdea) {
            VacationIdeaEditorSheet(idea: nil)
        }
        .sheet(item: $ideaToEdit) { idea in
            VacationIdeaEditorSheet(idea: idea)
        }
        .confirmationDialog(
            String(localized: "planning.delete_confirm"),
            isPresented: Binding(
                get: { ideaPendingDelete != nil },
                set: { if !$0 { ideaPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "planning.delete"), role: .destructive) {
                if let idea = ideaPendingDelete {
                    modelContext.delete(idea)
                    try? modelContext.save()
                }
                ideaPendingDelete = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                ideaPendingDelete = nil
            }
        }
    }
}

// MARK: - Idea card

private struct VacationIdeaVoteCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var idea: VacationIdea
    let currentVoterName: String
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var voted: Bool {
        idea.hasVoted(name: currentVoterName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let ui = idea.coverUIImage {
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
                                .font(.system(size: 36, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity)
                .frame(height: 120)

                Text(
                    idea.proposedDestination.isEmpty
                        ? String(localized: "planning.destination_placeholder")
                        : idea.proposedDestination
                )
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(
                        idea.hasUnanimousFamilyVotes
                            ? String(localized: "planning.lets_do_it")
                            : String(localized: "planning.waiting")
                    )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(idea.hasUnanimousFamilyVotes ? Color.green : Color.secondary)
                    Spacer(minLength: 8)
                    Menu {
                        Button {
                            onEdit()
                        } label: {
                            Label(String(localized: "common.edit"), systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label(String(localized: "planning.delete"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(String(localized: "planning.proposal_actions"))
                }

                HStack(spacing: 10) {
                    ForEach(HolidayFamilyVoter.allCases) { member in
                        let on = idea.hasVoted(name: member.rawValue)
                        VStack(spacing: 4) {
                            Image(systemName: on ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.caption)
                                .foregroundStyle(on ? SimpsonsTheme.blue : Color.secondary.opacity(0.6))
                            Text(member.rawValue)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if !idea.proposedDates.isEmpty {
                    Label(idea.proposedDates, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }

                if !idea.notes.isEmpty {
                    Text(idea.notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Label("\(idea.voteCount)/\(HolidayFamilyVoter.allCases.count)", systemImage: "hand.thumbsup.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        idea.toggleVote(for: currentVoterName)
                        try? modelContext.save()
                    } label: {
                        Image(systemName: voted ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(voted ? Color.white : SimpsonsTheme.blue)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle().fill(voted ? SimpsonsTheme.blue : Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        voted
                            ? String(localized: "planning.remove_vote")
                            : String(localized: "planning.vote")
                    )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label(String(localized: "common.edit"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(String(localized: "planning.delete"), systemImage: "trash")
            }
        }
    }
}

private extension VacationIdea {
    var coverUIImage: UIImage? {
        guard let data = coverImageData else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Create / edit sheet

private struct VacationIdeaEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// `nil` = create new proposal.
    let idea: VacationIdea?

    @State private var destination = ""
    @State private var dates = ""
    @State private var notes = ""
    @State private var coverImageData: Data?
    @State private var isSaving = false
    /// Set when the user picks a map search row (avoids a second geocode on save).
    @State private var coordinateFromMapPick: CLLocationCoordinate2D?
    @State private var isApplyingMapPick = false

    private var isEditing: Bool { idea != nil }

    private var trimmedDestination: String {
        destination.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "planning.destination")) {
                    TextField(String(localized: "planning.city_or_place"), text: $destination)
                    HolidayMapPlaceSearchBlock(
                        searchQuery: $destination,
                        buttonTitle: String(localized: "planning.search_places"),
                        onPick: { candidate in
                            isApplyingMapPick = true
                            destination = candidate.resolvedName
                            coordinateFromMapPick = candidate.coordinate
                            Task { @MainActor in
                                isApplyingMapPick = false
                            }
                        }
                    )
                }
                Section(String(localized: "planning.idea")) {
                    TextField(
                        String(localized: "planning.proposed_dates"),
                        text: $dates,
                        prompt: Text(String(localized: "planning.date_range"))
                    )
                    TextField(String(localized: "planning.notes_optional"), text: $notes, axis: .vertical)
                        .lineLimit(3 ... 6)
                }
                HolidayCoverImageFormSection(
                    coverImageData: $coverImageData,
                    headingTitle: String(localized: "planning.cover_heading"),
                    cityFieldTitle: String(localized: "planning.cover_city"),
                    searchButtonTitle: String(localized: "planning.cover_search"),
                    footerText: String(localized: "planning.cover_footer")
                )
                Section {
                    Text(String(localized: "planning.geocode_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(
                isEditing
                    ? String(localized: "planning.edit_title")
                    : String(localized: "planning.title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveIdea() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(
                                isEditing
                                    ? String(localized: "common.save")
                                    : String(localized: "planning.add")
                            )
                            .fontWeight(.semibold)
                        }
                    }
                    .disabled(trimmedDestination.isEmpty || isSaving)
                }
            }
            .onAppear {
                guard let idea else { return }
                destination = idea.proposedDestination
                dates = idea.proposedDates
                notes = idea.notes
                coverImageData = idea.coverImageData
                if idea.hasPlottableCoordinate {
                    coordinateFromMapPick = idea.coordinate
                }
            }
            .onChange(of: destination) { _, _ in
                if !isApplyingMapPick {
                    coordinateFromMapPick = nil
                }
            }
        }
    }

    private func saveIdea() async {
        isSaving = true
        defer { isSaving = false }
        var lat = 0.0
        var lon = 0.0
        if let picked = coordinateFromMapPick {
            lat = picked.latitude
            lon = picked.longitude
        } else if let existing = idea, existing.hasPlottableCoordinate,
                  destination == existing.proposedDestination {
            lat = existing.latitude
            lon = existing.longitude
        } else if let c = try? await HolidayGeocoding.coordinate(for: trimmedDestination) {
            lat = c.latitude
            lon = c.longitude
        }
        await MainActor.run {
            if let idea {
                idea.proposedDestination = trimmedDestination
                idea.proposedDates = dates
                idea.notes = notes
                idea.coverImageData = coverImageData
                idea.latitude = lat
                idea.longitude = lon
                try? modelContext.save()
            } else {
                let created = VacationIdea(
                    proposedDestination: trimmedDestination,
                    proposedDates: dates,
                    notes: notes,
                    voterNamesJSON: "[]",
                    coverImageData: coverImageData,
                    latitude: lat,
                    longitude: lon
                )
                modelContext.insert(created)
            }
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        HolidayPlanningView()
    }
    .modelContainer(
        for: [VacationIdea.self, HolidayChatMessage.self],
        inMemory: true
    )
}
