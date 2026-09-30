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

    nonisolated static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Öffentliche API

    /// Lädt Ereignisse aus allen drei Quellen (Sentry, Gespeichert, Letzte),
    /// soweit die jeweiligen Ordner existieren.
    nonisolated static func loadAll(from rootURL: URL) -> [SentryEvent] {
        let base = resolveBase(rootURL)
        return ClipSource.allCases.flatMap { loadEvents(base: base, source: $0) }
    }

    /// Rückwärtskompatibel: lädt nur die Sentry-Clips (wie zuvor).
    nonisolated static func loadEvents(from rootURL: URL) -> [SentryEvent] {
        loadEvents(base: resolveBase(rootURL), source: .sentry)
    }

    // MARK: - Ordner-Auflösung

    /// Ermittelt das Verzeichnis, das die Quell-Ordner (SentryClips/SavedClips/
    /// RecentClips) enthält. Akzeptiert: USB-Root (mit `TeslaCam`), den
    /// `TeslaCam`-Ordner selbst, oder direkt einen der Quell-Ordner.
    nonisolated static func resolveBase(_ rootURL: URL) -> URL {
        let fm = FileManager.default
        let name = rootURL.lastPathComponent

        // Direkt auf einen Quell-Ordner gezeigt → dessen Elternverzeichnis.
        if ClipSource.allCases.contains(where: { $0.folderName == name }) {
            return rootURL.deletingLastPathComponent()
        }
        // Enthält der Root einen TeslaCam-Unterordner? → diesen verwenden.
        let teslaCam = rootURL.appendingPathComponent("TeslaCam")
        if fm.fileExists(atPath: teslaCam.path) {
            return teslaCam
        }
        // Sonst Root unverändert (z.B. der TeslaCam-Ordner selbst).
        return rootURL
    }

    // MARK: - Laden je Quelle

    nonisolated static func loadEvents(base: URL, source: ClipSource) -> [SentryEvent] {
        let sourceURL = base.appendingPathComponent(source.folderName)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return [] }

        switch source {
        case .sentry, .saved:
            return loadEventFolders(at: sourceURL, source: source)
        case .recent:
            return loadFlatBuffer(at: sourceURL, source: source)
        }
    }

    /// Quellen mit Ereignis-Unterordnern (`YYYY-MM-DD_HH-mm-ss/`).
    private nonisolated static func loadEventFolders(at sourceURL: URL, source: ClipSource) -> [SentryEvent] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ))?.filter { $0.hasDirectoryPath } ?? []

        return folders
            .compactMap { parseEvent(at: $0, source: source) }
            .sorted { $0.eventTimestamp > $1.eventTimestamp }
    }

    /// `RecentClips` ist ein flacher Ordner ohne `event.json` — der laufende
    /// Dashcam-Puffer. Alle Minuten-Segmente werden zu einem Ereignis gebündelt.
    private nonisolated static func loadFlatBuffer(at sourceURL: URL, source: ClipSource) -> [SentryEvent] {
        let clips = parseClips(in: sourceURL)
        guard let first = clips.first else { return [] }

        let thumb = sourceURL.appendingPathComponent("thumb.png")
        let thumbnailURL = FileManager.default.fileExists(atPath: thumb.path) ? thumb : nil

        return [SentryEvent(
            folderURL: sourceURL,
            eventTimestamp: first.clipTimestamp,
            city: nil,
            reason: "",
            thumbnailURL: thumbnailURL,
            clips: clips,
            source: source,
            latitude: nil,
            longitude: nil
        )]
    }

    // MARK: - Parsing

    nonisolated static func parseEvent(at folderURL: URL, source: ClipSource = .sentry) -> SentryEvent? {
        let name = folderURL.lastPathComponent
        guard let date = dateFormatter.date(from: name) else { return nil }

        // event.json parsen (inkl. GPS)
        struct Metadata: Decodable {
            var city: String?
            var reason: String?
            var est_lat: String?
            var est_lon: String?
        }
        let jsonURL = folderURL.appendingPathComponent("event.json")
        let meta: Metadata? = if let data = try? Data(contentsOf: jsonURL) {
            try? JSONDecoder().decode(Metadata.self, from: data)
        } else {
            nil
        }

        // Thumbnail
        let thumb = folderURL.appendingPathComponent("thumb.png")
        let thumbnailURL = FileManager.default.fileExists(atPath: thumb.path) ? thumb : nil

        let clips = parseClips(in: folderURL)

        return SentryEvent(
            folderURL: folderURL,
            eventTimestamp: date,
            city: meta?.city,
            reason: meta?.reason,
            thumbnailURL: thumbnailURL,
            clips: clips,
            source: source,
            latitude: meta?.est_lat.flatMap(Double.init),
            longitude: meta?.est_lon.flatMap(Double.init)
        )
    }

    /// Gruppiert alle MP4-Dateien eines Ordners nach Timestamp-Prefix zu Clips.
    /// Dateiname-Format: `YYYY-MM-DD_HH-mm-ss-kameraname.mp4` (Prefix = 19 Zeichen).
    private nonisolated static func parseClips(in folderURL: URL) -> [SentryClip] {
        let mp4s = (try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ))?.filter { $0.pathExtension.lowercased() == "mp4" } ?? []

        var groups: [String: [URL]] = [:]
        for url in mp4s {
            let stem = url.deletingPathExtension().lastPathComponent
            guard stem.count > timestampPrefixLength else { continue }
            let prefix = String(stem.prefix(timestampPrefixLength))
            groups[prefix, default: []].append(url)
        }

        return groups.compactMap { prefix, urls -> SentryClip? in
            guard let clipDate = dateFormatter.date(from: prefix) else { return nil }
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
    }
}
