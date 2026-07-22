//
//  CloudDataManager.swift
//  TheGomsons
//
//  CloudKit troubleshooting (Public DB + Core Data mirroring)
//  ───────────────────────────────────────────────────────────
//  Mirroring requires server-side **indexes** on every synced `CD_*` record type. This cannot be
//  fixed in Swift; the app will log errors until CloudKit Dashboard is updated.
//
//  Typical logs (each names one record type / field)—follow the **exact** field name + index kind in the log:
//    • Field '___modTime' is not marked **sortable** → **Sortable** on `___modTime` for that `CD_*` type.
//    • Field '___modTime' is not marked **queryable** → **Queryable** on `___modTime` for **that** record type in the
//      log (e.g. **CD_VacationIdea**, **CD_HolidayDestination**, **CD_FamilyEvent**, **CD_Property**,
//      **CD_HolidayTrip**, **CD_HolidayTripParticipant**—each `CD_*`
//      type needs its own indexes). Some types also need **Sortable** on `___modTime` if the log asks for it.
//    • Field 'recordName' is not marked queryable → **Queryable** on `recordName` (e.g. **CD_PropertyContractor**,
//      **CD_FamilyEvent**, **CD_HolidayChatMessage**).
//  Until fixed: CKError 12, mirroring never initializes, export/import loops.
//
//  **`NSCocoaErrorDomain` 4864** / `incomprehensible archive` (often with UTF-8 bytes in the log, e.g. readable
//  ASCII like `"Some sam…"`): Core Data tried to **keyed-unarchive** a blob that is **plain text or other
//  non-archive data**—usually a **bad or mistyped CloudKit record** (schema/field mismatch), **stale
//  Development data**, or damaged sync metadata—not something your SwiftData `String` properties fix by
//  themselves. **Deleting/reinstalling the app does not fix this:** the Public database still returns the
//  same records from iCloud. **Remediation:** [CloudKit Console](https://icloud.developer.apple.com) → your
//  container → **Public Database** → delete offending `CD_*` records (or **Reset Environment** for
//  **Development** only), then relaunch the app. Ensure record field types match the app model; **Production**
//  needs the same cleanup if bad data was deployed there (back up first).
//  Until fixed, mirroring may **retry and log heavily**, which can make **launch feel slow**—fixing server data
//  (or resetting Development) is what restores normal startup and stops the 4864 spam.
//
//  Proactive approach: for **every** `CD_*` type under **Public** → **Schema** → **Record Types**, add
//  **Queryable** on **`___modTime`** (required for mirroring queries), **Sortable** on **`___modTime`** if you
//  want fewer follow-up errors, and **Queryable** on **`recordName`** (and **`___recordID`** if logs mention it).
//
//  Fix (icloud.developer.apple.com → Container **iCloud.com.gomnaes.TheGomsons**):
//  1. **Development** or **Production** must match the build you run.
//  2. **Public Database** → **Schema** → **Record Types** → open the **`CD_*`** from the log. One type
//     (e.g. **`CD_PropertyContractor`**) can surface **both** `recordName` and `___modTime` errors in
//     sequence—add **both** indexes on that type.
//  3. **Indexes** / **Metadata Indexes**: match the log—**`recordName`** → **Queryable**; **`___modTime`** →
//     **Sortable** and/or **Queryable** as the error text specifies (add both if mirroring still complains).
//  4. Save, **Deploy Schema** for Production when shipping.
//
//  Other console noise (not fixable in app code):
//  • `NSKeyedUnarchiveFromData` / deprecation — comes from **Core Data / system frameworks** (not your Swift);
//    Apple may silence it in a future OS. Ignore unless you see data corruption alongside it.
//  • `updateTaskRequest` / `com.apple.coredata.cloudkit.activity.export` / `BGSystemTaskSchedulerErrorDomain` —
//    Core Data’s background export scheduling. Logs like “already running/updated”, “pre-running”, or
//    “updateTaskRequest failed” with **Code=3** (`notPermitted` / null description) are common—Simulator,
//    overlapping requests, or the system refusing a BG task update. **Not** your app logic; ignore unless
//    mirroring itself fails (`CKError` 12 / CloudKit index issues).
//  • `Failed to clone external data reference` / `_EXTERNAL_DATA` / `.interim` — Core Data’s **external storage**
//    (`@Attribute(.externalStorage)` on image blobs) points at a **missing file** (crash, partial sync, or copy).
//    **Delete the app** and reinstall to wipe `Application Support/TheGomsons/.TheGomsons_SUPPORT/_EXTERNAL_DATA`;
//    then let CloudKit re-import. Not fixed by Swift-only code paths.
//  • `dasd` **BUG IN CLIENT**: `com.apple.coredata.cloudkit.activity.import` … **was asked to run but never started** —
//    the system scheduled a CloudKit **import** for Core Data but did not run it (or cancelled it immediately).
//    Often appears with **stressed scheduling**, **Low Power Mode**, a **stuck mirroring state**, or after
//    **schema/data errors** (see `CKError` 12 / 4864 above). Try: force-quit the app, reopen, leave it
//    **foreground** a minute; toggle Low Power off; **delete app → restart device → reinstall** if imports stay
//    stuck. If it persists with a **clean install**, focus on **server schema + bad records** (Console / indexes),
//    not only the device.
//  • `WAL checkpoint` (debug) — SQLite write-ahead log maintenance; normal when Core Data saves.
//  • `Debug session ended with code 9: killed` — debugger or system stopped the process, not necessarily an app bug.
//  Fixing CloudKit indexes stops the real sync failure (`CKError` 12 / mirroring not initialized).
//
//  `initializeCloudKitSchema` (DEBUG only, below) publishes types; it does **not** add CloudKit
//  Dashboard indexes. Missing indexes must be fixed on the server.
//
//  **Everyone should see everyone’s data (one shared family pool).** The store uses CloudKit’s
//  **Public** database (`databaseScope = .public`). There is no per-user filter in app code.
//  If each person only sees their own entries, mirroring is not merging remote records—usually:
//  • Missing **Queryable/Sortable** indexes on `CD_*` types (CKError 12 in Xcode).
//  • **Development** vs **Production** mismatch across devices.
//  • **CloudKit Console** → container → **Public Database** → **Security** / record-type permissions:
//    ensure `CD_*` types are readable by **Authenticated** or **World**, not restricted so only the
//    creator can read (otherwise other Apple IDs never import those records).
//  • iCloud not signed in on a device.
//
//  ── CloudKit Console walkthrough (indexes + shared reads) ─────────────────────
//  1. Open https://icloud.developer.apple.com → **Containers** → **iCloud.com.gomnaes.TheGomsons**
//     → **CloudKit Database** (or Database app) → select **Public Database** (not Private).
//  2. Pick **Development** or **Production** to match the build on every device (this project’s
//     entitlement pins Xcode + TestFlight / App Store to **Production**).
//  3. **Schema** → **Record Types**: after a DEBUG device run, `CD_*` types appear. Names match entities
//     (prefix `CD_`). For this app, expect at least:
//     `CD_Asset`, `CD_FamilyEvent`, `CD_FamilyGroupPhoto`, `CD_FamilyPerson`, `CD_HolidayChatMessage`, `CD_HolidayDestination`,
//     `CD_HolidayTrip`, `CD_HolidayTripParticipant`, `CD_InventoryItem`, `CD_InventoryItemLink`,
//     `CD_InventoryItemDocument`, `CD_Location`, `CD_Property`,
//     `CD_PropertyContact`, `CD_PropertyContractor`, `CD_PropertyEmergencyLine`, `CD_PropertyServiceProvider`,
//     `CD_Recipe`, `CD_PropertyMaintenanceEntry`, `CD_Subscription`, `CD_VacationIdea`
//     If the list differs, use whatever appears in Console as the source of truth.
//  4. Open **each** `CD_*` type → **Indexes** / **Metadata Indexes** (wording varies by Console version):
//     add **Queryable** on **`___modTime`**; add **Sortable** on **`___modTime`** if Xcode still complains;
//     add **Queryable** on **`recordName`** (and **`___recordID`** if the log names them).
//  5. **Security** / permissions for **Public**: ensure records are not “creator read only”—other
//     signed-in users must be allowed to **read** others’ `CD_*` rows (otherwise each device only sees
//     what it created). Exact UI depends on Console; look for record-type or role read rules.
//  6. **Production** only: **Deploy Schema** after editing indexes.
//  7. Relaunch the app on each device and watch Xcode for lingering `CKError` / index messages.
//
//  **If your deployed schema matches** `GRANT READ TO "_world"` **and** `___modTime` **Queryable+Sortable**
//  on each `CD_*` type: imports can see **everyone’s** rows.
//
//  **Multiple people editing the same rows (shared writes):** With only `GRANT WRITE TO "_creator"`,
//  CloudKit rejects updates from anyone except the Apple ID that created that record—mirroring export
//  fails with permission errors when another family member edits. To allow **any signed-in iCloud user**
//  who uses the app to update existing `CD_*` rows, grant **Write** to the **Authenticated** role
//  (`_icloud`) for each record type you want collaboratively editable:
//  • [CloudKit Console](https://icloud.developer.apple.com) → **Public Database** → **Schema** →
//    **Record Types** → open a **`CD_*`** type → **Security** / **Roles** (wording varies) → ensure
//    **Authenticated** / **`_icloud`** includes **Write** (not only **Create**). Repeat for every
//    **`CD_*`** type (and **`Users`** if you mirror it). **Deploy Schema** to Production when ready.
//  • If you use the **schema text** view, that corresponds to adding **`GRANT WRITE TO "_icloud"`**
//    alongside the existing **`GRANT WRITE TO "_creator"`** line—**Authenticated** can then update
//    records created by others. A checked-in copy lives at **`CloudKit/PublicSchema.ckdb`** (import via
//    Console or `xcrun cktool import-schema`). Tradeoff: any iCloud-authenticated client of your
//    container could write to those types (same as “everyone with the app”), not literally “creator only.”
//    For stricter, invitation-based sharing, use **CKShare** / Shared database instead of broad public writes.
//  The **`Users`** record type (non-`CD_`) is separate metadata—add **Queryable** on `___modTime` there
//  if Xcode logs ask for it.

