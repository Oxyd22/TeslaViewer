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

    nonisolated static func loadEvents(from rootURL: URL) -> [SentryEvent] {
        // Unterstützt: TeslaCam-Root, direkter SentryClips-Ordner, oder Unterordner
        var searchURL = rootURL
        if rootURL.lastPathComponent != "SentryClips" {
            let candidate = rootURL.appendingPathComponent("SentryClips")
            if FileManager.default.fileExists(atPath: candidate.path) {
                searchURL = candidate
            }
        }

        let folders = (try? FileManager.default.contentsOfDirectory(
            at: searchURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ))?.filter { $0.hasDirectoryPath } ?? []

        return folders
            .compactMap { parseEvent(at: $0) }
            .sorted { $0.eventTimestamp > $1.eventTimestamp }
    }

    nonisolated static func parseEvent(at folderURL: URL) -> SentryEvent? {
        let name = folderURL.lastPathComponent
        guard let date = dateFormatter.date(from: name) else { return nil }

        // event.json parsen
        struct Metadata: Decodable { var city: String?; var reason: String? }
        let jsonURL = folderURL.appendingPathComponent("event.json")
        let meta: Metadata? = if let data = try? Data(contentsOf: jsonURL) {
            try? JSONDecoder().decode(Metadata.self, from: data)
        } else {
            nil
        }

        // Thumbnail
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

        return SentryEvent(
            folderURL: folderURL,
            eventTimestamp: date,
            city: meta?.city,
            reason: meta?.reason,
            thumbnailURL: thumbnailURL,
            clips: clips
        )
    }
}
