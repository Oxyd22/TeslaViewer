//
//  Models.swift
//  TeslaViewer
//
//  Datenmodelle für Sentry-Ereignisse und Clips.
//

import Foundation
import CoreLocation

// MARK: - ClipSource

/// Die drei Quell-Ordner, die Tesla auf dem USB-Stick anlegt.
enum ClipSource: String, CaseIterable, Identifiable, Sendable {
    case sentry
    case saved
    case recent

    var id: String { rawValue }

    /// Ordnername im TeslaCam-Verzeichnis.
    var folderName: String {
        switch self {
        case .sentry: "SentryClips"
        case .saved:  "SavedClips"
        case .recent: "RecentClips"
        }
    }

    var displayName: String {
        switch self {
        case .sentry: "Sentry"
        case .saved:  "Gespeichert"
        case .recent: "Letzte"
        }
    }

    var systemIcon: String {
        switch self {
        case .sentry: "shield.lefthalf.filled"
        case .saved:  "bookmark.fill"
        case .recent: "clock.fill"
        }
    }
}

// MARK: - EventReason

struct EventReason {
    let raw: String

    private var resolved: (display: String, icon: String) {
        switch raw {
        case "sentry_aware_object_detection":
            ("Objekt erkannt", "eye.fill")
        case "sentry_aware_acc_object_detection":
            ("Objekt nahe Fahrzeug", "eye.fill")
        case "sentry_aware_body_cam_object_detection":
            ("Person erkannt", "figure.walk")
        case "user_interaction_dashcam_icon_tapped", "user_interaction_dashcam_panel_save":
            ("Manuell gespeichert", "square.and.arrow.down")
        case "user_interaction_honk":
            ("Hupe betätigt", "speaker.wave.2.fill")
        case "sentry_aware_collision":
            ("Kollision", "exclamationmark.triangle.fill")
        case "":
            ("Sentry-Ereignis", "video.fill")
        default:
            (raw.replacingOccurrences(of: "_", with: " ").capitalized, "video.fill")
        }
    }

    var display: String { resolved.display }
    var systemIcon: String { resolved.icon }
}

// MARK: - SentryClip

struct SentryClip: Identifiable, Sendable {
    let id = UUID()
    let clipTimestamp: Date
    let cameraURLs: [String: URL]
}

// MARK: - SentryEvent

struct SentryEvent: Identifiable, Hashable, Sendable {
    let id = UUID()
    let folderURL: URL
    let eventTimestamp: Date
    let city: String?
    let reason: String?
    let thumbnailURL: URL?
    let clips: [SentryClip]
    let source: ClipSource
    let latitude: Double?
    let longitude: Double?

    var reasonInfo: EventReason { EventReason(raw: reason ?? "") }

    /// GPS-Position aus `event.json` (`est_lat`/`est_lon`), falls vorhanden.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayDate: String {
        eventTimestamp.formatted(
            .dateTime
                .locale(Locale(identifier: "de_DE"))
                .day().month(.abbreviated).year()
                .hour().minute()
        )
    }

    static func == (lhs: SentryEvent, rhs: SentryEvent) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Preview-Beispieldaten

extension SentryEvent {
    static let preview = SentryEvent(
        folderURL: URL(fileURLWithPath: "/tmp/2025-12-23_12-00-00"),
        eventTimestamp: Date(timeIntervalSince1970: 1_735_000_000),
        city: "Berlin",
        reason: "sentry_aware_object_detection",
        thumbnailURL: nil,
        clips: [
            SentryClip(clipTimestamp: Date(timeIntervalSince1970: 1_735_000_000), cameraURLs: [:]),
            SentryClip(clipTimestamp: Date(timeIntervalSince1970: 1_735_000_060), cameraURLs: [:]),
        ],
        source: .sentry,
        latitude: 52.5200,
        longitude: 13.4050
    )

    static let previewList: [SentryEvent] = [
        preview,
        SentryEvent(
            folderURL: URL(fileURLWithPath: "/tmp/2025-12-22_08-30-00"),
            eventTimestamp: Date(timeIntervalSince1970: 1_734_900_000),
            city: "München",
            reason: "sentry_aware_collision",
            thumbnailURL: nil,
            clips: [
                SentryClip(clipTimestamp: Date(timeIntervalSince1970: 1_734_900_000), cameraURLs: [:])
            ],
            source: .saved,
            latitude: 48.1351,
            longitude: 11.5820
        ),
        SentryEvent(
            folderURL: URL(fileURLWithPath: "/tmp/2025-12-21_14-15-00"),
            eventTimestamp: Date(timeIntervalSince1970: 1_734_800_000),
            city: "Hamburg",
            reason: "user_interaction_honk",
            thumbnailURL: nil,
            clips: [
                SentryClip(clipTimestamp: Date(timeIntervalSince1970: 1_734_800_000), cameraURLs: [:])
            ],
            source: .sentry,
            latitude: nil,
            longitude: nil
        ),
    ]
}
