//
//  AddInventoryItemView.swift
//  TheGomsons
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AddInventoryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Property.name) private var properties: [Property]

    @State private var name = ""
    @State private var category: InventoryCategory = InventoryCategory.other
    @State private var estimatedValue: Double = 0
    @State private var currentRetailPrice: Double = 0
    @State private var purchaseDate = Date()
    @State private var warrantyExpiry = Date(timeIntervalSince1970: 0)
    @State private var selectedProperty: Property?

    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var showCamera = false
    @State private var isAnalyzing = false
    @State private var analysisSummary = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                                Label("Choose photo", systemImage: "photo.on.rectangle.angled")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button {
                                    showCamera = true
                                } label: {
                                    Label("Camera", systemImage: "camera.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        if let pickedImage {
                            Image(uiImage: pickedImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    if isAnalyzing {
                                        ZStack {
                                            Color.black.opacity(0.35)
                                            ProgressView("Analyzing…")
                                                .tint(.white)
                                                .foregroundStyle(.white)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }

                            Button {
                                Task { await runAnalysis() }
                            } label: {
                                Label("Identify from photo", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isAnalyzing)
                        }
                    }
                } header: {
                    Text("Photo")
                } footer: {
                    Text("Uses on-device Vision to guess the item, category, and any visible prices. Results are suggestions only.")
                }

                if !analysisSummary.isEmpty {
                    Section("Analysis") {
                        Text(analysisSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Item") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(InventoryCategory.allCases, id: \.self) { cat in
                            Text(cat.displayTitle).tag(cat)
                        }
                    }
                }

                Section("Values") {
                    HStack {
                        Text("Est. value")
                        Spacer()
                        TextField("0", value: $estimatedValue, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Current / list price")
                        Spacer()
                        TextField("0", value: $currentRetailPrice, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Dates") {
                    DatePicker("Purchase", selection: $purchaseDate, displayedComponents: .date)
                    DatePicker("Warranty ends", selection: $warrantyExpiry, displayedComponents: .date)
                }

                Section("Property") {
                    Picker("Stored at", selection: $selectedProperty) {
                        Text("None").tag(nil as Property?)
                        ForEach(properties) { property in
                            Text(property.name.isEmpty ? "Unnamed" : property.name)
                                .tag(property as Property?)
                        }
                    }
                }
            }
            .navigationTitle("Add inventory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveItem()
                    }
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
                guard newImage != nil else { return }
                analysisSummary = ""
                Task { await runAnalysis() }
            }
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    pickedImage = image
                }
            }
        } catch {
            await MainActor.run {
                analysisSummary = "Could not load photo."
            }
        }
    }

    private func runAnalysis() async {
        guard let image = pickedImage else { return }
        isAnalyzing = true
        let result = await InventoryImageAnalyzer.analyze(image: image)
        await MainActor.run {
            isAnalyzing = false
            if !result.suggestedName.isEmpty {
                name = result.suggestedName
            }
            category = result.category
            if result.estimatedValue > 0 {
                estimatedValue = result.estimatedValue
            }
            if result.currentRetailPrice > 0 {
                currentRetailPrice = result.currentRetailPrice
            }
            analysisSummary = result.analysisSummary
        }
    }

    private func saveItem() {
        let item = InventoryItem(
            name: name,
            category: category,
            purchaseDate: purchaseDate,
            warrantyExpiry: warrantyExpiry,
            estimatedValue: estimatedValue,
            currentRetailPrice: currentRetailPrice,
            property: selectedProperty
        )
        modelContext.insert(item)
        dismiss()
    }
}

#Preview {
    AddInventoryItemView()
        .modelContainer(for: [InventoryItem.self, Property.self], inMemory: true)
}
