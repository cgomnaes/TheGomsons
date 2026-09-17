//
//  PropertyListView.swift
//  TheGomsons
//

import SwiftData
import SwiftUI
import UIKit

struct PropertyListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openFamilyLanding) private var openFamilyLanding
    @Query(sort: [SortDescriptor(\Property.sortOrder), SortDescriptor(\Property.name)])
    private var allProperties: [Property]
    @Query(sort: \HolidayTrip.startDate) private var allHolidayTrips: [HolidayTrip]

    @State private var showAddProperty = false
    @State private var showArchived = false
    @State private var showRecipes = false
    @State private var showMaintenance = false
    @State private var showImport = false
    @State private var editMode: EditMode = .inactive

    private var activeProperties: [Property] {
        allProperties
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var archivedProperties: [Property] {
        allProperties.filter(\.isArchived).sorted { $0.archivedAt > $1.archivedAt }
    }

    private var upcomingHolidayTrips: [HolidayTrip] {
        allHolidayTrips.filter { !$0.isPastTrip }
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
                                    PropertyCardView(
                                        property: property,
                                        upcomingTrips: upcomingHolidayTrips
                                    )
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        archiveProperty(property)
                                    } label: {
                                        Label(String(localized: "property.archive"), systemImage: "archivebox")
                                    }
                                    .tint(.orange)
                                }
                            }
                            .onMove(perform: moveActiveProperties)
                        }

                        if !archivedProperties.isEmpty {
                            Section {
                                DisclosureGroup(isExpanded: $showArchived) {
                                    ForEach(archivedProperties) { property in
                                        NavigationLink {
                                            PropertyDetailView(property: property)
                                        } label: {
                                            PropertyCardView(property: property, compact: true)
                                                .opacity(0.72)
                                        }
                                        .buttonStyle(.plain)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
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
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .environment(\.editMode, $editMode)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "properties.title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    homeButton { openFamilyLanding() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !activeProperties.isEmpty {
                        EditButton()
                    }
                    Button {
                        showMaintenance = true
                    } label: {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(String(localized: "maintenance.log_title"))
                    .disabled(editMode.isEditing)
                    Button {
                        showRecipes = true
                    } label: {
                        Image(systemName: "frying.pan.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(String(localized: "recipe.box_title"))
                    .disabled(editMode.isEditing)
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(String(localized: "properties.import_title"))
                    .disabled(editMode.isEditing)
                    Button {
                        showAddProperty = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(String(localized: "stash.add_property"))
                    .disabled(editMode.isEditing)
                }
            }
            .navigationDestination(isPresented: $showRecipes) {
                RecipesListView()
            }
            .navigationDestination(isPresented: $showMaintenance) {
                MaintenanceLogListView()
            }
            .navigationDestination(isPresented: $showImport) {
                PropertiesImportView()
            }
            .sheet(isPresented: $showAddProperty) {
                AddPropertySheet()
            }
        }
    }

    /// Drag-reorder active properties; writes `sortOrder` so CloudKit keeps the order.
    private func moveActiveProperties(from source: IndexSet, to destination: Int) {
        var reordered = activeProperties
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, property) in reordered.enumerated() {
            property.sortOrder = index
        }
        do {
            try modelContext.save()
        } catch {
            print("[TheGomsons] Property reorder save failed: \(error.localizedDescription)")
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
            // Place restored properties at the end of the active list.
            property.sortOrder = (activeProperties.map(\.sortOrder).max() ?? -1) + 1
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

private struct PropertyCardView: View {
    let property: Property
    var upcomingTrips: [HolidayTrip] = []
    var compact: Bool = false

    private var coverHeight: CGFloat { compact ? 120 : 188 }

    private var displayName: String {
        property.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "property.unnamed")
            : property.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                coverImage
                    .frame(maxWidth: .infinity)
                    .frame(height: coverHeight)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: coverHeight)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(displayName)
                            .font(compact ? .headline.weight(.bold) : .title3.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        if property.isRented {
                            Text(String(localized: "property.tenure.rented"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(SimpsonsTheme.orange.opacity(0.9), in: Capsule())
                        }
                        Text(property.propertyKind.displayTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.22), in: Capsule())
                    }

                    if !property.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(property.address)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                    }
                }
                .padding(compact ? 12 : 16)
            }

            if !compact {
                cardMeta
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                PropertyCabinVisitsSection(
                    property: property,
                    upcomingTrips: upcomingTrips
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    @ViewBuilder
    private var coverImage: some View {
        if let data = property.coverImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [
                    Color(hue: 0.58, saturation: 0.42, brightness: 0.62),
                    Color(hue: 0.72, saturation: 0.38, brightness: 0.42),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "building.2.fill")
                    .font(.system(size: compact ? 32 : 44, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private var cardMeta: some View {
        let hasFacts = property.formattedBedBathArea != nil || property.yearBuilt > 0
        let hasContact = property.primaryContactForDisplay != nil || property.firstEmergencyNumber != nil
        let hasRentalBits = property.isRented && (
            !property.rentalCompanyName.isEmpty
                || !property.landlordOrOwnerName.isEmpty
                || !property.monthlyRent.isEmpty
        )
        if hasFacts || hasContact || hasRentalBits || !property.insuranceCarrier.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if property.isRented {
                    if !property.monthlyRent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(property.monthlyRent, systemImage: "banknote")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if !property.rentalCompanyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(property.rentalCompanyName, systemImage: "building.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if !property.landlordOrOwnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(property.landlordOrOwnerName, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let facts = property.formattedBedBathArea {
                    Label(facts, systemImage: "ruler")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }

                HStack(spacing: 12) {
                    if property.yearBuilt > 0 {
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
                }

                HStack(alignment: .top, spacing: 12) {
                    if let contact = property.primaryContactForDisplay {
                        if !contact.phone.isEmpty {
                            Label(contact.phone, systemImage: "phone.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if !contact.email.isEmpty {
                            Label(contact.email, systemImage: "envelope.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if !contact.name.isEmpty {
                            Label(contact.name, systemImage: "person.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
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
                    }
                }
            }
        }
    }
}

struct AddPropertySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Property.sortOrder) private var existingProperties: [Property]

    @State private var name = ""
    @State private var address = ""
    @State private var wifiNetwork = ""
    @State private var wifiPassword = ""
    @State private var emergencyNotes = ""
    @State private var propertyKind: PropertyKind = PropertyKind.other
    @State private var tenure: PropertyTenure = .owned
    @State private var bedrooms = ""
    @State private var bathrooms = ""
    @State private var livingAreaM2 = ""
    @State private var propertyRegisterURL = ""
    @State private var yearBuilt = ""
    @State private var insuranceCompany = ""
    @State private var landlordOrOwnerName = ""
    @State private var rentalCompanyName = ""
    @State private var rentalCompanyPhone = ""
    @State private var rentalCompanyEmail = ""
    @State private var depositAmount = ""
    @State private var monthlyRent = ""
    @State private var hasLeaseStart = false
    @State private var hasLeaseEnd = false
    @State private var leaseStartDate = Date()
    @State private var leaseEndDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var rentalContractReference = ""
    @State private var rentalContractNotes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "common.name"), text: $name)
                    TextField(String(localized: "property.field.address"), text: $address, axis: .vertical)
                        .lineLimit(3 ... 6)
                    Picker(String(localized: "property.type_picker"), selection: $propertyKind) {
                        ForEach(PropertyKind.pickerCases, id: \.self) { kind in
                            Text(kind.displayTitle).tag(kind)
                        }
                    }
                    Picker(String(localized: "property.tenure"), selection: $tenure) {
                        ForEach(PropertyTenure.allCases, id: \.self) { value in
                            Text(value.displayTitle).tag(value)
                        }
                    }
                    TextField(String(localized: "property.living_area"), text: $livingAreaM2)
                        .keyboardType(.numberPad)
                    TextField(
                        String(localized: "property.register_url_placeholder"),
                        text: $propertyRegisterURL,
                        axis: .vertical
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .lineLimit(2 ... 4)
                } header: {
                    Text(String(localized: "property.section.property"))
                } footer: {
                    Text(String(localized: "property.register_url_footer"))
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
                if tenure == .rented {
                    Section {
                        TextField(String(localized: "property.rental.landlord"), text: $landlordOrOwnerName)
                        TextField(String(localized: "property.rental.company"), text: $rentalCompanyName)
                        TextField(String(localized: "property.rental.company_phone"), text: $rentalCompanyPhone)
                            .keyboardType(.phonePad)
                        TextField(String(localized: "property.rental.company_email"), text: $rentalCompanyEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        TextField(String(localized: "property.rental.deposit"), text: $depositAmount)
                        TextField(String(localized: "property.rental.monthly_rent"), text: $monthlyRent)
                        Toggle(String(localized: "property.rental.lease_start"), isOn: $hasLeaseStart)
                        if hasLeaseStart {
                            DatePicker(
                                String(localized: "property.rental.lease_start"),
                                selection: $leaseStartDate,
                                displayedComponents: .date
                            )
                        }
                        Toggle(String(localized: "property.rental.lease_end"), isOn: $hasLeaseEnd)
                        if hasLeaseEnd {
                            DatePicker(
                                String(localized: "property.rental.lease_end"),
                                selection: $leaseEndDate,
                                displayedComponents: .date
                            )
                        }
                        TextField(String(localized: "property.rental.contract_ref"), text: $rentalContractReference)
                        TextField(
                            String(localized: "property.rental.contract_notes"),
                            text: $rentalContractNotes,
                            axis: .vertical
                        )
                        .lineLimit(3 ... 8)
                    } header: {
                        Text(String(localized: "property.rental.section"))
                    } footer: {
                        Text(String(localized: "property.rental.add_footer"))
                    }
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
                        let nextOrder = (existingProperties.map(\.sortOrder).max() ?? -1) + 1
                        let property = Property(
                            name: name,
                            address: address,
                            wifiNetwork: wifiNetwork,
                            wifiPassword: wifiPassword,
                            emergencyNotes: emergencyNotes,
                            propertyKind: propertyKind,
                            tenure: tenure,
                            bedrooms: Int(roomDigits) ?? 0,
                            bathrooms: Double(bathRaw) ?? 0,
                            livingAreaSqFt: Int(livingAreaM2.filter(\.isNumber)) ?? 0,
                            yearBuilt: Int(yearDigits) ?? 0,
                            propertyRegisterURL: propertyRegisterURL.trimmingCharacters(in: .whitespacesAndNewlines),
                            insuranceCarrier: insuranceCompany,
                            landlordOrOwnerName: tenure == .rented ? landlordOrOwnerName : "",
                            rentalCompanyName: tenure == .rented ? rentalCompanyName : "",
                            rentalCompanyPhone: tenure == .rented ? rentalCompanyPhone : "",
                            rentalCompanyEmail: tenure == .rented ? rentalCompanyEmail : "",
                            depositAmount: tenure == .rented ? depositAmount : "",
                            monthlyRent: tenure == .rented ? monthlyRent : "",
                            leaseStartDate: tenure == .rented && hasLeaseStart
                                ? Calendar.current.startOfDay(for: leaseStartDate) : nil,
                            leaseEndDate: tenure == .rented && hasLeaseEnd
                                ? Calendar.current.startOfDay(for: leaseEndDate) : nil,
                            rentalContractReference: tenure == .rented ? rentalContractReference : "",
                            rentalContractNotes: tenure == .rented ? rentalContractNotes : "",
                            sortOrder: nextOrder
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
