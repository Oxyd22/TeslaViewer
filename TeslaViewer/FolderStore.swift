//
//  FolderStore.swift
//  TeslaViewer
//
//  Verwaltet die Ordnerauswahl und merkt sich den zuletzt geöffneten
//  TeslaCam-Ordner über App-Neustarts hinweg (Security-Scoped Bookmark).
//

import SwiftUI

@MainActor
@Observable
final class FolderStore {
    private static let bookmarkKey = "TeslaCamFolderBookmark"

    private(set) var currentURL: URL?
    private var isAccessingSecurityScope = false

    init() {
        resolveStoredBookmark()
    }

    /// Zeigt den Ordnerauswahl-Dialog und merkt den gewählten Ordner dauerhaft.
    func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "TeslaCam-Ordner oder SentryClips-Ordner auswählen"
        panel.prompt = "Öffnen"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        setCurrent(url, storeBookmark: true)
        return url
    }

    private func resolveStoredBookmark() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        setCurrent(url, storeBookmark: isStale)
    }

    private func setCurrent(_ url: URL, storeBookmark: Bool) {
        stopAccessing()
        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
        currentURL = url

        guard storeBookmark else { return }
        if let data = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
    }

    private func stopAccessing() {
        guard isAccessingSecurityScope else { return }
        currentURL?.stopAccessingSecurityScopedResource()
        isAccessingSecurityScope = false
    }
}
