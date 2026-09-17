//
//  RecipesView.swift
//  TheGomsons
//
//  Shared family recipe box, optionally tied to a property or free-text place.
//

import SwiftData
import SwiftUI

struct RecipesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Recipe.sortOrder), SortDescriptor(\Recipe.title)])
    private var allRecipes: [Recipe]
    @Query(sort: [SortDescriptor(\Property.sortOrder), SortDescriptor(\Property.name)]) private var properties: [Property]

    /// When set, only show recipes for this property (plus allow adding with it preselected).
    var filterProperty: Property? = nil

    @State private var showEditor = false
    @State private var recipeToEdit: Recipe?
    @State private var searchText = ""

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleRecipes: [Recipe] {
        var list = allRecipes
        if let filterProperty {
            let id = filterProperty.persistentModelID
            list = list.filter { $0.property?.persistentModelID == id }
        }
        let q = trimmedSearch
        guard !q.isEmpty else { return list }
        return list.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(q)
                || recipe.placeSummary.localizedCaseInsensitiveContains(q)
                || recipe.ingredients.contains { $0.localizedCaseInsensitiveContains(q) }
                || recipe.instructions.localizedCaseInsensitiveContains(q)
                || recipe.trimmedNotes.localizedCaseInsensitiveContains(q)
        }
    }

    private var groupedByPlace: [(key: String, recipes: [Recipe])] {
        let grouped = Dictionary(grouping: visibleRecipes) { $0.placeSummary }
        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { key in (key, Recipe.sorted(grouped[key] ?? [])) }
    }

    var body: some View {
        Group {
            if allRecipes.isEmpty && filterProperty == nil {
                emptyAll
            } else if visibleRecipes.isEmpty {
                emptyFiltered
            } else {
                List {
                    ForEach(groupedByPlace, id: \.key) { bucket in
                        Section {
                            ForEach(bucket.recipes) { recipe in
                                Button {
                                    recipeToEdit = recipe
                                } label: {
                                    RecipeRowView(recipe: recipe, showsPlace: filterProperty == nil)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteRecipe(recipe)
                                    } label: {
                                        Label(String(localized: "common.delete"), systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            if filterProperty == nil {
                                Text(bucket.key)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(
            filterProperty.map { _ in String(localized: "recipe.place_title") }
                ?? String(localized: "recipe.box_title")
        )
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: String(localized: "recipe.search_prompt"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(String(localized: "recipe.add"))
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                RecipeEditorView(defaultProperty: filterProperty)
            }
        }
        .sheet(item: $recipeToEdit) { recipe in
            NavigationStack {
                RecipeEditorView(recipeToEdit: recipe)
            }
        }
    }

    private var emptyAll: some View {
        ContentUnavailableView(
            String(localized: "recipe.empty_title"),
            systemImage: "frying.pan.fill",
            description: Text(String(localized: "recipe.empty_detail"))
        )
    }

    private var emptyFiltered: some View {
        ContentUnavailableView(
            trimmedSearch.isEmpty
                ? String(localized: "recipe.empty_place_title")
                : String(localized: "recipe.no_matches"),
            systemImage: trimmedSearch.isEmpty ? "frying.pan" : "magnifyingglass",
            description: Text(
                trimmedSearch.isEmpty
                    ? String(localized: "recipe.empty_place_detail")
                    : String(format: String(localized: "recipe.search_empty"), locale: .current, trimmedSearch)
            )
        )
    }

    private func deleteRecipe(_ recipe: Recipe) {
        modelContext.delete(recipe)
        do {
            try modelContext.save()
        } catch {
            print("[TheGomsons] Failed to delete recipe: \(error.localizedDescription)")
        }
    }
}

// MARK: - Row

private struct RecipeRowView: View {
    let recipe: Recipe
    var showsPlace: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.title.isEmpty ? String(localized: "recipe.untitled") : recipe.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                if showsPlace {
                    Label(recipe.placeSummary, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if recipe.prepTimeMinutes > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Label("\(recipe.prepTimeMinutes) \(String(localized: "recipe.minutes_short"))", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !recipe.ingredients.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(
                        String(
                            format: String(localized: "recipe.ingredient_count"),
                            locale: .current,
                            recipe.ingredients.count
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Editor

struct RecipeEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Property.sortOrder), SortDescriptor(\Property.name)]) private var properties: [Property]

    var recipeToEdit: Recipe? = nil
    var defaultProperty: Property? = nil

    @State private var title = ""
    @State private var placeLabel = ""
    @State private var notes = ""
    @State private var instructions = ""
    @State private var prepMinutes = 0
    @State private var selectedProperty: Property?
    @State private var draftIngredients: [String] = [""]
    @State private var confirmDelete = false

    private var isNew: Bool { recipeToEdit == nil }

    private var activeProperties: [Property] {
        properties.filter { !$0.isArchived }
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "recipe.title_field"), text: $title)
                HStack {
                    Text(String(localized: "recipe.prep_time"))
                    Spacer()
                    TextField("0", value: $prepMinutes, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 72)
                    Text(String(localized: "recipe.minutes_short"))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker(String(localized: "recipe.property"), selection: $selectedProperty) {
                    Text(String(localized: "recipe.place.family"))
                        .tag(nil as Property?)
                    ForEach(activeProperties) { property in
                        Text(property.name.isEmpty ? String(localized: "property.unnamed") : property.name)
                            .tag(property as Property?)
                    }
                }
                TextField(String(localized: "recipe.place_label"), text: $placeLabel, axis: .vertical)
                    .lineLimit(1 ... 3)
            } header: {
                Text(String(localized: "recipe.place_section"))
            } footer: {
                Text(String(localized: "recipe.place_footer"))
            }

            Section(String(localized: "recipe.ingredients")) {
                ForEach(draftIngredients.indices, id: \.self) { index in
                    HStack {
                        TextField(String(localized: "recipe.ingredient_placeholder"), text: $draftIngredients[index])
                        if draftIngredients.count > 1 {
                            Button {
                                draftIngredients.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button {
                    draftIngredients.append("")
                } label: {
                    Label(String(localized: "recipe.add_ingredient"), systemImage: "plus.circle")
                }
            }

            Section(String(localized: "recipe.instructions")) {
                TextField(String(localized: "recipe.instructions_placeholder"), text: $instructions, axis: .vertical)
                    .lineLimit(4 ... 16)
            }

            Section(String(localized: "common.notes")) {
                TextField(String(localized: "recipe.notes_placeholder"), text: $notes, axis: .vertical)
                    .lineLimit(2 ... 6)
            }

            if !isNew {
                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Text(String(localized: "recipe.delete"))
                    }
                }
            }
        }
        .navigationTitle(isNew ? String(localized: "recipe.new") : String(localized: "recipe.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "common.save")) { save() }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear(perform: load)
        .confirmationDialog(
            String(localized: "recipe.delete_confirm"),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                if let recipe = recipeToEdit {
                    modelContext.delete(recipe)
                    try? modelContext.save()
                }
                dismiss()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
    }

    private func load() {
        if let recipe = recipeToEdit {
            title = recipe.title
            placeLabel = recipe.placeLabel
            notes = recipe.notes
            instructions = recipe.instructions
            prepMinutes = recipe.prepTimeMinutes
            selectedProperty = recipe.property
            let ings = recipe.ingredients
            draftIngredients = ings.isEmpty ? [""] : ings
        } else {
            selectedProperty = defaultProperty
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let ingredients = draftIngredients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let target: Recipe
        if let existing = recipeToEdit {
            target = existing
        } else {
            let nextOrder = ((try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? [])
                .map(\.sortOrder).max() ?? 0
            let created = Recipe(sortOrder: nextOrder + 1)
            modelContext.insert(created)
            target = created
        }

        target.title = trimmedTitle
        target.ingredients = ingredients
        target.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        target.prepTimeMinutes = max(0, prepMinutes)
        target.placeLabel = placeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.property = selectedProperty

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to save recipe: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationStack {
        RecipesListView()
    }
    .modelContainer(
        for: [Recipe.self, Property.self],
        inMemory: true
    )
}
