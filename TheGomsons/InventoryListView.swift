//
//  InventoryListView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI
import UIKit

struct InventoryListView: View {
    @Environment(\.openFamilyLanding) private var openFamilyLanding
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]

    @State private var showAddItem = false
    @State private var itemToEdit: InventoryItem?
    @State private var searchText = ""

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredItems: [InventoryItem] {
        let q = trimmedSearch
        guard !q.isEmpty else { return Array(items) }
        return items.filter { Self.matchesSearch($0, query: q) }
    }

    private var sections: [(section: InventoryStashSection, items: [InventoryItem])] {
        InventoryItem.groupedByStashSection(filteredItems)
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        String(localized: "stash.empty"),
                        systemImage: "archivebox.fill",
                        description: Text(String(localized: "stash.empty.detail"))
                    )
                } else if sections.isEmpty {
                    ContentUnavailableView(
                        String(localized: "stash.no_matches"),
                        systemImage: "magnifyingglass",
                        description: Text(String(format: String(localized: "stash.search_empty"), locale: .current, trimmedSearch))
                    )
                } else {
                    List {
                        ForEach(sections, id: \.section) { bucket in
                            Section {
                                ForEach(bucket.items) { item in
                                    Button {
                                        itemToEdit = item
                                    } label: {
                                        BelongingsItemRow(item: item, showsProperty: true)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deleteItem(item)
                                        } label: {
                                            Label(String(localized: "common.delete"), systemImage: "trash")
                                        }
                                    }
                                }
                                .onDelete { offsets in
                                    deleteItems(at: offsets, in: bucket.items)
                                }
                            } header: {
                                Text(bucket.section.title)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listRowSpacing(2)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "stash.title"))
            .searchable(text: $searchText, prompt: String(localized: "stash.search_prompt"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "inventory.add_title"))
                }
            }
            .sheet(isPresented: $showAddItem) {
                NavigationStack {
                    AddInventoryItemView()
                }
            }
            .sheet(item: $itemToEdit) { item in
                NavigationStack {
                    AddInventoryItemView(itemToEdit: item)
                }
            }
        }
    }

    private func deleteItems(at offsets: IndexSet, in sectionItems: [InventoryItem]) {
        for index in offsets {
            guard sectionItems.indices.contains(index) else { continue }
            deleteItem(sectionItems[index])
        }
    }

    private func deleteItem(_ item: InventoryItem) {
        modelContext.delete(item)
        do {
            try modelContext.save()
        } catch {
            print("[TheGomsons] Failed to delete belonging: \(error.localizedDescription)")
        }
    }

    private static func matchesSearch(_ item: InventoryItem, query: String) -> Bool {
        let fields: [String] = [
            item.name,
            item.trimmedNotes,
            item.trimmedPurchasePlace,
            item.trimmedLocationDetail,
            item.trimmedProductURL,
            item.insuranceNotes,
            item.category.displayTitle,
            item.category.stashSection.title,
            item.property?.name ?? "",
            String(localized: "inventory.family_wide"),
        ]
        return fields.contains { $0.localizedStandardContains(query) }
    }
}

/// Compact row for Belongings list and property detail.
struct BelongingsItemRow: View {
    let item: InventoryItem
    var showsProperty: Bool = true

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var metaLine: String {
        var parts: [String] = [item.category.displayTitle]
        if showsProperty {
            if let name = item.property?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                parts.append(name)
            } else {
                parts.append(String(localized: "inventory.family_wide"))
            }
        }
        if !item.trimmedLocationDetail.isEmpty {
            parts.append(item.trimmedLocationDetail)
        }
        return parts.joined(separator: " · ")
    }

    private var valueText: String? {
        if item.estimatedValue > 0 {
            return item.estimatedValue.formatted(.currency(code: currencyCode))
        }
        if item.currentRetailPrice > 0 {
            return item.currentRetailPrice.formatted(.currency(code: currencyCode))
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            InventoryItemPhotoThumbnail(photoData: item.photoData, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.name.isEmpty ? String(localized: "inventory.untitled_item") : item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if item.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel(String(localized: "inventory.attachments_a11y"))
                    }
                }
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let valueText {
                Text(valueText)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Leading thumbnail for Belongings rows (placeholder when no photo).
struct InventoryItemPhotoThumbnail: View {
    var photoData: Data?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let data = photoData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: "archivebox")
                        .font(.system(size: size * 0.36, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(String(localized: "stash.photo_a11y"))
    }
}

#Preview {
    InventoryListView()
        .modelContainer(for: [InventoryItem.self, InventoryItemLink.self, InventoryItemDocument.self, Property.self], inMemory: true)
}
