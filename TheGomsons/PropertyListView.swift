//
//  PropertyListView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

struct PropertyListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openFamilyLanding) private var openFamilyLanding
    @Query(sort: \Property.name) private var allProperties: [Property]

    @State private var showAddProperty = false
    @State private var showArchived = false
    @State private var showRecipes = false
    @State private var showMaintenance = false

    private var activeProperties: [Property] {
        allProperties.filter { !$0.isArchived }
    }

    private var archivedProperties: [Property] {
        allProperties.filter(\.isArchived).sorted { $0.archivedAt > $1.archivedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeProperties.isEmpty && archivedProperties.isEmpty {
                    ContentUnavailableView(
                        String(localized: "properties.empty"),
                        systemImage: "building.2",
                        description: Text(String(localized: "properties.empty.detail"))
                    )
                } else {
                    List {
                        if !activeProperties.isEmpty {
                            ForEach(activeProperties) { property in
                                NavigationLink {
                                    PropertyDetailView(property: property)
                                } label: {
                                    PropertyRowView(property: property)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        archiveProperty(property)
                                    } label: {
                                        Label(String(localized: "property.archive"), systemImage: "archivebox")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }

                        if !archivedProperties.isEmpty {
                            Section {
                                DisclosureGroup(isExpanded: $showArchived) {
                                    ForEach(archivedProperties) { property in
                                        HStack {
                                            PropertyRowView(property: property)
                                                .opacity(0.6)
                                            Spacer()
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                modelContext.delete(property)
                                            } label: {
                                                Label(String(localized: "common.delete"), systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                            Button {
                                                restoreProperty(property)
                                            } label: {
                                                Label(String(localized: "property.restore"), systemImage: "arrow.uturn.backward")
                                            }
                                            .tint(.green)
                                        }
                                    }
                                } label: {
                                    Label(
                                        String(format: String(localized: "property.archived"), locale: .current, archivedProperties.count),
                                        systemImage: "archivebox"
                                    )
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "properties.title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showMaintenance = true
                    } label: {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(String(localized: "maintenance.log_title"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRecipes = true
                    } label: {
                        Image(systemName: "frying.pan.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(String(localized: "recipe.box_title"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddProperty = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(String(localized: "stash.add_property"))
                }
            }
            .navigationDestination(isPresented: $showRecipes) {
                RecipesListView()
            }
            .navigationDestination(isPresented: $showMaintenance) {
                MaintenanceLogListView()
            }
            .sheet(isPresented: $showAddProperty) {
                AddPropertySheet()
            }
        }
    }

    private func archiveProperty(_ property: Property) {
        withAnimation {
            property.isArchived = true
            property.archivedAt = Date()
        }
        persistArchiveChange("archive")
    }

    private func restoreProperty(_ property: Property) {
        withAnimation {
            property.isArchived = false
            property.archivedAt = .distantPast
        }
        persistArchiveChange("restore")
    }

    private func persistArchiveChange(_ label: String) {
        do {
            try modelContext.save()
        } catch {
            print("[TheGomsons] Property \(label) save failed: \(error.localizedDescription)")
        }
    }
}

private struct PropertyRowView: View {
    let property: Property

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            propertyThumbnail
            propertyDetails
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var propertyThumbnail: some View {
        if let data = property.coverImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.blue.opacity(0.12))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "building.2.fill")
                        .font(.title3)
                        .foregroundStyle(.blue.opacity(0.5))
                }
        }
    }

    private var propertyDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(property.name.isEmpty ? String(localized: "property.unnamed") : property.name)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(property.propertyKind.displayTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.45), in: Capsule())
            }

            if !property.address.isEmpty {
                Text(property.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let facts = property.formattedBedBathArea {
                Label(facts, systemImage: "ruler")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }

            if property.yearBuilt > 0 {
                // Verbatim + String(year): avoid SwiftUI LocalizedStringKey formatting years as "1 982".
                Text(String(format: String(localized: "property.built"), locale: .current, property.yearBuilt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !property.insuranceCarrier.isEmpty {
                Label(property.insuranceCarrier, systemImage: "shield.checkered")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            HStack(alignment: .top, spacing: 12) {
                if let contact = property.primaryContactForDisplay {
                    if !contact.phone.isEmpty {
                        Label {
                            Text(contact.phone)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "phone.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                    } else if !contact.email.isEmpty {
                        Label {
                            Text(contact.email)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "envelope.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                    } else if !contact.name.isEmpty {
                        Label(contact.name, systemImage: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .labelStyle(.titleAndIcon)
                    }
                }

                if let emergency = property.firstEmergencyNumber {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            if !emergency.label.isEmpty {
                                Text(emergency.label)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.tertiary)
                            }
                            Text(emergency.phoneNumber)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: "cross.case.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                }
            }
        }
    }
}

struct AddPropertySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var wifiNetwork = ""
    @State private var wifiPassword = ""
    @State private var emergencyNotes = ""
    @State private var propertyKind: PropertyKind = PropertyKind.other
    @State private var bedrooms = ""
    @State private var bathrooms = ""
    @State private var yearBuilt = ""
    @State private var insuranceCompany = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "property.section.property")) {
                    TextField(String(localized: "common.name"), text: $name)
                    TextField(String(localized: "property.field.address"), text: $address, axis: .vertical)
                        .lineLimit(3 ... 6)
                    Picker(String(localized: "property.type_picker"), selection: $propertyKind) {
                        ForEach(PropertyKind.pickerCases, id: \.self) { kind in
                            Text(kind.displayTitle).tag(kind)
                        }
                    }
                }
                Section(String(localized: "property.key_info")) {
                    TextField(String(localized: "property.field.bedrooms"), text: $bedrooms)
                        .keyboardType(.numberPad)
                    TextField(String(localized: "property.field.bathrooms"), text: $bathrooms)
                        .keyboardType(.decimalPad)
                    TextField(String(localized: "property.field.year_built"), text: $yearBuilt)
                        .keyboardType(.numberPad)
                    TextField(String(localized: "property.field.insurance_company"), text: $insuranceCompany)
                }
                Section(String(localized: "property.wifi")) {
                    TextField(String(localized: "property.field.network"), text: $wifiNetwork)
                    SecureField(String(localized: "common.password"), text: $wifiPassword)
                }
                Section(String(localized: "property.emergency_notes")) {
                    TextField(String(localized: "property.emergency_field_prompt"), text: $emergencyNotes, axis: .vertical)
                        .lineLimit(4 ... 8)
                }
            }
            .navigationTitle(String(localized: "property.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add")) {
                        let yearDigits = String(yearBuilt.filter(\.isNumber).prefix(4))
                        let roomDigits = String(bedrooms.filter(\.isNumber))
                        let bathRaw = bathrooms.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
                        let property = Property(
                            name: name,
                            address: address,
                            wifiNetwork: wifiNetwork,
                            wifiPassword: wifiPassword,
                            emergencyNotes: emergencyNotes,
                            propertyKind: propertyKind,
                            bedrooms: Int(roomDigits) ?? 0,
                            bathrooms: Double(bathRaw) ?? 0,
                            livingAreaSqFt: 0,
                            yearBuilt: Int(yearDigits) ?? 0,
                            insuranceCarrier: insuranceCompany
                        )
                        modelContext.insert(property)
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            print("[TheGomsons] Failed to save new property: \(error.localizedDescription)")
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    PropertyListView()
        .modelContainer(
            for: [
                Property.self,
                PropertyContact.self,
                PropertyEmergencyLine.self,
                PropertyContractor.self,
                PropertyServiceProvider.self,
                InventoryItem.self,
            ],
            inMemory: true
        )
}
