//
//  FamilyGroupPhotosView.swift
//  TheGomsons
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Shared family photo album (not tied to a single person).
struct FamilyGroupPhotosView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyGroupPhoto.sortOrder) private var photos: [FamilyGroupPhoto]

    @State private var pickerItem: PhotosPickerItem?
    @State private var editingPhoto: FamilyGroupPhoto?
    @State private var draftCaption = ""
    @State private var confirmDelete: FamilyGroupPhoto?

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                if photos.isEmpty {
                    ContentUnavailableView(
                        String(localized: "family_tree.photos_empty_title"),
                        systemImage: "photo.on.rectangle.angled",
                        description: Text(String(localized: "family_tree.photos_empty_detail"))
                    )
                    .frame(minHeight: 220)
                    .padding(.top, 32)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(photos) { photo in
                            groupPhotoCell(photo)
                        }
                    }
                    .padding(16)
                }
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(SimpsonsTheme.charcoal)
                    .padding(12)
                    .background(Circle().fill(SimpsonsTheme.orange.opacity(0.95)))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
            .accessibilityLabel(String(localized: "family_tree.add_group_photo"))
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: pickerItem) { _, new in
            Task { await importPickedPhoto(new) }
        }
        .sheet(item: $editingPhoto) { photo in
            NavigationStack {
                Form {
                    Section {
                        if let data = photo.imageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    Section(String(localized: "family_tree.group_photo_caption")) {
                        TextField(String(localized: "family_tree.group_photo_caption_placeholder"), text: $draftCaption, axis: .vertical)
                            .lineLimit(2 ... 8)
                    }
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = photo
                        } label: {
                            Label(String(localized: "family_tree.delete_group_photo"), systemImage: "trash")
                        }
                    }
                }
                .navigationTitle(String(localized: "family_tree.group_photo_edit"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.cancel")) {
                            editingPhoto = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.save")) {
                            photo.caption = draftCaption.trimmingCharacters(in: .whitespacesAndNewlines)
                            try? modelContext.save()
                            editingPhoto = nil
                        }
                        .fontWeight(.semibold)
                    }
                }
                .onAppear {
                    draftCaption = photo.caption
                }
            }
        }
        .confirmationDialog(
            String(localized: "family_tree.delete_group_photo_confirm"),
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                if let p = confirmDelete {
                    modelContext.delete(p)
                    try? modelContext.save()
                    if editingPhoto?.persistentModelID == p.persistentModelID {
                        editingPhoto = nil
                    }
                }
                confirmDelete = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                confirmDelete = nil
            }
        }
    }

    @ViewBuilder
    private func groupPhotoCell(_ photo: FamilyGroupPhoto) -> some View {
        Button {
            editingPhoto = photo
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let data = photo.imageData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.secondarySystemFill)
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            }
                    }
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if !photo.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(photo.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func importPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await MainActor.run {
            let next = (photos.map(\.sortOrder).max() ?? 0) + 1
            let p = FamilyGroupPhoto(caption: "", sortOrder: next, addedAt: Date(), imageData: data)
            modelContext.insert(p)
            try? modelContext.save()
            pickerItem = nil
        }
    }
}
