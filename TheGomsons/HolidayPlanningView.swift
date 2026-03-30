//
//  HolidayPlanningView.swift
//  TheGomsons
//

import CoreLocation
import SwiftData
import SwiftUI

private enum HolidayAppUser: String, CaseIterable, Identifiable {
    case pappa = "Pappa"
    case mamma = "Mamma"
    case cc = "CC"
    case herman = "Herman"

    var id: String { rawValue }
}

/// Voting on vacation ideas (top) and family holiday chat (bottom).
struct HolidayPlanningView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("holidayChatFamilyShortcut") private var shortcutRaw: String = "Pappa"

    @Query(sort: \VacationIdea.upvotes, order: .reverse) private var ideas: [VacationIdea]
    @Query(sort: \HolidayChatMessage.timestamp, order: .forward) private var chatMessages: [HolidayChatMessage]

    @State private var draftMessage = ""
    @State private var showProposeIdea = false
    @FocusState private var chatFieldFocused: Bool

    private var currentShortcut: HolidayAppUser {
        HolidayAppUser(rawValue: shortcutRaw) ?? .pappa
    }

    private var senderNameForMessages: String {
        currentShortcut.rawValue
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                votingSection
                    .frame(height: max(geo.size.height * 0.42, 200))

                Divider()

                chatSection
                    .frame(maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showProposeIdea) {
            ProposeVacationIdeaSheet()
        }
    }

    // MARK: - Voting

    private var votingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Vacation ideas")
                    .font(.headline)
                Spacer()
                Button {
                    showProposeIdea = true
                } label: {
                    Label("Propose", systemImage: "lightbulb.max.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if ideas.isEmpty {
                ContentUnavailableView(
                    "No ideas yet",
                    systemImage: "hand.thumbsup.circle",
                    description: Text("Propose a destination and dates—family can vote with a thumbs up.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(ideas) { idea in
                            VacationIdeaVoteCard(idea: idea)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: - Chat

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Family chat")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 8) {
                Text("Chatting as")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(HolidayAppUser.allCases) { user in
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
                            .accessibilityLabel(user.rawValue)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(chatMessages) { msg in
                            HolidayChatBubbleRow(
                                message: msg,
                                isFromCurrentUser: isCurrentUser(senderName: msg.senderName)
                            )
                            .id(msg.persistentModelID)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    scrollChatToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: chatMessages.count) { _, _ in
                    scrollChatToBottom(proxy: proxy, animated: true)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $draftMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($chatFieldFocused)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func isCurrentUser(senderName: String) -> Bool {
        let a = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return a == senderNameForMessages
    }

    private func sendMessage() {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let msg = HolidayChatMessage(senderName: senderNameForMessages, messageText: text, timestamp: Date())
        modelContext.insert(msg)
        draftMessage = ""
        chatFieldFocused = false
    }

    private func scrollChatToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard let last = chatMessages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(last.persistentModelID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last.persistentModelID, anchor: .bottom)
        }
    }
}

// MARK: - Idea card

private struct VacationIdeaVoteCard: View {
    @Bindable var idea: VacationIdea

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(idea.proposedDestination.isEmpty ? "Destination" : idea.proposedDestination)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: 200, alignment: .leading)

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
                    .lineLimit(3)
            }

            HStack {
                Label("\(idea.upvotes)", systemImage: "hand.thumbsup.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    idea.upvotes += 1
                } label: {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.gradient, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Upvote")
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
    }
}

// MARK: - Chat bubble

private struct HolidayChatBubbleRow: View {
    let message: HolidayChatMessage
    let isFromCurrentUser: Bool

    var body: some View {
        HStack {
            if isFromCurrentUser { Spacer(minLength: 48) }
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isFromCurrentUser {
                    Text(message.senderName.isEmpty ? "Someone" : message.senderName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(message.messageText)
                    .font(.body)
                    .foregroundStyle(isFromCurrentUser ? Color.white : Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isFromCurrentUser ? Color.blue : Color(.systemGray5))
                    }
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !isFromCurrentUser { Spacer(minLength: 48) }
        }
    }
}

// MARK: - Propose sheet

private struct ProposeVacationIdeaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var destination = ""
    @State private var dates = ""
    @State private var notes = ""
    @State private var isSaving = false

    private var trimmedDestination: String {
        destination.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Idea") {
                    TextField("Destination", text: $destination)
                    TextField("Proposed dates", text: $dates, prompt: Text("e.g. July 12–20"))
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Text("We look up the destination when you add the idea so it can appear on the World Map with a lightbulb pin. If the lookup misses, the idea is still saved—it just won’t show on the map until you edit it with a clearer place name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Propose a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveIdea() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Add").fontWeight(.semibold)
                        }
                    }
                    .disabled(trimmedDestination.isEmpty || isSaving)
                }
            }
        }
    }

    private func saveIdea() async {
        isSaving = true
        defer { isSaving = false }
        var lat = 0.0
        var lon = 0.0
        if let c = try? await HolidayGeocoding.coordinate(for: trimmedDestination) {
            lat = c.latitude
            lon = c.longitude
        }
        await MainActor.run {
            let idea = VacationIdea(
                proposedDestination: trimmedDestination,
                proposedDates: dates,
                notes: notes,
                upvotes: 0,
                latitude: lat,
                longitude: lon
            )
            modelContext.insert(idea)
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
