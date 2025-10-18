//
//  KineTrackApp.swift
//  KineTrack
//
//  Created by Zeedan on 10/18/25.
//

import SwiftUI
import CoreData

@main
struct KineTrackApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
