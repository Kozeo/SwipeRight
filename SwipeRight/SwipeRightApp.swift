//
//  SwipeRightApp.swift
//  SwipeRight
//
//  Created by Elliot Gaubert on 08/05/2025.
//

import SwiftUI

@main
struct SwipeRightApp: App {
    // Create our PhotoViewModel
    @State private var photoViewModel = PhotoViewModel()

    var body: some Scene {
        WindowGroup {
            PhotoBrowserView(model: photoViewModel)
                .preferredColorScheme(.light)
        }
    }
}