import CloudKit
import Combine
import CoreData
import SwiftData
import UIKit
import _SwiftData_CoreData

/// Central place for SwiftData + CloudKit **Public Database** configuration.
///
/// All four family members sync to the same public data pool—no CKShare
/// invitations needed.  `NSPersistentCloudKitContainer` handles export,
/// import, and `CKQuerySubscription` creation automatically for every entity.
///
/// **Dual stack:** CloudKit mirroring uses `NSPersistentCloudKitContainer`; the UI uses
/// SwiftData on the **same store URL** with `cloudKitDatabase: .none`. After a successful
/// CloudKit **import**, SwiftData’s coordinator can stay stale—so we rebuild the
/// `ModelContainer` (debounced) so `@Query` picks up other users’ rows.
@MainActor
final class CloudDataManager: ObservableObject {
    static let shared = CloudDataManager()

    /// Merges SwiftData’s underlying `NSManagedObjectContext` saves into the CloudKit stack’s `viewContext`.
    private var siblingContextSaveObserver: NSObjectProtocol?
    private var cloudKitEventObserver: NSObjectProtocol?
    private var swiftDataReloadTask: Task<Void, Never>?
    private var isReloadingSwiftData = false

    static let cloudKitContainerIdentifier = "iCloud.com.gomnaes.TheGomsons"

