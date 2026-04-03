//
//  TeslaViewerApp.swift
//  TeslaViewer
//

import SwiftUI

@main
struct TeslaViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .help) {}
        }
    }
}
