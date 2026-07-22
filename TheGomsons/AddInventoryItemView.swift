//
//  AddInventoryItemView.swift
//  TheGomsons
//

import PhotosUI
import QuickLook
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AddInventoryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @Query(sort: \Property.name) private var properties: [Property]

    private let itemToEdit: InventoryItem?
    private let defaultProperty: Property?

    @State private var name: String
    @State private var category: InventoryCategory
    @State private var estimatedValue: Double
    @State private var currentRetailPrice: Double
    @State private var purchaseDate: Date
    @State private var warrantyExpiry: Date
    @State private var notes: String
    @State private var purchasePlace: String
    @State private var locationDetail: String
    @State private var productURL: String
    @State private var insuranceNotes: String
    @State private var selectedProperty: Property?

    @State private var draftLinks: [DraftLink] = []
    @State private var draftDocuments: [DraftDocument] = []

    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var showCamera = false
    @State private var isAnalyzing = false
    @State private var analysisSummary = ""
    @State private var rankedVisionOptions: [InventoryImageAnalyzer.RankedOption] = []
    @State private var selectedVisionIdentifier: String?
    @State private var confirmDelete = false

    @State private var showFileImporter = false
    @State private var pendingDocumentKind: InventoryDocumentKind = .receipt
    @State private var showKindPicker = false
    @State private var previewURL: URL?

    private var isEditing: Bool { itemToEdit != nil }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private struct DraftLink: Identifiable, Equatable {
        let id: UUID
        var title: String
        var url: String
    }

    private struct DraftDocument: Identifiable, Equatable {
        let id: UUID
        var title: String
        var kind: InventoryDocumentKind
        var fileName: String
        var contentType: String
        var fileData: Data
    }

    init(itemToEdit: InventoryItem? = nil, defaultProperty: Property? = nil) {
        _properties = Query(sort: \Property.name)
        self.itemToEdit = itemToEdit
        self.defaultProperty = defaultProperty
        if let item = itemToEdit {
            _name = State(initialValue: item.name)
            _category = State(initialValue: item.category)
            _estimatedValue = State(initialValue: item.estimatedValue)
            _currentRetailPrice = State(initialValue: item.currentRetailPrice)
            _purchaseDate = State(initialValue: item.purchaseDate)
            _warrantyExpiry = State(initialValue: item.warrantyExpiry)
            _notes = State(initialValue: item.notes)
            _purchasePlace = State(initialValue: item.purchasePlace)
            _locationDetail = State(initialValue: item.locationDetail)
            _productURL = State(initialValue: item.productURL)
            _insuranceNotes = State(initialValue: item.insuranceNotes)
            _selectedProperty = State(initialValue: item.property)
            _pickedImage = State(initialValue: item.photoData.flatMap { UIImage(data: $0) })
            _draftLinks = State(initialValue: item.sortedLinks.map {
                DraftLink(id: UUID(), title: $0.title, url: $0.url)
            })
            _draftDocuments = State(initialValue: item.sortedDocuments.compactMap { doc in
                guard let data = doc.fileData else { return nil }
                return DraftDocument(
                    id: UUID(),
                    title: doc.title.isEmpty ? doc.fileName : doc.title,
                    kind: doc.kind,
                    fileName: doc.fileName,
                    contentType: doc.contentType,
                    fileData: data
                )
            })
        } else {
            _name = State(initialValue: "")
            _category = State(initialValue: .other)
            _estimatedValue = State(initialValue: 0)
            _currentRetailPrice = State(initialValue: 0)
            _purchaseDate = State(initialValue: Date())
            _warrantyExpiry = State(initialValue: Date(timeIntervalSince1970: 0))
            _notes = State(initialValue: "")
            _purchasePlace = State(initialValue: "")
            _locationDetail = State(initialValue: "")
            _productURL = State(initialValue: "")
            _insuranceNotes = State(initialValue: "")
            _selectedProperty = State(initialValue: defaultProperty)
            _pickedImage = State(initialValue: nil)
        }
    }

    var body: some View {
        Form {
            itemSection
            photoSection
            if shouldShowVisionPicker {
                visionSection
            }
            whereSection
            purchaseSection
            linksSection
            documentsSection
            notesSection
            if isEditing {
                Section {
                    Button(String(localized: "inventory.delete"), role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
        }
        .navigationTitle(isEditing ? String(localized: "inventory.edit_title") : String(localized: "inventory.add_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "common.save")) { saveItem() }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            Task { await loadPhoto(from: newItem) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(image: $pickedImage)
                .ignoresSafeArea()
        }
        .onChange(of: pickedImage) { _, newImage in
            guard newImage != nil, itemToEdit == nil else { return }
            analysisSummary = ""
            rankedVisionOptions = []
            selectedVisionIdentifier = nil
            Task { await runAnalysis() }
        }
        .onAppear { applyDefaultPropertyIfNeeded() }
        .onChange(of: properties.count) { _, _ in applyDefaultPropertyIfNeeded() }
        .confirmationDialog(
            String(localized: "inventory.delete_item_confirm"),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) { deleteItemAndDismiss() }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "inventory.delete_confirm"))
        }
        .confirmationDialog(
            String(localized: "inventory.doc.pick_kind"),
            isPresented: $showKindPicker,
            titleVisibility: .visible
        ) {
            ForEach(InventoryDocumentKind.allCases, id: \.self) { kind in
                Button(kind.displayTitle) {
                    pendingDocumentKind = kind
                    showFileImporter = true
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image, .jpeg, .png, .heic],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { cleanupPreview() } }
        )) {
            if let previewURL {
                NavigationStack {
                    InventoryDocumentPreviewSheet(fileURL: previewURL)
                        .navigationTitle(String(localized: "inventory.doc.preview"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(String(localized: "common.done")) { cleanupPreview() }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Sections

    private var itemSection: some View {
        Section {
            TextField(String(localized: "common.name"), text: $name)
                .font(.body.weight(.medium))
            Picker(String(localized: "common.category"), selection: $category) {
                ForEach(InventoryStashSection.allCases, id: \.self) { section in
                    Section(section.title) {
                        ForEach(section.categories, id: \.self) { cat in
                            Text(cat.displayTitle).tag(cat)
                        }
                    }
                }
            }
        }
    }

    private var photoSection: some View {
        Section {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    if let pickedImage {
                        Image(uiImage: pickedImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.tertiarySystemFill)
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.tertiary)
                    }
                    if isAnalyzing {
                        Color.black.opacity(0.4)
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                            Text(String(localized: "inventory.choose_photo"))
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showCamera = true
                            } label: {
                                Image(systemName: "camera")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel(String(localized: "inventory.camera"))
                        }
                    }

                    if pickedImage != nil {
                        HStack(spacing: 12) {
                            Button {
                                Task { await runAnalysis() }
                            } label: {
                                Label(String(localized: "inventory.identify"), systemImage: "sparkles")
                                    .font(.caption.weight(.semibold))
                            }
                            .disabled(isAnalyzing)

                            Button(String(localized: "inventory.remove_photo"), role: .destructive) {
                                clearPhoto()
                            }
                            .font(.caption)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if !analysisSummary.isEmpty {
                Text(analysisSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "inventory.photo"))
        }
    }

    private var visionSection: some View {
        Section {
            ForEach(rankedVisionOptions.prefix(4)) { option in
                Button {
                    name = option.title
                    category = option.category
                    selectedVisionIdentifier = option.identifier
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .foregroundStyle(.primary)
                            Text(option.category.displayTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if option.confidence > 0 {
                            Text(String(format: "%.0f%%", option.confidence * 100))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        if selectedVisionIdentifier == option.identifier {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        } header: {
            Text(String(localized: "common.type"))
        }
    }

    private var whereSection: some View {
        Section {
            Picker(String(localized: "inventory.stored_at"), selection: $selectedProperty) {
                Text(String(localized: "inventory.family_wide")).tag(nil as Property?)
                ForEach(properties.filter { !$0.isArchived }) { property in
                    Text(property.name.isEmpty ? String(localized: "common.unnamed") : property.name)
                        .tag(property as Property?)
                }
            }
            TextField(
                String(localized: "inventory.location_detail"),
                text: $locationDetail,
                prompt: Text(String(localized: "inventory.location_detail.prompt"))
            )
        } header: {
            Text(String(localized: "inventory.where"))
        }
    }

    private var purchaseSection: some View {
        Section {
            TextField(
                String(localized: "inventory.purchase_place"),
                text: $purchasePlace,
                prompt: Text(String(localized: "inventory.purchase_place.prompt"))
            )
            DatePicker(String(localized: "inventory.purchase"), selection: $purchaseDate, displayedComponents: .date)
            DatePicker(String(localized: "inventory.warranty"), selection: $warrantyExpiry, displayedComponents: .date)
            LabeledContent(String(localized: "inventory.est_value")) {
                TextField("0", value: $estimatedValue, format: .currency(code: currencyCode))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(String(localized: "inventory.list_price")) {
                TextField("0", value: $currentRetailPrice, format: .currency(code: currencyCode))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            TextField(
                String(localized: "inventory.insurance_notes"),
                text: $insuranceNotes,
                axis: .vertical
            )
            .lineLimit(2 ... 4)
        } header: {
            Text(String(localized: "inventory.purchase_insurance"))
        }
    }

    private var linksSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField(String(localized: "inventory.product_url"), text: $productURL, prompt: Text("https://"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                if let url = normalizedURL(from: productURL) {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "inventory.open_link"))
                }
            }

            ForEach($draftLinks) { $link in
                VStack(alignment: .leading, spacing: 6) {
                    TextField(String(localized: "inventory.link_title"), text: $link.title)
                        .font(.subheadline)
                    TextField(String(localized: "inventory.link_url"), text: $link.url)
                        .font(.subheadline)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        draftLinks.removeAll { $0.id == link.id }
                    } label: {
                        Label(String(localized: "common.delete"), systemImage: "trash")
                    }
                }
            }

            Button {
                draftLinks.append(DraftLink(id: UUID(), title: "", url: ""))
            } label: {
                Label(String(localized: "inventory.add_link"), systemImage: "plus")
            }
        } header: {
            Text(String(localized: "inventory.links"))
        }
    }

    private var documentsSection: some View {
        Section {
            ForEach(draftDocuments) { doc in
                Button {
                    openDocumentPreview(doc)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(doc.title.isEmpty ? doc.fileName : doc.title)
                                .foregroundStyle(.primary)
                            Text(doc.kind.displayTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        draftDocuments.removeAll { $0.id == doc.id }
                    } label: {
                        Label(String(localized: "common.delete"), systemImage: "trash")
                    }
                }
            }

            Button {
                showKindPicker = true
            } label: {
                Label(String(localized: "inventory.add_document"), systemImage: "plus")
            }
        } header: {
            Text(String(localized: "inventory.documents"))
        } footer: {
            Text(String(localized: "inventory.documents.footer"))
                .font(.caption2)
        }
    }

    private var notesSection: some View {
        Section {
            TextField(String(localized: "inventory.notes.prompt"), text: $notes, axis: .vertical)
                .lineLimit(2 ... 6)
        } header: {
            Text(String(localized: "common.notes"))
        }
    }

    private var shouldShowVisionPicker: Bool {
        guard !rankedVisionOptions.isEmpty else { return false }
        if rankedVisionOptions.count > 1 { return true }
        return (rankedVisionOptions.first?.confidence ?? 0) < 0.4
    }

    // MARK: - Actions

    private func clearPhoto() {
        pickedImage = nil
        pickerItem = nil
        analysisSummary = ""
        rankedVisionOptions = []
        selectedVisionIdentifier = nil
    }

    private func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            break
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), data.count <= 25 * 1024 * 1024 else { return }
            let fileName = url.lastPathComponent
            let contentType = InventoryDocumentFileHelper.contentType(for: fileName, fallbackUTType: nil)
            draftDocuments.append(
                DraftDocument(
                    id: UUID(),
                    title: fileName,
                    kind: pendingDocumentKind,
                    fileName: fileName,
                    contentType: contentType,
                    fileData: data
                )
            )
        }
    }

    private func openDocumentPreview(_ doc: DraftDocument) {
        cleanupPreview()
        if let url = try? InventoryDocumentFileHelper.writeTemporaryFile(data: doc.fileData, fileName: doc.fileName) {
            previewURL = url
        }
    }

    private func cleanupPreview() {
        if let previewURL {
            try? FileManager.default.removeItem(at: previewURL.deletingLastPathComponent())
        }
        previewURL = nil
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            await MainActor.run { pickedImage = image }
        }
    }

    private func applyDefaultPropertyIfNeeded() {
        guard itemToEdit == nil, selectedProperty == nil, defaultProperty != nil else { return }
        selectedProperty = defaultProperty
    }

    private func runAnalysis() async {
        guard let image = pickedImage else { return }
        isAnalyzing = true
        let result = await InventoryImageAnalyzer.analyze(image: image)
        await MainActor.run {
            isAnalyzing = false
            rankedVisionOptions = result.rankedOptions
            selectedVisionIdentifier = result.rankedOptions.first?.identifier
            if !result.suggestedName.isEmpty { name = result.suggestedName }
            category = result.category
            if result.estimatedValue > 0 { estimatedValue = result.estimatedValue }
            if result.currentRetailPrice > 0 { currentRetailPrice = result.currentRetailPrice }
            if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !result.suggestedNotes.isEmpty {
                notes = result.suggestedNotes
            }
            analysisSummary = result.analysisSummary
        }
    }

    private func deleteItemAndDismiss() {
        guard let item = itemToEdit else { return }
        modelContext.delete(item)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to delete belonging: \(error.localizedDescription)")
        }
    }

    private func saveItem() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let jpeg = pickedImage.flatMap { $0.jpegData(compressionQuality: 0.85) }

        let target: InventoryItem
        if let existing = itemToEdit {
            existing.name = trimmed
            existing.category = category
            existing.purchaseDate = purchaseDate
            existing.warrantyExpiry = warrantyExpiry
            existing.estimatedValue = estimatedValue
            existing.currentRetailPrice = currentRetailPrice
            existing.notes = notes
            existing.purchasePlace = purchasePlace
            existing.locationDetail = locationDetail
            existing.productURL = productURL
            existing.insuranceNotes = insuranceNotes
            existing.property = selectedProperty
            existing.photoData = jpeg
            target = existing
            for link in existing.links ?? [] { modelContext.delete(link) }
            for doc in existing.documents ?? [] { modelContext.delete(doc) }
        } else {
            let item = InventoryItem(
                name: trimmed,
                category: category,
                purchaseDate: purchaseDate,
                warrantyExpiry: warrantyExpiry,
                estimatedValue: estimatedValue,
                currentRetailPrice: currentRetailPrice,
                notes: notes,
                purchasePlace: purchasePlace,
                locationDetail: locationDetail,
                productURL: productURL,
                insuranceNotes: insuranceNotes,
                photoData: jpeg,
                property: selectedProperty
            )
            modelContext.insert(item)
            target = item
        }

        for (index, link) in draftLinks.enumerated() {
            let url = link.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { continue }
            let title = link.title.trimmingCharacters(in: .whitespacesAndNewlines)
            modelContext.insert(
                InventoryItemLink(
                    title: title.isEmpty ? url : title,
                    url: url,
                    sortOrder: index,
                    item: target
                )
            )
        }

        for (index, doc) in draftDocuments.enumerated() {
            modelContext.insert(
                InventoryItemDocument(
                    title: doc.title,
                    kind: doc.kind,
                    fileName: doc.fileName,
                    contentType: doc.contentType,
                    fileData: doc.fileData,
                    sortOrder: index,
                    item: target
                )
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("[TheGomsons] Failed to save belonging: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationStack {
        AddInventoryItemView()
    }
    .modelContainer(for: [InventoryItem.self, InventoryItemLink.self, InventoryItemDocument.self, Property.self], inMemory: true)
}
