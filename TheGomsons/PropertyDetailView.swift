//
//  PropertyDetailView.swift
//  TheGomsons
//

import PhotosUI
import SwiftData
import SwiftUI

struct PropertyDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var property: Property
    @Query(sort: \HolidayTrip.startDate) private var allHolidayTrips: [HolidayTrip]

    @State private var showAddContact = false
    @State private var showAddEmergencyLine = false
    @State private var showAddContractor = false
    @State private var showAddServiceProvider = false
    @State private var showAddInventoryItem = false
    @State private var inventoryItemToEdit: InventoryItem?
    @State private var showAddRecipe = false
    @State private var recipeToEdit: Recipe?
    @State private var showAddMaintenance = false
    @State private var maintenanceToEdit: PropertyMaintenanceEntry?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showWifiPassword = false
    @State private var showAlarmCode = false
    @State private var showGateCode = false

    private var sortedContacts: [PropertyContact] {
        (property.contacts ?? []).sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary && !$1.isPrimary }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name < $1.name
        }
    }

    private var sortedEmergencyLines: [PropertyEmergencyLine] {
        (property.emergencyLines ?? []).sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.label < $1.label
        }
    }

    private var upcomingHolidayTrips: [HolidayTrip] {
        allHolidayTrips.filter { !$0.isPastTrip }
    }

    private var contractorsByTrade: [(trade: ContractorTrade, items: [PropertyContractor])] {
        let all = (property.contractors ?? []).sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name < $1.name
        }
        let grouped = Dictionary(grouping: all, by: \.trade)
        return ContractorTrade.allCases.compactMap { trade in
            guard let items = grouped[trade], !items.isEmpty else { return nil }
            return (trade, items)
        }
    }

    private var providersByKind: [(kind: ServiceProviderKind, items: [PropertyServiceProvider])] {
        let all = (property.serviceProviders ?? []).sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.companyName < $1.companyName
        }
        let grouped = Dictionary(grouping: all, by: \.kind)
        return ServiceProviderKind.allCases.compactMap { kind in
            guard let items = grouped[kind], !items.isEmpty else { return nil }
            return (kind, items)
        }
    }

    @ViewBuilder
    private var propertyCoverImage: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = property.coverImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(hue: 0.58, saturation: 0.42, brightness: 0.62),
                            Color(hue: 0.72, saturation: 0.38, brightness: 0.42),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.55))
                        Text(String(localized: "property.add_photo"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            }

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Image(systemName: property.coverImageData == nil ? "camera.fill" : "pencil.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(12)
        }
        .contextMenu {
            if property.coverImageData != nil {
                Button(role: .destructive) {
                    withAnimation { property.coverImageData = nil }
                } label: {
                    Label(String(localized: "property.remove_photo"), systemImage: "trash")
                }
            }
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                if let original = UIImage(data: data) {
                    let maxDimension: CGFloat = 1200
                    let scale = min(maxDimension / original.size.width, maxDimension / original.size.height, 1.0)
                    let newSize = CGSize(width: original.size.width * scale, height: original.size.height * scale)
                    let renderer = UIGraphicsImageRenderer(size: newSize)
                    let compressed = renderer.jpegData(withCompressionQuality: 0.8) { ctx in
                        original.draw(in: CGRect(origin: .zero, size: newSize))
                    }
                    property.coverImageData = compressed
                } else {
                    property.coverImageData = data
                }
            }
        }
    }

    var body: some View {
        List {
            Section {
                propertyCoverImage
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if property.isVacationHome {
                Section {
                    PropertyCabinVisitsSection(
                        property: property,
                        upcomingTrips: upcomingHolidayTrips,
                        showsHeader: false
                    )
                    .padding(.vertical, 4)
                } header: {
                    Text(String(localized: "property.cabin.next_visits"))
                } footer: {
                    Text(String(localized: "property.cabin.next_visits.footer"))
                }
            }

            Section {
                TextField(String(localized: "property.field.name"), text: $property.name)
                    .font(.title2.weight(.bold))
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                TextField(String(localized: "property.field.address"), text: $property.address, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textContentType(.fullStreetAddress)
                    .lineLimit(1...4)
            } header: {
                Text(String(localized: "property.rename_section"))
            } footer: {
                Text(String(localized: "property.name_edit_footer"))
            }

            Section {
                Picker(String(localized: "property.type_picker"), selection: $property.propertyKind) {
                    ForEach(PropertyKind.pickerCases, id: \.self) { kind in
                        Text(kind.displayTitle).tag(kind)
                    }
                }
                Picker(String(localized: "property.tenure"), selection: $property.tenureRaw) {
                    ForEach(PropertyTenure.allCases, id: \.self) { tenure in
                        Text(tenure.displayTitle).tag(tenure.rawValue)
                    }
                }
                HStack {
                    Text(String(localized: "property.living_area"))
                    Spacer()
                    IntZeroAsEmptyField(placeholder: String(localized: "property.number_dash"), value: $property.livingAreaSqFt)
                        .frame(maxWidth: 100)
                }
                VStack(alignment: .leading, spacing: 8) {
                    TextField(
                        String(localized: "property.register_url_placeholder"),
                        text: $property.propertyRegisterURL,
                        axis: .vertical
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .lineLimit(2 ... 4)
                    if let registerURL = Self.sanitizedURL(from: property.propertyRegisterURL) {
                        Link(destination: registerURL) {
                            Label(String(localized: "property.open_register"), systemImage: "safari")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                HStack {
                    Text(String(localized: "property.field.bedrooms"))
                    Spacer()
                    IntZeroAsEmptyField(placeholder: String(localized: "property.number_dash"), value: $property.bedrooms)
                        .frame(maxWidth: 80)
                }
                HStack {
                    Text(String(localized: "property.field.bathrooms"))
                    Spacer()
                    DoubleZeroAsEmptyField(placeholder: String(localized: "property.number_dash"), value: $property.bathrooms)
                        .frame(maxWidth: 80)
                }
                HStack {
                    Text(String(localized: "property.field.year_built"))
                    Spacer()
                    IntZeroAsEmptyField(placeholder: String(localized: "property.number_dash"), value: $property.yearBuilt, maxDigits: 4)
                        .frame(maxWidth: 100)
                }
                LabeledContent(String(localized: "property.field.insurance_company")) {
                    TextField(String(localized: "common.optional"), text: $property.insuranceCarrier)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text(String(localized: "property.key_info"))
            } footer: {
                Text(String(localized: "property.register_url_footer"))
            }

            if property.isRented {
                rentalSection
            }

            Section {
                LabeledContent(String(localized: "property.field.network")) {
                    TextField(String(localized: "property.ssid"), text: $property.wifiNetwork)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                }
                LabeledContent(String(localized: "common.password")) {
                    RevealableSecureField(
                        placeholder: String(localized: "common.password"),
                        text: $property.wifiPassword,
                        isRevealed: $showWifiPassword
                    )
                }
            } header: {
                Text(String(localized: "property.wifi"))
            }

            Section {
                if sortedEmergencyLines.isEmpty {
                    Text(String(localized: "property.emergency.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedEmergencyLines) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.label.isEmpty ? String(localized: "property.unlabeled") : line.label)
                                .font(.headline)
                            if !line.phoneNumber.isEmpty {
                                if let url = TelephoneURL.url(for: line.phoneNumber) {
                                    Link(destination: url) {
                                        Label(line.phoneNumber, systemImage: "phone.fill")
                                            .font(.subheadline.monospaced())
                                    }
                                } else {
                                    Text(line.phoneNumber)
                                        .font(.subheadline.monospaced())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                modelContext.delete(line)
                            } label: {
                                Label(String(localized: "common.delete"), systemImage: "trash")
                            }
                        }
                    }
                }
                Button {
                    showAddEmergencyLine = true
                } label: {
                    Label(String(localized: "property.add_number"), systemImage: "cross.case.fill")
                }
                TextField(String(localized: "property.emergency_field_prompt"), text: $property.emergencyNotes, axis: .vertical)
                    .lineLimit(4 ... 12)
            } header: {
                Text(String(localized: "property.emergency_contacts"))
            } footer: {
                Text(String(localized: "property.emergency_footer"))
                    .font(.caption)
            }

            Section {
                if sortedContacts.isEmpty {
                    Text(property.isRented
                          ? String(localized: "property.contacts.empty_rented")
                          : String(localized: "property.contact_hint"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedContacts) { contact in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(contact.name.isEmpty ? String(localized: "property.contact.unnamed") : contact.name)
                                    .font(.headline)
                                if contact.isPrimary {
                                    Text(String(localized: "property.primary"))
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.15), in: Capsule())
                                }
                            }
                            if !contact.role.isEmpty {
                                Text(contact.role)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !contact.phone.isEmpty {
                                if let url = TelephoneURL.url(for: contact.phone) {
                                    Link(destination: url) {
                                        Label(contact.phone, systemImage: "phone.fill")
                                            .font(.subheadline)
                                    }
                                } else {
                                    Text(contact.phone)
                                        .font(.subheadline.monospaced())
                                }
                            }
                            if !contact.email.isEmpty, let mailURL = URL(string: "mailto:\(contact.email)") {
                                Link(destination: mailURL) {
                                    Label(contact.email, systemImage: "envelope.fill")
                                        .font(.caption)
                                }
                            }
                            if !contact.notes.isEmpty {
                                Text(contact.notes)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                modelContext.delete(contact)
                            } label: {
                                Label(String(localized: "common.delete"), systemImage: "trash")
                            }
                        }
                    }
                }
                Button {
                    showAddContact = true
                } label: {
                    Label(String(localized: "property.add_contact"), systemImage: "person.badge.plus")
                }
            } header: {
                Text(String(localized: "property.contact_people"))
            }

            Section {
                Text(String(localized: "property.security_footer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(String(localized: "property.alarm_code")) {
                    RevealableSecureField(
                        placeholder: String(localized: "common.optional"),
                        text: $property.alarmOrSecurityCode,
                        isRevealed: $showAlarmCode
                    )
                }
                LabeledContent(String(localized: "property.gate_code")) {
                    RevealableSecureField(
                        placeholder: String(localized: "common.optional"),
                        text: $property.gateOrAccessCode,
                        isRevealed: $showGateCode
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "property.water_shutoff"))
                        .font(.subheadline.weight(.semibold))
                    TextField(String(localized: "property.water_shutoff_prompt"), text: $property.waterShutoffLocation, axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "property.trash_recycling"))
                        .font(.subheadline.weight(.semibold))
                    TextField(String(localized: "property.trash_prompt"), text: $property.trashAndRecyclingSchedule, axis: .vertical)
                        .lineLimit(2 ... 4)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "property.parking"))
                        .font(.subheadline.weight(.semibold))
                    TextField(String(localized: "property.parking_prompt"), text: $property.parkingNotes, axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "property.smart_home"))
                        .font(.subheadline.weight(.semibold))
                    TextField(String(localized: "property.smart_home_prompt"), text: $property.smartHomeNotes, axis: .vertical)
                        .lineLimit(2 ... 6)
                }
            } header: {
                Text(String(localized: "property.other_systems"))
            }

            // MARK: Contractors
            Section {
                if contractorsByTrade.isEmpty {
                    Text(property.isRented
                          ? String(localized: "property.contractors.empty_rented")
                          : String(localized: "property.contractors.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(contractorsByTrade, id: \.trade) { group in
                        DisclosureGroup {
                            ForEach(group.items) { contractor in
                                ContractorRow(contractor: contractor)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            modelContext.delete(contractor)
                                        } label: {
                                            Label(String(localized: "common.delete"), systemImage: "trash")
                                        }
                                    }
                            }
                        } label: {
                            Label(group.trade.displayTitle, systemImage: group.trade.systemImage)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                Button {
                    showAddContractor = true
                } label: {
                    Label(
                        property.isRented
                            ? String(localized: "property.add_repair_contact")
                            : String(localized: "property.add_contractor"),
                        systemImage: "hammer.fill"
                    )
                }
            } header: {
                Text(property.isRented
                      ? String(localized: "property.repair_contacts")
                      : String(localized: "property.contractors"))
            } footer: {
                if property.isRented {
                    Text(String(localized: "property.contractors.hint_rented"))
                } else {
                    Text(String(localized: "property.contractors.hint"))
                }
            }

            // MARK: Service providers
            Section {
                if providersByKind.isEmpty {
                    Text(String(localized: "property.providers.hint"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(providersByKind, id: \.kind) { group in
                        DisclosureGroup {
                            ForEach(group.items) { provider in
                                ServiceProviderRow(provider: provider)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            modelContext.delete(provider)
                                        } label: {
                                            Label(String(localized: "common.delete"), systemImage: "trash")
                                        }
                                    }
                            }
                        } label: {
                            Label(group.kind.displayTitle, systemImage: group.kind.systemImage)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                Button {
                    showAddServiceProvider = true
                } label: {
                    Label(String(localized: "property.add_provider"), systemImage: "building.2.fill")
                }
            } header: {
                Text(String(localized: "property.service_providers"))
            }

            Section {
                LabeledContent(String(localized: "property.insurance_policy")) {
                    TextField(String(localized: "common.optional"), text: $property.insurancePolicyNumber)
                        .multilineTextAlignment(.trailing)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "property.utilities_accounts"))
                        .font(.subheadline.weight(.semibold))
                    TextField(String(localized: "property.utilities_prompt"), text: $property.utilitiesNotes, axis: .vertical)
                        .lineLimit(3 ... 8)
                }
            } header: {
                Text(String(localized: "property.more_details"))
            }

            Section {
                Button {
                    showAddInventoryItem = true
                } label: {
                    Label(String(localized: "property.add_belonging"), systemImage: "plus.circle.fill")
                }

                if (property.inventoryItems ?? []).isEmpty {
                    Text(String(localized: "property.belongings_empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(InventoryItem.groupedByStashSection(property.inventoryItems ?? []), id: \.section) { bucket in
                        Section {
                            ForEach(bucket.items) { item in
                                Button {
                                    inventoryItemToEdit = item
                                } label: {
                                    BelongingsItemRow(item: item, showsProperty: false)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text(bucket.section.title)
                        }
                    }
                }
            } header: {
                Text(String(localized: "property.belongings_section"))
            }

            Section {
                Button {
                    showAddRecipe = true
                } label: {
                    Label(String(localized: "property.add_recipe"), systemImage: "plus.circle.fill")
                }

                let placeRecipes = Recipe.sorted(property.recipes ?? [])
                if placeRecipes.isEmpty {
                    Text(String(localized: "property.recipes_empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(placeRecipes) { recipe in
                        Button {
                            recipeToEdit = recipe
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.title.isEmpty ? String(localized: "recipe.untitled") : recipe.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                if recipe.prepTimeMinutes > 0 || !recipe.trimmedPlaceLabel.isEmpty {
                                    HStack(spacing: 6) {
                                        if !recipe.trimmedPlaceLabel.isEmpty {
                                            Text(recipe.trimmedPlaceLabel)
                                        }
                                        if recipe.prepTimeMinutes > 0 {
                                            Text("\(recipe.prepTimeMinutes) \(String(localized: "recipe.minutes_short"))")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink {
                    RecipesListView(filterProperty: property)
                } label: {
                    Label(String(localized: "property.all_recipes"), systemImage: "frying.pan.fill")
                }
            } header: {
                Text(String(localized: "property.recipes_section"))
            }

            Section {
                Button {
                    showAddMaintenance = true
                } label: {
                    Label(String(localized: "property.add_maintenance"), systemImage: "plus.circle.fill")
                }

                let logs = PropertyMaintenanceEntry.sorted(property.maintenanceEntries ?? [])
                if logs.isEmpty {
                    Text(String(localized: "property.maintenance_empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logs.prefix(5)) { entry in
                        Button {
                            maintenanceToEdit = entry
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: entry.category.systemImage)
                                    .foregroundStyle(SimpsonsTheme.brown)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title.isEmpty ? String(localized: "maintenance.untitled") : entry.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if let days = entry.daysUntilDue() {
                                        Text(
                                            days < 0
                                                ? String(format: String(localized: "maintenance.overdue_days"), locale: .current, abs(days))
                                                : (days == 0
                                                    ? String(localized: "maintenance.due_today")
                                                    : String(format: String(localized: "maintenance.due_in_days"), locale: .current, days))
                                        )
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(days < 0 ? .red : (days <= 30 ? SimpsonsTheme.orange : .secondary))
                                    } else if entry.performedAt > Date(timeIntervalSince1970: 0) {
                                        Text(entry.performedAt.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink {
                    MaintenanceLogListView(filterProperty: property)
                } label: {
                    Label(String(localized: "property.all_maintenance"), systemImage: "wrench.and.screwdriver.fill")
                }
            } header: {
                Text(String(localized: "property.maintenance_section"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(
            property.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "property.detail.title")
                : property.name
        )
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .onChange(of: property.name) { _, _ in
            persistPropertyEdits()
        }
        .onDisappear {
            persistPropertyEdits()
        }
        .sheet(isPresented: $showAddContact) {
            AddPropertyContactSheet(property: property)
        }
        .sheet(isPresented: $showAddEmergencyLine) {
            AddPropertyEmergencyLineSheet(property: property)
        }
        .sheet(isPresented: $showAddContractor) {
            AddPropertyContractorSheet(property: property)
        }
        .sheet(isPresented: $showAddServiceProvider) {
            AddPropertyServiceProviderSheet(property: property)
        }
        .sheet(isPresented: $showAddInventoryItem) {
            NavigationStack {
                AddInventoryItemView(defaultProperty: property)
            }
        }
        .sheet(item: $inventoryItemToEdit) { item in
            NavigationStack {
                AddInventoryItemView(itemToEdit: item)
            }
        }
        .sheet(isPresented: $showAddRecipe) {
            NavigationStack {
                RecipeEditorView(defaultProperty: property)
            }
        }
        .sheet(item: $recipeToEdit) { recipe in
            NavigationStack {
                RecipeEditorView(recipeToEdit: recipe)
            }
        }
        .sheet(isPresented: $showAddMaintenance) {
            NavigationStack {
                MaintenanceEntryEditorView(defaultProperty: property)
            }
        }
        .sheet(item: $maintenanceToEdit) { entry in
            NavigationStack {
                MaintenanceEntryEditorView(entryToEdit: entry)
            }
        }
        .task {
            let normalized = property.propertyKind.normalizedForPicker
            if normalized != property.propertyKind {
                property.propertyKind = normalized
            }
        }
        .onChange(of: photoPickerItem) { _, newItem in
            loadPhoto(from: newItem)
        }
    }

    private func persistPropertyEdits() {
        do {
            try modelContext.save()
        } catch {
            print("[TheGomsons] Failed to save property edits: \(error.localizedDescription)")
        }
    }

    /// Accepts full URLs or host/path strings for the property register link.
    private static func sanitizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        if let url = URL(string: "https://\(trimmed)"), url.host != nil { return url }
        return nil
    }

    @ViewBuilder
    private var rentalSection: some View {
        Section {
            TextField(String(localized: "property.rental.landlord"), text: $property.landlordOrOwnerName)
                .textContentType(.name)
            TextField(String(localized: "property.rental.company"), text: $property.rentalCompanyName)
                .textContentType(.organizationName)
            TextField(String(localized: "property.rental.company_phone"), text: $property.rentalCompanyPhone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
            if !property.rentalCompanyPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let url = TelephoneURL.url(for: property.rentalCompanyPhone) {
                Link(destination: url) {
                    Label(property.rentalCompanyPhone, systemImage: "phone.fill")
                }
            }
            TextField(String(localized: "property.rental.company_email"), text: $property.rentalCompanyEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            if !property.rentalCompanyEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let mailURL = URL(string: "mailto:\(property.rentalCompanyEmail)") {
                Link(destination: mailURL) {
                    Label(property.rentalCompanyEmail, systemImage: "envelope.fill")
                }
            }

            LabeledContent(String(localized: "property.rental.deposit")) {
                TextField(String(localized: "property.rental.amount_placeholder"), text: $property.depositAmount)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(String(localized: "property.rental.monthly_rent")) {
                TextField(String(localized: "property.rental.amount_placeholder"), text: $property.monthlyRent)
                    .multilineTextAlignment(.trailing)
            }

            Toggle(String(localized: "property.rental.lease_start"), isOn: leaseStartEnabled)
            if property.leaseStartDate != nil {
                DatePicker(
                    String(localized: "property.rental.lease_start"),
                    selection: leaseStartBinding,
                    displayedComponents: .date
                )
            }
            Toggle(String(localized: "property.rental.lease_end"), isOn: leaseEndEnabled)
            if property.leaseEndDate != nil {
                DatePicker(
                    String(localized: "property.rental.lease_end"),
                    selection: leaseEndBinding,
                    displayedComponents: .date
                )
            }

            TextField(String(localized: "property.rental.contract_ref"), text: $property.rentalContractReference)
            TextField(
                String(localized: "property.rental.contract_notes"),
                text: $property.rentalContractNotes,
                axis: .vertical
            )
            .lineLimit(3 ... 10)
        } header: {
            Text(String(localized: "property.rental.section"))
        } footer: {
            Text(String(localized: "property.rental.footer"))
        }
    }

    private var leaseStartEnabled: Binding<Bool> {
        Binding(
            get: { property.leaseStartDate != nil },
            set: { property.leaseStartDate = $0 ? (property.leaseStartDate ?? Date()) : nil }
        )
    }

    private var leaseStartBinding: Binding<Date> {
        Binding(
            get: { property.leaseStartDate ?? Date() },
            set: { property.leaseStartDate = $0 }
        )
    }

    private var leaseEndEnabled: Binding<Bool> {
        Binding(
            get: { property.leaseEndDate != nil },
            set: { property.leaseEndDate = $0 ? (property.leaseEndDate ?? Date()) : nil }
        )
    }

    private var leaseEndBinding: Binding<Date> {
        Binding(
            get: { property.leaseEndDate ?? Date() },
            set: { property.leaseEndDate = $0 }
        )
    }
}

private enum TelephoneURL {
    static func url(for raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digits = trimmed.filter { $0.isNumber || $0 == "+" }
        guard digits.count >= 3 else { return nil }
        return URL(string: "tel:" + digits)
    }
}

/// Secure text that stays masked until the eye button is tapped.
private struct RevealableSecureField: View {
    var placeholder: String
    @Binding var text: String
    @Binding var isRevealed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .multilineTextAlignment(.trailing)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isRevealed
                    ? String(localized: "common.hide_secret")
                    : String(localized: "common.show_secret")
            )
        }
    }
}

struct AddPropertyContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let property: Property

    @State private var name = ""
    @State private var role = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var notes = ""
    @State private var isPrimary = false

    private var roleSuggestions: [String] {
        [
            String(localized: "property.role.landlord"),
            String(localized: "property.role.hoa"),
            String(localized: "property.role.manager"),
            String(localized: "property.role.super"),
            String(localized: "property.role.neighbor"),
            String(localized: "property.role.insurance"),
            String(localized: "property.role.plumber"),
        ]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "property.contact.person")) {
                    TextField(String(localized: "common.name"), text: $name)
                    TextField(
                        String(localized: "property.person.role"),
                        text: $role,
                        prompt: Text(String(localized: "property.person.role_prompt"))
                    )
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(roleSuggestions, id: \.self) { suggestion in
                                Button {
                                    role = suggestion
                                } label: {
                                    Text(suggestion)
                                        .font(.caption.weight(.medium))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section(String(localized: "property.contact.reach")) {
                    TextField(String(localized: "common.phone"), text: $phone)
                        .keyboardType(.phonePad)
                    TextField(String(localized: "common.email"), text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                Section(String(localized: "common.notes")) {
                    TextField(String(localized: "property.contact.notes_prompt"), text: $notes, axis: .vertical)
                        .lineLimit(2 ... 6)
                }
                Section {
                    Toggle(String(localized: "property.contact.primary_toggle"), isOn: $isPrimary)
                }
            }
            .navigationTitle(String(localized: "property.contact.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add")) {
                        let nextOrder = ((property.contacts ?? []).map(\.sortOrder).max() ?? -1) + 1
                        if isPrimary {
                            for c in (property.contacts ?? []) where c.isPrimary {
                                c.isPrimary = false
                            }
                        }
                        let contact = PropertyContact(
                            name: name,
                            role: role,
                            phone: phone,
                            email: email,
                            notes: notes,
                            isPrimary: isPrimary,
                            sortOrder: nextOrder,
                            property: property
                        )
                        modelContext.insert(contact)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct AddPropertyEmergencyLineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let property: Property

    @State private var label = ""
    @State private var phoneNumber = ""

    private var poisonControlNumber: String {
        if Locale.current.language.languageCode?.identifier == "nb" {
            return "22 59 13 00"
        }
        return "1-800-222-1222"
    }

    private var presets: [(String, String)] {
        [
            (String(localized: "property.emergency.preset.police"), ""),
            (String(localized: "property.emergency.preset.fire"), ""),
            (String(localized: "property.emergency.preset.poison"), poisonControlNumber),
            (String(localized: "property.emergency.preset.building"), ""),
            (String(localized: "property.emergency.preset.gas"), ""),
        ]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "property.emergency.number_section")) {
                    TextField(
                        String(localized: "property.emergency.label"),
                        text: $label,
                        prompt: Text(String(localized: "property.emergency.label_prompt"))
                    )
                    TextField(String(localized: "common.phone"), text: $phoneNumber)
                        .keyboardType(.phonePad)
                }
                Section(String(localized: "property.emergency.quick")) {
                    ForEach(presets, id: \.0) { preset in
                        Button {
                            label = preset.0
                            phoneNumber = preset.1
                        } label: {
                            HStack {
                                Text(preset.0)
                                Spacer()
                                if !preset.1.isEmpty {
                                    Text(preset.1)
                                        .foregroundStyle(.secondary)
                                        .font(.caption.monospaced())
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "property.emergency.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add")) {
                        let nextOrder = ((property.emergencyLines ?? []).map(\.sortOrder).max() ?? -1) + 1
                        let line = PropertyEmergencyLine(
                            label: label,
                            phoneNumber: phoneNumber,
                            sortOrder: nextOrder,
                            property: property
                        )
                        modelContext.insert(line)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Row views

private struct ContractorRow: View {
    let contractor: PropertyContractor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(contractor.name.isEmpty ? String(localized: "common.unnamed") : contractor.name)
                .font(.headline)
            if !contractor.phone.isEmpty {
                if let url = TelephoneURL.url(for: contractor.phone) {
                    Link(destination: url) {
                        Label(contractor.phone, systemImage: "phone.fill")
                            .font(.subheadline)
                    }
                } else {
                    Text(contractor.phone).font(.subheadline.monospaced())
                }
            }
            if !contractor.email.isEmpty, let mailURL = URL(string: "mailto:\(contractor.email)") {
                Link(destination: mailURL) {
                    Label(contractor.email, systemImage: "envelope.fill")
                        .font(.caption)
                }
            }
            if !contractor.website.isEmpty {
                if let webURL = URL(string: contractor.website) {
                    Link(destination: webURL) {
                        Label(contractor.website, systemImage: "globe")
                            .font(.caption)
                            .lineLimit(1)
                    }
                } else {
                    Text(contractor.website).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !contractor.notes.isEmpty {
                Text(contractor.notes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ServiceProviderRow: View {
    let provider: PropertyServiceProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(provider.companyName.isEmpty ? String(localized: "common.unnamed") : provider.companyName)
                .font(.headline)
            if !provider.accountNumber.isEmpty {
                Label(
                    String(format: String(localized: "property.account_fmt"), locale: .current, provider.accountNumber),
                    systemImage: "number"
                )
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if !provider.phone.isEmpty {
                if let url = TelephoneURL.url(for: provider.phone) {
                    Link(destination: url) {
                        Label(provider.phone, systemImage: "phone.fill")
                            .font(.subheadline)
                    }
                } else {
                    Text(provider.phone).font(.subheadline.monospaced())
                }
            }
            if !provider.email.isEmpty, let mailURL = URL(string: "mailto:\(provider.email)") {
                Link(destination: mailURL) {
                    Label(provider.email, systemImage: "envelope.fill")
                        .font(.caption)
                }
            }
            if !provider.website.isEmpty {
                if let webURL = URL(string: provider.website) {
                    Link(destination: webURL) {
                        Label(provider.website, systemImage: "globe")
                            .font(.caption)
                            .lineLimit(1)
                    }
                } else {
                    Text(provider.website).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !provider.notes.isEmpty {
                Text(provider.notes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add contractor sheet

struct AddPropertyContractorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let property: Property

    @State private var name = ""
    @State private var trade: ContractorTrade = .other
    @State private var phone = ""
    @State private var email = ""
    @State private var website = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "property.trade")) {
                    Picker(String(localized: "property.trade"), selection: $trade) {
                        ForEach(ContractorTrade.allCases, id: \.self) { t in
                            Label(t.displayTitle, systemImage: t.systemImage).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section(String(localized: "property.details")) {
                    TextField(String(localized: "property.contractor.name_company"), text: $name)
                    TextField(String(localized: "common.phone"), text: $phone)
                        .keyboardType(.phonePad)
                    TextField(String(localized: "common.email"), text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField(String(localized: "property.website"), text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
                Section(String(localized: "common.notes")) {
                    TextField(String(localized: "property.contractor.notes_prompt"), text: $notes, axis: .vertical)
                        .lineLimit(2 ... 6)
                }
            }
            .navigationTitle(String(localized: "property.contractor.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add")) {
                        let nextOrder = ((property.contractors ?? []).map(\.sortOrder).max() ?? -1) + 1
                        let contractor = PropertyContractor(
                            name: name,
                            trade: trade,
                            phone: phone,
                            email: email,
                            website: website,
                            notes: notes,
                            sortOrder: nextOrder,
                            property: property
                        )
                        modelContext.insert(contractor)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Add service provider sheet

struct AddPropertyServiceProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let property: Property

    @State private var companyName = ""
    @State private var kind: ServiceProviderKind = .other
    @State private var accountNumber = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var website = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "property.provider.type")) {
                    Picker(String(localized: "property.category"), selection: $kind) {
                        ForEach(ServiceProviderKind.allCases, id: \.self) { k in
                            Label(k.displayTitle, systemImage: k.systemImage).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section(String(localized: "property.details")) {
                    TextField(String(localized: "property.company_name"), text: $companyName)
                    TextField(String(localized: "property.account_number"), text: $accountNumber)
                        .textInputAutocapitalization(.never)
                    TextField(String(localized: "common.phone"), text: $phone)
                        .keyboardType(.phonePad)
                    TextField(String(localized: "common.email"), text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField(String(localized: "property.website_portal"), text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
                Section(String(localized: "common.notes")) {
                    TextField(String(localized: "property.provider.notes_prompt"), text: $notes, axis: .vertical)
                        .lineLimit(2 ... 6)
                }
            }
            .navigationTitle(String(localized: "property.provider.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add")) {
                        let nextOrder = ((property.serviceProviders ?? []).map(\.sortOrder).max() ?? -1) + 1
                        let provider = PropertyServiceProvider(
                            companyName: companyName,
                            kind: kind,
                            accountNumber: accountNumber,
                            phone: phone,
                            email: email,
                            website: website,
                            notes: notes,
                            sortOrder: nextOrder,
                            property: property
                        )
                        modelContext.insert(provider)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PropertyDetailView(
            property: Property(
                name: "Lake house",
                address: "123 Shore Rd",
                wifiNetwork: "GomsonsGuest",
                wifiPassword: "secret",
                emergencyNotes: "Breaker panel in garage.",
                propertyKind: PropertyKind.cabin,
                bedrooms: 4,
                bathrooms: 2.5,
                livingAreaSqFt: 185,
                yearBuilt: 1998
            )
        )
    }
    .modelContainer(
        for: [
            Property.self,
            PropertyContact.self,
            PropertyEmergencyLine.self,
            PropertyContractor.self,
            PropertyServiceProvider.self,
            InventoryItem.self,
            InventoryItemLink.self,
            InventoryItemDocument.self,
            Recipe.self,
            PropertyMaintenanceEntry.self,
        ],
        inMemory: true
    )
}