    /// When Info.plist `CloudKitUsesProductionEnvironment` is true (keep in sync with the Production
    /// `com.apple.developer.icloud-container-environment` entitlement), skip `initializeCloudKitSchema`.
    /// That API creates placeholder `CD_FAKE_*` records; if Production’s deployed schema is missing fields,
    /// those writes fail with CKError 12/2006, mirroring never initializes, and other users cannot sync.
    /// Production schema must be deployed via CloudKit Console (or `cktool import-schema --environment production`).
    private static var iCloudContainerUsesProductionEntitlement: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CloudKitUsesProductionEnvironment") as? Bool == true
    }

    private static var storeURL: URL {
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
            InventoryItemLink.self,
            InventoryItemDocument.self,
            Asset.self,
            Location.self,
            Recipe.self,
            PropertyMaintenanceEntry.self,
            FamilyEvent.self,
            HolidayTrip.self,
            HolidayDestination.self,
            HolidayTripParticipant.self,
            VacationIdea.self,
            HolidayChatMessage.self,
            PropertyContractor.self,
            PropertyServiceProvider.self,
            FamilyPerson.self,
            FamilyGroupPhoto.self,
            Subscription.self,
        ])
    }

    /// Set only after `NSPersistentCloudKitContainer` finishes loading the store. Opening SwiftData on the same file before that breaks CloudKit export/import.
    @Published private(set) var modelContainer: ModelContainer?

    /// Bumped when SwiftData is reopened after a CloudKit import (views can `.id` this if needed).
    @Published private(set) var swiftDataStoreEpoch = 0

    /// Latest iCloud account status for the app’s CloudKit container (`nil` until first query finishes).
    @Published private(set) var cloudKitAccountStatus: CKAccountStatus?

    let persistentCloudKitContainer: NSPersistentCloudKitContainer

    /// Shown in Data backup → Family sync. The target uses `com.apple.developer.icloud-container-environment` = Production so **Xcode runs and TestFlight/App Store share the same CloudKit data pool**.
    static var syncBuildEnvironmentFootnote: String {
        String(localized: "sync.env_footnote")
    }

    /// Shown in Data backup → Family sync. Explains shared intent and “siloed” troubleshooting.
    static var sharedFamilyDataFootnote: String {
        String(localized: "sync.family_footnote")
    }

    private init() {
        let schema = Self.gomsonsSchema
        let storeURL = Self.storeURL

        guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(for: schema, mergedWith: nil) else {
            fatalError("Could not build NSManagedObjectModel for SwiftData schema.")
        }

        // ── Core Data container → CloudKit **Public** database ──
        let cloudContainer = NSPersistentCloudKitContainer(name: "TheGomsons", managedObjectModel: managedObjectModel)

        let storeDescription = NSPersistentStoreDescription(url: storeURL)
        let ckOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerIdentifier)
        ckOptions.databaseScope = .public
        storeDescription.cloudKitContainerOptions = ckOptions
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        cloudContainer.persistentStoreDescriptions = [storeDescription]

        persistentCloudKitContainer = cloudContainer

        let cloudViewContext = cloudContainer.viewContext
        siblingContextSaveObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSManagedObjectContextDidSave,
            object: nil,
            queue: nil
        ) { notification in
            guard let saved = notification.object as? NSManagedObjectContext,
                  saved !== cloudViewContext
            else { return }
            cloudViewContext.perform {
                cloudViewContext.mergeChanges(fromContextDidSave: notification)
            }
        }

        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: cloudContainer,
            queue: nil
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event
            else { return }

            let typeLabel: String
            switch event.type {
            case .setup: typeLabel = "setup"
            case .import: typeLabel = "import"
            case .export: typeLabel = "export"
            @unknown default: typeLabel = "other"
            }

            if let error = event.error {
                print("[TheGomsons] CloudKit \(typeLabel) failed: \(error.localizedDescription)")
                return
            }
            guard event.endDate != nil else { return }
            print("[TheGomsons] CloudKit \(typeLabel) succeeded")

            if event.type == .import {
                Task { @MainActor in
                    CloudDataManager.shared.scheduleSwiftDataReload(reason: "cloudkit-import")
                }
            }
        }

        // Note: do not reload SwiftData on every `NSPersistentStoreRemoteChange` — that fires
        // very often (including around local exports) and caused jarring UI resets. Import
        // success above is the reliable signal that Public DB rows need a SwiftData reopen.

        cloudContainer.loadPersistentStores { _, error in
            if let error {
                fatalError("CloudKit persistent store failed to load: \(error)")
            }
            #if DEBUG
            if !Self.iCloudContainerUsesProductionEntitlement {
                do {
                    try cloudContainer.initializeCloudKitSchema(options: [])
                } catch {
                    print("[TheGomsons] initializeCloudKitSchema (DEBUG): \(error.localizedDescription)")
                }
            }
            #endif

            Task { @MainActor in
                do {
                    try self.openSwiftDataContainer(schema: schema, storeURL: storeURL)
                } catch {
                    fatalError("Could not create ModelContainer (same store as CloudKit stack): \(error)")
                }
                self.refreshCloudKitAccountStatus()
            }
        }

        cloudContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        cloudContainer.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Rebuild SwiftData against the shared store so `@Query` sees rows CloudKit just imported.
    private func openSwiftDataContainer(schema: Schema, storeURL: URL) throws {
        let modelConfiguration = ModelConfiguration(
            nil,
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContainer = container
        swiftDataStoreEpoch += 1
    }

    /// Debounced reopen after a CloudKit import (batches multi-record imports).
    func scheduleSwiftDataReload(reason: String) {
        swiftDataReloadTask?.cancel()
        swiftDataReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            reloadSwiftDataContainer(reason: reason)
        }
    }

    /// Manual pull from Data backup / troubleshooting — rebuilds SwiftData against the shared store.
    func refreshFamilyDataFromStore() {
        scheduleSwiftDataReload(reason: "manual-refresh")
    }

    private func reloadSwiftDataContainer(reason: String) {
        guard !isReloadingSwiftData else { return }
        guard modelContainer != nil else { return }
        isReloadingSwiftData = true
        defer { isReloadingSwiftData = false }
        do {
            try openSwiftDataContainer(schema: Self.gomsonsSchema, storeURL: Self.storeURL)
            print("[TheGomsons] Reloaded SwiftData after \(reason) (epoch \(swiftDataStoreEpoch))")
        } catch {
            print("[TheGomsons] SwiftData reload failed (\(reason)): \(error.localizedDescription)")
        }
    }

    // MARK: - Remote notification handling

    /// Call once at launch (typically from AppDelegate `didFinishLaunchingWithOptions`).
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Forward incoming silent pushes so NSPersistentCloudKitContainer
    /// fetches fresh records from the public database.
    func handleRemoteNotification(
        userInfo: [AnyHashable: Any],
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Public-database subscription payloads often omit `subscriptionOwnerUserRecordID` and
        // sometimes `subscriptionID`; requiring them caused valid pushes to report `.noData` and
        // weakened background import. Any CloudKit notification is enough to proceed.
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completion(.noData)
            return
        }
        // Run completion on the view context’s queue so mirroring can process the push first.
        persistentCloudKitContainer.viewContext.perform {
            completion(.newData)
        }
    }

    /// Refreshes `cloudKitAccountStatus` and logs when iCloud isn’t available (sync cannot work).
    func refreshCloudKitAccountStatus() {
        cloudKitContainer.accountStatus { [weak self] status, error in
            let err = error.map { " \($0.localizedDescription)" } ?? ""
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cloudKitAccountStatus = status
                if status != .available {
                    print("[TheGomsons] CloudKit: iCloud not available for sync (status \(status.rawValue)).\(err) Shared data needs an iCloud account signed in.")
                }
            }
        }
    }

    func cloudKitAccountStatusDescription(for status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return String(localized: "icloud.status.available")
        case .noAccount:
            return String(localized: "icloud.status.no_account")
        case .restricted:
            return String(localized: "icloud.status.restricted")
        case .couldNotDetermine:
            return String(localized: "icloud.status.unknown")
        case .temporarilyUnavailable:
            return String(localized: "icloud.status.temp")
        @unknown default:
            return String(localized: "icloud.status.unknown_default")
        }
    }

    var cloudKitContainer: CKContainer {
        CKContainer(identifier: Self.cloudKitContainerIdentifier)
    }
}
