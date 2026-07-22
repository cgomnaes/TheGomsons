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
                    .frame(height: 220)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.blue.opacity(0.25), Color.cyan.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Add a photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 180)
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
                    Label("Remove photo", systemImage: "trash")
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
                VStack(spacing: 0) {
                    propertyCoverImage
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Property name", text: $property.name)
                            .font(.title2.weight(.bold))
                        TextField("Address", text: $property.address, axis: .vertical)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1...4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Key information") {
                Picker("Type", selection: $property.propertyKind) {
                    ForEach(PropertyKind.pickerCases, id: \.self) { kind in
                        Text(kind.displayTitle).tag(kind)
                    }
                }
                HStack {
                    Text("Bedrooms")
                    Spacer()
                    IntZeroAsEmptyField(placeholder: "—", value: $property.bedrooms)
                        .frame(maxWidth: 80)
                }
                HStack {
                    Text("Bathrooms")
                    Spacer()
                    DoubleZeroAsEmptyField(placeholder: "—", value: $property.bathrooms)
                        .frame(maxWidth: 80)
                }
                HStack {
                    Text("Year built")
                    Spacer()
                    IntZeroAsEmptyField(placeholder: "—", value: $property.yearBuilt, maxDigits: 4)
                        .frame(maxWidth: 100)
                }
                LabeledContent("Insurance company") {
                    TextField("Optional", text: $property.insuranceCarrier)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Wi‑Fi") {
                LabeledContent("Network") {
                    TextField("SSID", text: $property.wifiNetwork)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Password") {
                    SecureField("Password", text: $property.wifiPassword)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                if sortedEmergencyLines.isEmpty {
                    Text("Police non-emergency, poison control, building super after hours…")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedEmergencyLines) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.label.isEmpty ? "Unlabeled" : line.label)
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
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                Button {
                    showAddEmergencyLine = true
                } label: {
                    Label("Add number", systemImage: "cross.case.fill")
                }
                TextField("Medical, egress, breaker panel, gas shutoff…", text: $property.emergencyNotes, axis: .vertical)
                    .lineLimit(4 ... 12)
            } header: {
                Text("Emergency contacts")
            } footer: {
                Text("Dialable numbers above; add context here (medical, egress, breaker panel, gas shutoff…).")
                    .font(.caption)
            }

            Section("Contact people") {
                if sortedContacts.isEmpty {
                    Text("Add a landlord, HOA contact, handyman, or neighbor.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedContacts) { contact in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(contact.name.isEmpty ? "Unnamed contact" : contact.name)
                                    .font(.headline)
                                if contact.isPrimary {
                                    Text("Primary")
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
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                Button {
                    showAddContact = true
                } label: {
                    Label("Add contact", systemImage: "person.badge.plus")
                }
            }

            Section {
                Text("Alarm, gate codes, shutoffs, and smart-home notes stay on-device—only share this screen with people you trust.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Other systems") {
                LabeledContent("Alarm / security code") {
                    SecureField("Optional", text: $property.alarmOrSecurityCode)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Gate / door code") {
                    SecureField("Optional", text: $property.gateOrAccessCode)
                        .multilineTextAlignment(.trailing)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Water shutoff")
                        .font(.subheadline.weight(.semibold))
                    TextField("Basement, street valve, unit…", text: $property.waterShutoffLocation, axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trash & recycling")
                        .font(.subheadline.weight(.semibold))
                    TextField("Pickup days, cart storage…", text: $property.trashAndRecyclingSchedule, axis: .vertical)
                        .lineLimit(2 ... 4)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Parking")
                        .font(.subheadline.weight(.semibold))
                    TextField("Spots, permits, guest rules…", text: $property.parkingNotes, axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Smart home")
                        .font(.subheadline.weight(.semibold))
                    TextField("Hubs, apps, automations…", text: $property.smartHomeNotes, axis: .vertical)
                        .lineLimit(2 ... 6)
                }
            }

            // MARK: Contractors
            Section {
                if contractorsByTrade.isEmpty {
                    Text("Electricians, plumbers, carpenters, handymen…")
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
                                            Label("Delete", systemImage: "trash")
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
                    Label("Add contractor", systemImage: "hammer.fill")
                }
            } header: {
                Text("Contractors")
            }

            // MARK: Service providers
            Section {
                if providersByKind.isEmpty {
                    Text("Electricity company, internet, public services…")
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
                                            Label("Delete", systemImage: "trash")
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
                    Label("Add service provider", systemImage: "building.2.fill")
                }
            } header: {
                Text("Service providers")
            }

            Section("More details") {
                HStack {
                    Text("Living area (m²)")
                    Spacer()
                    IntZeroAsEmptyField(placeholder: "—", value: $property.livingAreaSqFt)
                        .frame(maxWidth: 100)
                }
                LabeledContent("Insurance policy #") {
                    TextField("Optional", text: $property.insurancePolicyNumber)
                        .multilineTextAlignment(.trailing)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Utilities & accounts")
                        .font(.subheadline.weight(.semibold))
                    TextField("Gas, electric, water, internet account hints…", text: $property.utilitiesNotes, axis: .vertical)
                        .lineLimit(3 ... 8)
                }
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
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
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

    private let roleSuggestions = [
        "Landlord",
        "HOA / board",
        "Property manager",
        "Building super",
        "Neighbor",
        "Insurance agent",
        "Plumber / HVAC",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $name)
                    TextField("Role", text: $role, prompt: Text("Landlord, HOA, neighbor…"))
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
                Section("Reach them") {
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                Section("Notes") {
                    TextField("Gate fob, hours, languages…", text: $notes, axis: .vertical)
                        .lineLimit(2 ... 6)
                }
                Section {
                    Toggle("Primary contact for this property", isOn: $isPrimary)
                }
            }
            .navigationTitle("New contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
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

    private let presets = [
        ("Police (non-emergency)", ""),
        ("Fire / EMS (local)", ""),
        ("Poison control", "1-800-222-1222"),
        ("Building after-hours", ""),
        ("Utility gas leak", ""),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Number") {
                    TextField("Label", text: $label, prompt: Text("e.g. Police non-emergency"))
                    TextField("Phone", text: $phoneNumber)
                        .keyboardType(.phonePad)
                }
                Section("Quick add") {
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
            .navigationTitle("Emergency number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
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
            Text(contractor.name.isEmpty ? "Unnamed" : contractor.name)
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
            Text(provider.companyName.isEmpty ? "Unnamed" : provider.companyName)
                .font(.headline)
            if !provider.accountNumber.isEmpty {
                Label("Acct: \(provider.accountNumber)", systemImage: "number")
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
                Section("Trade") {
                    Picker("Trade", selection: $trade) {
                        ForEach(ContractorTrade.allCases, id: \.self) { t in
                            Label(t.displayTitle, systemImage: t.systemImage).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Details") {
                    TextField("Name / company", text: $name)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Website", text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
                Section("Notes") {
                    TextField("Availability, pricing, ratings…", text: $notes, axis: .vertical)
                        .lineLimit(2 ... 6)
                }
            }
            .navigationTitle("New contractor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
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
                Section("Type") {
                    Picker("Category", selection: $kind) {
                        ForEach(ServiceProviderKind.allCases, id: \.self) { k in
                            Label(k.displayTitle, systemImage: k.systemImage).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Details") {
                    TextField("Company name", text: $companyName)
                    TextField("Account number", text: $accountNumber)
                        .textInputAutocapitalization(.never)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Website / portal URL", text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
                Section("Notes") {
                    TextField("Login hints, billing cycle, contact person…", text: $notes, axis: .vertical)
                        .lineLimit(2 ... 6)
                }
            }
            .navigationTitle("New service provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
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
