//
//  TheGomsonsApp.swift
//  TheGomsons
//
//  Created by Christian Gomnaes on 29/03/2026.
//

import SwiftData
import SwiftUI

@main
struct TheGomsonsApp: App {
    @UIApplicationDelegateAdaptor(GomsonsAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            TheGomsonsRootView()
        }
        .environmentObject(CloudDataManager.shared)
    }
}

/// Waits for the CloudKit-backed store to load before attaching SwiftData; see `CloudDataManager`.
private struct TheGomsonsRootView: View {
    @EnvironmentObject private var cloud: CloudDataManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var didAttemptMonthlyBackupThisSession = false

    var body: some View {
        Group {
            if let container = cloud.modelContainer {
                // Do **not** `.id(swiftDataStoreEpoch)` here — that remounted ContentView on every
                // CloudKit import and kicked users back to the landing screen.
                ContentView()
                    .modelContainer(container)
            } else if let message = cloud.storeLoadErrorMessage {
                ContentUnavailableView {
                    Label(String(localized: "sync.store_error_title"), systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button(String(localized: "sync.reload_local")) {
                        cloud.refreshFamilyDataFromStore()
                    }
                }
            } else {
                ProgressView(String(localized: "common.loading"))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Safe dual-stack reopen: only when leaving the UI (background). Tearing down
            // ModelContainer while foregrounded (active / debounced import) causes frequent crashes.
            if phase == .background {
                cloud.applyDeferredSwiftDataReloadIfNeeded()
            }
            if phase == .active {
                runMonthlyBackupIfNeeded()
            }
        }
        .onChange(of: cloud.modelContainer != nil) { _, ready in
            if ready {
                runMonthlyBackupIfNeeded()
            }
        }
    }

    private func runMonthlyBackupIfNeeded() {
        guard !didAttemptMonthlyBackupThisSession else { return }
        guard let container = cloud.modelContainer else { return }
        guard AppDataBackup.monthlyICloudBackupsEnabled, AppDataBackup.isMonthlyBackupDue else { return }
        didAttemptMonthlyBackupThisSession = true

        Task { @MainActor in
            // Brief delay so CloudKit / UI can settle after becoming active.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let context = ModelContext(container)
            if let url = AppDataBackup.performMonthlyBackupIfNeeded(modelContext: context) {
                print("[TheGomsons] Monthly iCloud backup saved: \(url.lastPathComponent)")
            }
        }
    }
}

/// Registers for remote notifications so `NSPersistentCloudKitContainer` can
/// receive silent pushes whenever records change in the **Public Database**.
final class GomsonsAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        Task {
            await FamilyCalendarNotifications.requestAuthorizationIfNeeded()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            CloudDataManager.shared.handleRemoteNotification(
                userInfo: userInfo,
                completion: completionHandler
            )
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Token handled by the system for CloudKit subscriptions.
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[TheGomsons] Remote notification registration failed: \(error.localizedDescription)")
    }
}
