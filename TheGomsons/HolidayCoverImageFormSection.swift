//
//  HolidayCoverImageFormSection.swift
//  TheGomsons
//
//  Shared “heading / cover” picker: Wikipedia + satellite + photo library (same behavior as trip editor).
//

import MapKit
import PhotosUI
import SwiftUI
import UIKit

/// Form content for choosing a cover image from a place search, previews, or the photo library.
struct HolidayCoverImageFormSection: View {
    @Binding var coverImageData: Data?
    /// When set, a map search pick fills these so the holiday world map can pin the trip at the cover city.
    var coverPlaceName: Binding<String>? = nil
    var coverLatitude: Binding<Double>? = nil
    var coverLongitude: Binding<Double>? = nil

    var headingTitle: String = String(localized: "cover.heading_title")
    var cityFieldTitle: String = String(localized: "planning.cover_city")
    var searchButtonTitle: String = String(localized: "planning.cover_search")
    var footerText: String = String(localized: "cover.default_footer")

    @State private var coverPhotoItem: PhotosPickerItem?
    @State private var coverSearchQuery = ""
    @State private var isGeneratingCoverFromPlace = false
    @State private var coverPlaceAlert: String?
    @State private var coverPickerChoices: [HolidayCoverChoice] = []
    @State private var coverPickerThumbnails: [UUID: UIImage] = [:]

    var body: some View {
        Section(headingTitle) {
            headingPreview
            TextField(cityFieldTitle, text: $coverSearchQuery, prompt: Text(String(localized: "cover.search")))
            HolidayMapPlaceSearchBlock(
                searchQuery: $coverSearchQuery,
                buttonTitle: searchButtonTitle,
                onPick: { candidate in
                    coverPlaceName?.wrappedValue = candidate.resolvedName
                    coverLatitude?.wrappedValue = candidate.coordinate.latitude
                    coverLongitude?.wrappedValue = candidate.coordinate.longitude
                    Task { await prepareCoverChoices(for: candidate) }
                },
                isDisabled: isGeneratingCoverFromPlace
            )
            if isGeneratingCoverFromPlace {
                HStack {
                    ProgressView()
                    Text(coverPickerChoices.isEmpty ? String(localized: "cover.finding_photos") : String(localized: "cover.loading_previews"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !coverPickerChoices.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(coverPickerChoices) { choice in
                        Button {
                            Task { await confirmCoverChoice(choice) }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    if let ui = coverPickerThumbnails[choice.id] {
                                        Image(uiImage: ui)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color(.tertiarySystemGroupedBackground))
                                            .overlay {
                                                ProgressView()
                                            }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                Text(choice.label)
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            PhotosPicker(selection: $coverPhotoItem, matching: .images) {
                Label(String(localized: "cover.choose_photo"), systemImage: "photo.badge.plus")
            }
            .disabled(isGeneratingCoverFromPlace)
            if coverImageData != nil {
                Button(role: .destructive) {
                    coverImageData = nil
                } label: {
                    Label(String(localized: "cover.remove_heading"), systemImage: "trash")
                }
            }
            Text(footerText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onChange(of: coverPhotoItem) { _, new in
            Task {
                guard let new else { return }
                await MainActor.run {
                    coverPickerChoices = []
                    coverPickerThumbnails = [:]
                }
                if let data = try? await new.loadTransferable(type: Data.self) {
                    await MainActor.run { coverImageData = data }
                }
            }
        }
        .alert(String(localized: "cover.alert"), isPresented: Binding(
            get: { coverPlaceAlert != nil },
            set: { if !$0 { coverPlaceAlert = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) { coverPlaceAlert = nil }
        } message: {
            Text(coverPlaceAlert ?? "")
        }
    }

    private var headingPreview: some View {
        HStack {
            Spacer()
            Group {
                if let data = coverImageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))
                        .overlay {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .frame(width: 200, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer()
        }
        .listRowBackground(Color.clear)
    }

    private func prepareCoverChoices(for candidate: HolidayPlaceCandidate) async {
        await MainActor.run {
            isGeneratingCoverFromPlace = true
            coverPickerChoices = []
            coverPickerThumbnails = [:]
        }
        do {
            let choices = try await HolidayPlaceSearch.coverImageChoices(for: candidate, limit: 6)
            await MainActor.run { coverPickerChoices = choices }
            await loadCoverPickerThumbnails(for: choices)
        } catch {
            await MainActor.run {
                coverPlaceAlert = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { isGeneratingCoverFromPlace = false }
    }

    private func loadCoverPickerThumbnails(for choices: [HolidayCoverChoice]) async {
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for choice in choices {
                group.addTask {
                    switch choice.kind {
                    case let .wikipedia(_, thumbnailURL):
                        do {
                            let data = try await HolidayWikipediaCoverImages.downloadImageData(from: thumbnailURL)
                            return (choice.id, UIImage(data: data))
                        } catch {
                            return (choice.id, nil)
                        }
                    case let .satellite(center, latDelta, lonDelta):
                        do {
                            let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
                            let data = try await HolidayTripCoverPlaceImage.satelliteJPEG(
                                center: center,
                                span: span,
                                pixelWidth: 360,
                                pixelHeight: 200
                            )
                            return (choice.id, UIImage(data: data))
                        } catch {
                            return (choice.id, nil)
                        }
                    }
                }
            }
            for await (id, image) in group {
                await MainActor.run {
                    if let image {
                        coverPickerThumbnails[id] = image
                    }
                }
            }
        }
    }

    private func confirmCoverChoice(_ choice: HolidayCoverChoice) async {
        await MainActor.run { isGeneratingCoverFromPlace = true }
        defer { Task { @MainActor in isGeneratingCoverFromPlace = false } }
        do {
            let data: Data
            switch choice.kind {
            case let .wikipedia(pageTitle, thumbnailURL):
                data = try await HolidayWikipediaCoverImages.fetchImageDataForCover(
                    pageTitle: pageTitle,
                    thumbnailURL: thumbnailURL
                )
            case let .satellite(center, latDelta, lonDelta):
                let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
                data = try await HolidayTripCoverPlaceImage.satelliteJPEG(
                    center: center,
                    span: span,
                    pixelWidth: 1600,
                    pixelHeight: 900
                )
            }
            await MainActor.run { coverImageData = data }
        } catch {
            await MainActor.run {
                coverPlaceAlert = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
