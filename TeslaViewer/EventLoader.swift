//
//  EventLoader.swift
//  TeslaViewer
//
//  Lädt und parst TeslaCam-Ordnerstrukturen zu SentryEvent-Objekten.
//

import Foundation

enum EventLoader {
    /// Länge des Timestamp-Prefix "YYYY-MM-DD_HH-mm-ss" in Tesla-Dateinamen
    private nonisolated static let timestampPrefixLength = 19

    private nonisolated static let filenameFormat: Date.FormatString =
        "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)_\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))-\(minute: .twoDigits)-\(second: .twoDigits)"

    private nonisolated static let jsonTimestampFormat: Date.FormatString =
        "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)"

    nonisolated struct ScanResult: Sendable {
        let events: [SentryEvent]
        /// Ob ein "EncryptedClips"-Ordner gefunden und übersprungen wurde.
        let skippedEncrypted: Bool
    }

    /// Scannt eine TeslaCam-Ordnerstruktur. Unterstützt: TeslaCam-Root (mit SentryClips
    /// und/oder SavedClips), einen direkten SentryClips-/SavedClips-Ordner, einen einzelnen
    /// Ereignisordner, oder einen Ordner mit Ereignisunterordnern.
    @concurrent
    nonisolated static func scan(root rootURL: URL) async -> ScanResult {
        let fm = FileManager.default
        let name = rootURL.lastPathComponent

        if name == "SentryClips" {
            return ScanResult(events: events(in: rootURL, source: .sentry), skippedEncrypted: false)
        }
        if name == "SavedClips" {
            return ScanResult(events: events(in: rootURL, source: .saved), skippedEncrypted: false)
        }
        if let date = parseFolderDate(name) {
            let event = parseEvent(at: rootURL, eventTimestamp: date, source: .sentry)
            return ScanResult(events: event.map { [$0] } ?? [], skippedEncrypted: false)
        }

        var sourceRoots: [(URL, ClipSource)] = []
        let sentryDir = rootURL.appendingPathComponent("SentryClips")
        if fm.fileExists(atPath: sentryDir.path) {
            sourceRoots.append((sentryDir, .sentry))
        }
        let savedDir = rootURL.appendingPathComponent("SavedClips")
        if fm.fileExists(atPath: savedDir.path) {
            sourceRoots.append((savedDir, .saved))
        }
        let skippedEncrypted = fm.fileExists(
            atPath: rootURL.appendingPathComponent("EncryptedClips").path
        )

        if sourceRoots.isEmpty {
            // Kein bekannter Unterordner: den Ordner selbst nach Ereignisunterordnern durchsuchen.
            sourceRoots.append((rootURL, .sentry))
        }

        var allEvents: [SentryEvent] = []
        for (dir, source) in sourceRoots {
            allEvents.append(contentsOf: events(in: dir, source: source))
        }
        allEvents.sort { $0.eventTimestamp > $1.eventTimestamp }
        return ScanResult(events: allEvents, skippedEncrypted: skippedEncrypted)
    }

    private nonisolated static func events(in directory: URL, source: ClipSource) -> [SentryEvent] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ))?.filter { $0.hasDirectoryPath } ?? []

        return folders.compactMap { folder in
            guard let date = parseFolderDate(folder.lastPathComponent) else { return nil }
            return parseEvent(at: folder, eventTimestamp: date, source: source)
        }
    }

    private nonisolated static func parseFolderDate(_ name: String) -> Date? {
        try? Date(name, strategy: .fixed(format: filenameFormat, timeZone: .current))
    }

    private nonisolated static func parseEvent(
        at folderURL: URL, eventTimestamp: Date, source: ClipSource
    ) -> SentryEvent? {
        struct Metadata: Decodable {
            var timestamp: String?
            var city: String?
            var street: String?
            var reason: String?
        }

        let jsonURL = folderURL.appendingPathComponent("event.json")
        let meta: Metadata? = if let data = try? Data(contentsOf: jsonURL) {
            try? JSONDecoder().decode(Metadata.self, from: data)
        } else {
            nil
        }

        let triggerTimestamp = meta?.timestamp.flatMap {
            try? Date($0, strategy: .fixed(format: jsonTimestampFormat, timeZone: .current))
        }

        let thumb = folderURL.appendingPathComponent("thumb.png")
        let thumbnailURL = FileManager.default.fileExists(atPath: thumb.path) ? thumb : nil

        // MP4-Dateien nach Timestamp-Prefix gruppieren
        let mp4s = (try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ))?.filter { $0.pathExtension.lowercased() == "mp4" } ?? []

        // Dateiname-Format: YYYY-MM-DD_HH-MM-SS-kameraname.mp4
        // Timestamp ist immer 19 Zeichen, dann "-", dann Kameraname
        var groups: [String: [URL]] = [:]
        for url in mp4s {
            let stem = url.deletingPathExtension().lastPathComponent
            guard stem.count > timestampPrefixLength else { continue }
            let prefix = String(stem.prefix(timestampPrefixLength))
            groups[prefix, default: []].append(url)
        }

        let clips = groups.compactMap { prefix, urls -> SentryClip? in
            guard let clipDate = parseFolderDate(prefix) else { return nil }
            var cameraURLs: [String: URL] = [:]
            for url in urls {
                let stem = url.deletingPathExtension().lastPathComponent
                // Kameraname beginnt nach den 19 Timestamp-Zeichen + dem Trennzeichen "-"
                let separatorOffset = timestampPrefixLength + 1
                if stem.count > separatorOffset {
                    cameraURLs[String(stem.dropFirst(separatorOffset))] = url
                }
            }
            return SentryClip(clipTimestamp: clipDate, cameraURLs: cameraURLs)
        }.sorted { $0.clipTimestamp < $1.clipTimestamp }

        let street = meta?.street
        return SentryEvent(
            folderURL: folderURL,
            eventTimestamp: eventTimestamp,
            triggerTimestamp: triggerTimestamp,
            city: meta?.city,
            street: (street?.isEmpty ?? true) ? nil : street,
            reason: meta?.reason,
            thumbnailURL: thumbnailURL,
            source: source,
            clips: clips
        )
    }
}
