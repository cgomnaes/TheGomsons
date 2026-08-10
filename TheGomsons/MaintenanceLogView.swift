//
//  MaintenanceLogView.swift
//  TheGomsons
//
//  Shared maintenance log for homes/cabins (service history + next-due).
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MaintenanceLogListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\PropertyMaintenanceEntry.nextDueAt), SortDescriptor(\PropertyMaintenanceEntry.performedAt, order: .reverse)])
    private var allEntries: [PropertyMaintenanceEntry]

    var filterProperty: Property? = nil

    @State private var showEditor = false
    @State private var entryToEdit: PropertyMaintenanceEntry?
    @State private var searchText = ""
    @State private var showOverdueOnly = false

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleEntries: [PropertyMaintenanceEntry] {
        var list = allEntries
        if let filterProperty {
            let id = filterProperty.persistentModelID
            list = list.filter { $0.property?.persistentModelID == id }
        }
        if showOverdueOnly {
            list = list.filter { ($0.daysUntilDue() ?? 1) < 0 }
        }
        let q = trimmedSearch
        guard !q.isEmpty else { return PropertyMaintenanceEntry.sorted(list) }
        return PropertyMaintenanceEntry.sorted(list.filter { entry in
            entry.title.localizedCaseInsensitiveContains(q)
                || entry.category.displayTitle.localizedCaseInsensitiveContains(q)
                || entry.trimmedPerformedBy.localizedCaseInsensitiveContains(q)
                || entry.trimmedNotes.localizedCaseInsensitiveContains(q)
                || (entry.property?.name.localizedCaseInsensitiveContains(q) ?? false)
        })
    }

    var body: some View {
        Group {
            if allEntries.isEmpty && filterProperty == nil {
                emptyAll
            } else if visibleEntries.isEmpty {
                emptyFiltered
            } else {
                List {
                    ForEach(visibleEntries) { entry in
                        Button {
                            entryToEdit = entry
                        } label: {
                            MaintenanceEntryRow(entry: entry, showsProperty: filterProperty == nil)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteEntry(entry)
                            } label: {
                                Label(String(localized: "common.delete"), systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(
            filterProperty.map { _ in String(localized: "maintenance.place_title") }
                ?? String(localized: "maintenance.log_title")
        )
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: String(localized: "maintenance.search_prompt"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $showOverdueOnly) {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .toggleStyle(.button)
                .accessibilityLabel(String(localized: "maintenance.filter_overdue"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(String(localized: "maintenance.add"))
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                MaintenanceEntryEditorView(defaultProperty: filterProperty)
            }
        }
        .sheet(item: $entryToEdit) { entry in
            NavigationStack {
                MaintenanceEntryEditorView(entryToEdit: entry)
            }
        }
    }

    private var emptyAll: some View {
        ContentUnavailableView(
            String(localized: "maintenance.empty_title"),
            systemImage: "wrench.and.screwdriver.fill",
            description: Text(String(localized: "maintenance.empty_detail"))
        )
    }

    private var emptyFiltered: some View {
        ContentUnavailableView(
            showOverdueOnly
                ? String(localized: "maintenance.no_overdue")
                : (trimmedSearch.isEmpty
                    ? String(localized: "maintenance.empty_place_title")
                    : String(localized: "maintenance.no_matches")),
            systemImage: showOverdueOnly ? "checkmark.seal" : (trimmedSearch.isEmpty ? "wrench.and.screwdriver" : "magnifyingglass"),
            description: Text(
                showOverdueOnly
                    ? String(localized: "maintenance.no_overdue_detail")
                    : (trimmedSearch.isEmpty
                        ? String(localized: "maintenance.empty_place_detail")
                        : String(format: String(localized: "maintenance.search_empty"), locale: .current, trimmedSearch))
            )
        )
    }

    private func deleteEntry(_ entry: PropertyMaintenanceEntry) {
        modelContext.delete(entry)
        do {
            try modelContext.save()
        } catch {
            print("[TheGomsons] Failed to delete maintenance entry: \(error.localizedDescription)")
        }
    }
}

// MARK: - Row

private struct MaintenanceEntryRow: View {
    let entry: PropertyMaintenanceEntry
    var showsProperty: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.category.systemImage)
                .font(.title3)
                .foregroundStyle(SimpsonsTheme.brown)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title.isEmpty ? String(localized: "maintenance.untitled") : entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(entry.category.displayTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if showsProperty, let name = entry.property?.name, !name.isEmpty {
                        Label(name, systemImage: "building.2")
                            .lineLimit(1)
                    }
                    if entry.performedAt > Date(timeIntervalSince1970: 0) {
                        Text(entry.performedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let days = entry.daysUntilDue() {
                    Text(dueText(days: days))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(days < 0 ? .red : (days <= 30 ? SimpsonsTheme.orange : .secondary))
                }
            }
            Spacer(minLength: 0)
            if entry.photoData != nil {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func dueText(days: Int) -> String {
        if days < 0 {
            return String(format: String(localized: "maintenance.overdue_days"), locale: .current, abs(days))
        }
        if days == 0 {
            return String(localized: "maintenance.due_today")
        }
        if days == 1 {
            return String(localized: "maintenance.due_tomorrow")
        }
        return String(format: String(localized: "maintenance.due_in_days"), locale: .current, days)
    }
}

// MARK: - Editor

struct MaintenanceEntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Property.name) private var properties: [Property]

    var entryToEdit: PropertyMaintenanceEntry? = nil
    var defaultProperty: Property? = nil

    @State private var title = ""
    @State private var category: MaintenanceCategory = .other
    @State private var performedAt = Date()
    @State private var hasNextDue = false
    @State private var nextDueAt = Calendar.current.date(byAdding: .month, value: 12, to: Date()) ?? Date()
    @State private var performedBy = ""
    @State private var costAmount = 0.0
    @State private var notes = ""
    @State private var selectedProperty: Property?
    @State private var pickedImage: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var confirmDelete = false

    private var isNew: Bool { entryToEdit == nil }

    private var activeProperties: [Property] {
        properties.filter { !$0.isArchived }
    }

    var body: some View {
        Form {
            basicsSection
            placeSection
            scheduleSection
            notesSection
            photoSection
            if !isNew {
                deleteSection
            }
        }
        .navigationTitle(isNew ? String(localized: "maintenance.new") : String(localized: "maintenance.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { editorToolbar }
        .onAppear(perform: load)
        .onChange(of: pickerItem) { _, newItem in
            Task { await loadPhoto(from: newItem) }
        }
        .confirmationDialog(
            String(localized: "maintenance.delete_confirm"),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive, action: deleteAndDismiss)
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedProperty != nil
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "common.cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(String(localized: "common.save")) { save() }
                .fontWeight(.semibold)
                .disabled(!canSave)
        }
    }

    @ViewBuilder
    private var basicsSection: some View {
        Section {
            TextField(String(localized: "maintenance.title_field"), text: $title)
            Picker(String(localized: "common.category"), selection: $category) {
                ForEach(MaintenanceCategory.allCases, id: \.self) { cat in
                    Label(cat.displayTitle, systemImage: cat.systemImage).tag(cat)
                }
            }
            DatePicker(
                String(localized: "maintenance.performed_at"),
                selection: $performedAt,
                displayedComponents: .date
            )
            TextField(String(localized: "maintenance.performed_by"), text: $performedBy)
            costRow
        }
    }

    private var costRow: some View {
        HStack {
            Text(String(localized: "maintenance.cost"))
            Spacer()
            TextField("0", value: $costAmount, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }

    @ViewBuilder
    private var placeSection: some View {
        Section {
            Picker(String(localized: "maintenance.property"), selection: $selectedProperty) {
                Text(String(localized: "maintenance.property_required"))
                    .tag(nil as Property?)
                ForEach(activeProperties) { property in
                    Text(property.name.isEmpty ? String(localized: "property.unnamed") : property.name)
                        .tag(property as Property?)
                }
            }
        } header: {
            Text(String(localized: "maintenance.place_section"))
        } footer: {
            Text(String(localized: "maintenance.place_footer"))
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        Section {
            Toggle(String(localized: "maintenance.has_next_due"), isOn: $hasNextDue)
            if hasNextDue {
                DatePicker(
                    String(localized: "maintenance.next_due"),
                    selection: $nextDueAt,
                    displayedComponents: .date
                )
            }
        } header: {
            Text(String(localized: "maintenance.schedule_section"))
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        Section(String(localized: "common.notes")) {
            TextField(String(localized: "maintenance.notes_placeholder"), text: $notes, axis: .vertical)
                .lineLimit(3 ... 10)
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        Section(String(localized: "maintenance.photo")) {
            if let pickedImage {
                Image(uiImage: pickedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button(role: .destructive) {
                    self.pickedImage = nil
                    pickerItem = nil
                } label: {
                    Text(String(localized: "maintenance.remove_photo"))
                }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(photoPickerLabel, systemImage: "camera.fill")
            }
        }
    }

    private var photoPickerLabel: String {
        pickedImage == nil
            ? String(localized: "maintenance.add_photo")
            : String(localized: "maintenance.change_photo")
    }

    @ViewBuilder
    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Text(String(localized: "maintenance.delete"))
            }
        }
    }

    private func deleteAndDismiss() {
        if let entry = entryToEdit {
            modelContext.delete(entry)
            try? modelContext.save()
        }
        dismiss()
    }

    private func load() {
        if let entry = entryToEdit {
            title = entry.title
            category = entry.category
            performedAt = entry.performedAt > Date(timeIntervalSince1970: 0) ? entry.performedAt : Date()
            hasNextDue = entry.hasNextDue
            nextDueAt = entry.hasNextDue
                ? entry.nextDueAt
                : (Calendar.current.date(byAdding: .month, value: 12, to: Date()) ?? Date())
            performedBy = entry.performedBy
            costAmount = entry.costAmount
            notes = entry.notes
            selectedProperty = entry.property
            pickedImage = entry.photoData.flatMap { UIImage(data: $0) }
        } else {
            selectedProperty = defaultProperty
            performedAt = Date()
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        await MainActor.run {
            pickedImage = image
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, let property = selectedProperty else { return }

        let jpeg = pickedImage.flatMap { $0.jpegData(compressionQuality: 0.85) }

        let target: PropertyMaintenanceEntry
        if let existing = entryToEdit {
            target = existing
        } else {
            let nextOrder = ((try? modelContext.fetch(FetchDescriptor<PropertyMaintenanceEntry>())) ?? [])
                .map(\.sortOrder).max() ?? 0
            let created = PropertyMaintenanceEntry(sortOrder: nextOrder + 1)
            modelContext.insert(created)
            target = created
        }

        target.title = trimmedTitle
        target.category = category
        target.performedAt = Calendar.current.startOfDay(for: performedAt)
        target.nextDueAt = hasNextDue
            ? Calendar.current.startOfDay(for: nextDueAt)
            : Date(timeIntervalSince1970: 0)
        target.performedBy = performedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        target.costAmount = max(0, costAmount)
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.photoData = jpeg
        target.property = property

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to save maintenance entry: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationStack {
        MaintenanceLogListView()
    }
    .modelContainer(for: [PropertyMaintenanceEntry.self, Property.self], inMemory: true)
}
