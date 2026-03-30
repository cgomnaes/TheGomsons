//
//  PropertyListView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI

struct PropertyListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openFamilyLanding) private var openFamilyLanding
    @Query(sort: \Property.name) private var properties: [Property]

    @State private var showAddProperty = false

    var body: some View {
        NavigationStack {
            Group {
                if properties.isEmpty {
                    ContentUnavailableView(
                        "No properties yet",
                        systemImage: "building.2",
                        description: Text("Add a home or vacation place—track key facts, contacts, emergency numbers, Wi‑Fi, and on-site inventory.")
                    )
                } else {
                    List {
                        ForEach(properties) { property in
                            NavigationLink {
                                PropertyDetailView(property: property)
                            } label: {
                                PropertyRowView(property: property)
                            }
                        }
                        .onDelete(perform: deleteProperties)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Properties")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddProperty = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Add property")
                }
            }
            .sheet(isPresented: $showAddProperty) {
                AddPropertySheet()
            }
        }
    }

    private func deleteProperties(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(properties[index])
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
                Text(property.name.isEmpty ? "Unnamed property" : property.name)
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

            if let facts = property.formattedBedBathSqft {
                Label(facts, systemImage: "ruler")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }

            if property.yearBuilt > 0 {
                Text("Built \(property.yearBuilt)")
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
    @State private var sqft = ""
    @State private var yearBuilt = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Property") {
                    TextField("Name", text: $name)
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(3 ... 6)
                    Picker("Type", selection: $propertyKind) {
                        ForEach(PropertyKind.allCases, id: \.self) { kind in
                            Text(kind.displayTitle).tag(kind)
                        }
                    }
                }
                Section("Key facts (optional)") {
                    TextField("Bedrooms", text: $bedrooms)
                        .keyboardType(.numberPad)
                    TextField("Bathrooms", text: $bathrooms)
                        .keyboardType(.decimalPad)
                    TextField("Living area (sq ft)", text: $sqft)
                        .keyboardType(.numberPad)
                    TextField("Year built", text: $yearBuilt)
                        .keyboardType(.numberPad)
                }
                Section("Wi‑Fi") {
                    TextField("Network name", text: $wifiNetwork)
                    SecureField("Password", text: $wifiPassword)
                }
                Section("Safety") {
                    TextField("On-site emergency notes", text: $emergencyNotes, axis: .vertical)
                        .lineLimit(4 ... 8)
                }
            }
            .navigationTitle("New property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let property = Property(
                            name: name,
                            address: address,
                            wifiNetwork: wifiNetwork,
                            wifiPassword: wifiPassword,
                            emergencyNotes: emergencyNotes,
                            propertyKind: propertyKind,
                            bedrooms: Int(bedrooms) ?? 0,
                            bathrooms: Double(bathrooms.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            livingAreaSqFt: Int(sqft) ?? 0,
                            yearBuilt: Int(yearBuilt) ?? 0
                        )
                        modelContext.insert(property)
                        dismiss()
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
