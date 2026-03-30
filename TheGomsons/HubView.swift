//
//  HubView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

struct HubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openFamilyLanding) private var openFamilyLanding
    @State private var section: HubSection = .recipes

    enum HubSection: String, CaseIterable {
        case recipes = "Recipes"
        case calendar = "Calendar"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Hub section", selection: $section) {
                    ForEach(HubSection.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch section {
                    case .recipes:
                        RecipeHubPanel()
                    case .calendar:
                        CalendarHubPanel()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Hub")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                if section == .calendar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            let event = FamilyEvent(
                                title: "New event",
                                date: Date(),
                                location: "",
                                assignedTo: ""
                            )
                            modelContext.insert(event)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityLabel("Add event")
                    }
                }
            }
        }
    }
}

private struct RecipeHubPanel: View {
    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    var body: some View {
        Group {
            if recipes.isEmpty {
                ContentUnavailableView(
                    "No recipes",
                    systemImage: "fork.knife",
                    description: Text("Save family favorites here for quick access.")
                )
            } else {
                List {
                    ForEach(recipes) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.title.isEmpty ? "Untitled" : recipe.title)
                                    .font(.headline)
                                if recipe.prepTime > 0 {
                                    Text("Prep \(formattedPrep(recipe.prepTime))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func formattedPrep(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "\(Int(seconds / 60)) min"
    }
}

private struct RecipeDetailView: View {
    @Bindable var recipe: Recipe

    var body: some View {
        List {
            Section("Ingredients") {
                if recipe.ingredients.isEmpty {
                    Text("None listed")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }
            }
            Section("Instructions") {
                Text(recipe.instructions.isEmpty ? "—" : recipe.instructions)
            }
            if recipe.prepTime > 0 {
                Section("Timing") {
                    LabeledContent("Prep") {
                        Text(DateComponentsFormatter.prepFormatter.string(from: recipe.prepTime) ?? "—")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(recipe.title.isEmpty ? "Recipe" : recipe.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension DateComponentsFormatter {
    static let prepFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .full
        return f
    }()
}

private struct CalendarHubPanel: View {
    @Query(sort: \FamilyEvent.date) private var events: [FamilyEvent]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView(
                    "No events",
                    systemImage: "calendar",
                    description: Text("Plan trips, dinners, and school nights in one place.")
                )
            } else {
                List {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.title.isEmpty ? "Untitled" : event.title)
                                .font(.headline)
                            Text(event.date, format: Date.FormatStyle(date: .complete, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !event.location.isEmpty {
                                Label(event.location, systemImage: "mappin.and.ellipse")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            if !event.assignedTo.isEmpty {
                                Label(event.assignedTo, systemImage: "person.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteEvents)
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func deleteEvents(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(events[index])
        }
    }
}

#Preview {
    HubView()
        .modelContainer(for: [Recipe.self, FamilyEvent.self], inMemory: true)
}
