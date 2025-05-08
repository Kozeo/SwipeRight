//
//  SwipeRightApp.swift
//  SwipeRight
//
//  Created by Elliot Gaubert on 08/05/2025.
//

import SwiftUI
import SwiftData

@main
struct SwipeRightApp: App {
    // Create our PhotoViewModel
    @State private var photoViewModel = PhotoViewModel()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            PhotoBrowserView(model: photoViewModel)
        }
        .modelContainer(sharedModelContainer)
    }
}
