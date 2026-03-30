//
//  CloudDataManager.swift
//  TheGomsons
//

import CloudKit
import CoreData
import SwiftData
import UIKit
import _SwiftData_CoreData

/// Central place for SwiftData + CloudKit configuration and family-share helpers (`UIActivityViewController` + `CKShare`).
@MainActor
final class CloudDataManager {
    static let shared = CloudDataManager()

    static let cloudKitContainerIdentifier = "iCloud.com.gomnaes.TheGomsons"

    static var storeURL: URL {
        let folder = URL.applicationSupportDirectory.appendingPathComponent("TheGomsons", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("TheGomsons.store", isDirectory: false)
    }

    static var gomsonsSchema: Schema {
        Schema([
            Property.self,
            PropertyContact.self,
            PropertyEmergencyLine.self,
            InventoryItem.self,
            Asset.self,
            Location.self,
            Recipe.self,
            FamilyEvent.self,
            HolidayTrip.self,
            HolidayDestination.self,
            HolidayTripParticipant.self,
            VacationIdea.self,
            HolidayChatMessage.self,
            PropertyContractor.self,
            PropertyServiceProvider.self,
        ])
    }

    let modelContainer: ModelContainer
    let persistentCloudKitContainer: NSPersistentCloudKitContainer

    private init() {
        let schema = Self.gomsonsSchema

        guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(for: schema, mergedWith: nil) else {
            fatalError("Could not build NSManagedObjectModel for SwiftData schema.")
        }

        let cloudContainer = NSPersistentCloudKitContainer(name: "TheGomsons", managedObjectModel: managedObjectModel)
        let storeDescription = NSPersistentStoreDescription(url: Self.storeURL)
        Self.applyPrivateCloudKitOptions(to: storeDescription)
        cloudContainer.persistentStoreDescriptions = [storeDescription]

        cloudContainer.loadPersistentStores { _, error in
            if let error {
                fatalError("CloudKit persistent store failed to load: \(error)")
            }
        }

        cloudContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        cloudContainer.viewContext.automaticallyMergesChangesFromParent = true

        persistentCloudKitContainer = cloudContainer

        let modelConfiguration = ModelConfiguration(
            nil,
            schema: schema,
            url: Self.storeURL,
            cloudKitDatabase: .automatic
        )

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer (same store as CloudKit stack): \(error)")
        }
    }

    var managedObjectModel: NSManagedObjectModel {
        guard let mom = NSManagedObjectModel.makeManagedObjectModel(for: Self.gomsonsSchema, mergedWith: nil) else {
            fatalError("Could not build NSManagedObjectModel for SwiftData schema.")
        }
        return mom
    }

    func makePersistentCloudKitContainer() -> NSPersistentCloudKitContainer {
        NSPersistentCloudKitContainer(name: "TheGomsons", managedObjectModel: managedObjectModel)
    }

    static func applyPrivateCloudKitOptions(to description: NSPersistentStoreDescription) {
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
        options.databaseScope = .private
        description.cloudKitContainerOptions = options
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
    }

    /// Managed objects to attach to a new or existing family share (prefers properties, then any persisted row).
    func managedObjectsForSharing() -> [NSManagedObject] {
        let context = persistentCloudKitContainer.viewContext
        let coordinator = context.persistentStoreCoordinator
        let model = coordinator?.managedObjectModel
        let entityNames = model?.entities.compactMap(\.name) ?? []

        let preferredOrder = [
            "Property", "CD_Property",
            "FamilyEvent", "CD_FamilyEvent",
            "Asset", "CD_Asset",
            "PropertyContact", "CD_PropertyContact",
        ]
        for name in preferredOrder where entityNames.contains(name) {
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.fetchLimit = 25
            if let rows = try? context.fetch(request), !rows.isEmpty {
                return rows
            }
        }

        for name in entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.fetchLimit = 1
            if let row = try? context.fetch(request).first {
                return [row]
            }
        }

        return []
    }

    /// Family iCloud sharing using the iOS 17+ share-sheet path (`NSItemProvider.registerCKShare`), not the deprecated `UICloudSharingController(preparationHandler:)`.
    func makeFamilyShareActivityViewController() -> UIActivityViewController {
        let ckContainer = cloudKitContainer
        let objectIDs = managedObjectsForSharing().map(\.objectID)

        let provider = NSItemProvider()
        provider.registerCKShare(container: ckContainer, allowedSharingOptions: .standard) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare, Error>) in
                Task { @MainActor in
                    let pc = CloudDataManager.shared.persistentCloudKitContainer
                    let context = pc.viewContext
                    let resolved: [NSManagedObject] = objectIDs.compactMap { id in
                        try? context.existingObject(with: id)
                    }
                    guard !resolved.isEmpty else {
                        continuation.resume(
                            throwing: NSError(
                                domain: "TheGomsons",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "Could not create a CloudKit share. Add some data (for example a property) and try again.",
                                ]
                            )
                        )
                        return
                    }
                    pc.share(resolved, to: nil) { _, share, _, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        guard let share else {
                            continuation.resume(
                                throwing: NSError(
                                    domain: "TheGomsons",
                                    code: 1,
                                    userInfo: [
                                        NSLocalizedDescriptionKey:
                                            "Could not create a CloudKit share. Add some data (for example a property) and try again.",
                                    ]
                                )
                            )
                            return
                        }
                        continuation.resume(returning: share)
                    }
                }
            }
        }

        let configuration = UIActivityItemsConfiguration(itemProviders: [provider])
        configuration.metadataProvider = { key in
            if key == .title {
                "The Gomsons" as NSString
            } else {
                nil
            }
        }
        configuration.supportedInteractions = [.share]

        return UIActivityViewController(activityItemsConfiguration: configuration)
    }

    var cloudKitContainer: CKContainer {
        CKContainer(identifier: Self.cloudKitContainerIdentifier)
    }
}
