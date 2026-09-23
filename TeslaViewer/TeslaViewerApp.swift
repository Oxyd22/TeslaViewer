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
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .help) {}
            CommandGroup(after: .newItem) {
                Divider()
                OpenFolderCommand()
                RevealInFinderCommand()
            }
            CommandMenu("Wiedergabe") {
                TogglePlaybackCommand()
                Divider()
                StepBackwardCommand()
                StepForwardCommand()
                JumpToTriggerCommand()
                Divider()
                ExitFocusCommand()
            }
        }
    }
}

// MARK: - Menübefehle

/// Jeder Befehl liest seine eigene fokussierte Aktion und deaktiviert sich selbst,
/// wenn kein Ereignis geöffnet ist bzw. die Aktion nicht verfügbar ist.

private struct OpenFolderCommand: View {
    @FocusedValue(\.openFolderAction) private var action: (() -> Void)?

    var body: some View {
        Button("Ordner öffnen…") { action?() }
            .keyboardShortcut("o", modifiers: .command)
    }
}

private struct RevealInFinderCommand: View {
    @FocusedValue(\.playbackActions) private var actions: PlaybackActions?

    var body: some View {
        Button("Im Finder zeigen") { actions?.revealInFinder() }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(actions == nil)
    }
}

private struct TogglePlaybackCommand: View {
    @FocusedValue(\.playbackActions) private var actions: PlaybackActions?

    var body: some View {
        Button("Abspielen/Pause") { actions?.togglePlayback() }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(actions == nil)
    }
}

private struct StepBackwardCommand: View {
    @FocusedValue(\.playbackActions) private var actions: PlaybackActions?

    var body: some View {
        Button("1 Sekunde zurück") { actions?.stepBackward() }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(actions == nil)
    }
}

private struct StepForwardCommand: View {
    @FocusedValue(\.playbackActions) private var actions: PlaybackActions?

    var body: some View {
        Button("1 Sekunde vor") { actions?.stepForward() }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(actions == nil)
    }
}

private struct JumpToTriggerCommand: View {
    @FocusedValue(\.playbackActions) private var actions: PlaybackActions?

    var body: some View {
        Button("Zum Ereignis springen") { actions?.jumpToTrigger?() }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(actions?.jumpToTrigger == nil)
    }
}

private struct ExitFocusCommand: View {
    @FocusedValue(\.playbackActions) private var actions: PlaybackActions?

    var body: some View {
        Button("Kamera-Fokus beenden") { actions?.exitFocus?() }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(actions?.exitFocus == nil)
    }
}
