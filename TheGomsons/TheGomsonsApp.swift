//
//  TheGomsonsApp.swift
//  TheGomsons
//
//  Created by Christian Gomnaes on 29/03/2026.
//

import SwiftUI
import SwiftData

@main
struct TheGomsonsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(CloudDataManager.shared.modelContainer)
    }
}
