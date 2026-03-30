//
//  InventoryListView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

struct InventoryListView: View {
    @Environment(\.openFamilyLanding) private var openFamilyLanding
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]

    @State private var showAddItem = false

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No inventory",
                        systemImage: "archivebox",
                        description: Text("Add an item and use a photo to get on-device suggestions for name, category, and prices.")
                    )
                } else {
                    List {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.name.isEmpty ? "Untitled item" : item.name)
                                    .font(.headline)
                                HStack {
                                    Text(item.category.displayTitle)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.quaternary.opacity(0.5), in: Capsule())
                                    if let propertyName = item.property?.name, !propertyName.isEmpty {
                                        Spacer(minLength: 8)
                                        Label(propertyName, systemImage: "building.2.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .labelStyle(.titleAndIcon)
                                    }
                                }
                                if item.currentRetailPrice > 0 || item.estimatedValue > 0 {
                                    HStack(spacing: 10) {
                                        if item.currentRetailPrice > 0 {
                                            Text("List \(item.currentRetailPrice, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if item.estimatedValue > 0 {
                                            Text("Est. \(item.estimatedValue, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Inventory")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddItem = true
                    } label: {
                        Label("Add with photo", systemImage: "camera.fill.badge.ellipsis")
                    }
                }
            }
            .sheet(isPresented: $showAddItem) {
                AddInventoryItemView()
            }
        }
    }
}

#Preview {
    InventoryListView()
        .modelContainer(for: [InventoryItem.self, Property.self], inMemory: true)
}
