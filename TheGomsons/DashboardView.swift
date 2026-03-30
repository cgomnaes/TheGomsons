//
//  DashboardView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.openFamilyLanding) private var openFamilyLanding

    @Query private var assets: [Asset]
    @Query private var inventoryItems: [InventoryItem]

    @State private var showFamilyShare = false

    private var totalAssetValue: Double {
        assets.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    summaryCard(
                        title: "Portfolio",
                        subtitle: "Total asset value",
                        accent: SimpsonsTheme.orange,
                        icon: "dollarsign.circle.fill",
                        value: Text(totalAssetValue, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    )

                    summaryCard(
                        title: "Inventory",
                        subtitle: "Items tracked across properties",
                        accent: SimpsonsTheme.pink,
                        icon: "archivebox.fill",
                        value: Text("\(inventoryItems.count)")
                            .font(.largeTitle.weight(.semibold))
                            .monospacedDigit()
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFamilyShare = true
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .symbolRenderingMode(.multicolor)
                    }
                    .accessibilityLabel("Invite family to shared iCloud data")
                }
            }
            .fullScreenCover(isPresented: $showFamilyShare) {
                FamilyShareActivityRepresentable(onDismiss: { showFamilyShare = false })
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func summaryCard(title: String, subtitle: String, accent: Color, icon: String, value: Text) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                value
                    .font(.title.weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.2), lineWidth: 1.5)
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Asset.self, InventoryItem.self], inMemory: true)
}
