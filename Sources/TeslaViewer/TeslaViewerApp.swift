//
//  TeslaViewerApp.swift
//  TeslaViewer
//

import SwiftUI
import AppKit

// Beim Start als reines SwiftPM-Executable muss die Aktivierungs-Policy
// explizit gesetzt werden, damit ein normales Fenster im Vordergrund
// erscheint (das übernimmt sonst die Info.plist eines App-Bundles).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct TeslaViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
