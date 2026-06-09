//
//  Models.swift
//  TeslaViewer
//
//  Datenmodelle für Sentry-Ereignisse und Clips.
//

import Foundation

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

    var reasonInfo: EventReason { EventReason(raw: reason ?? "") }

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
        ]
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
            ]
        ),
        SentryEvent(
            folderURL: URL(fileURLWithPath: "/tmp/2025-12-21_14-15-00"),
            eventTimestamp: Date(timeIntervalSince1970: 1_734_800_000),
            city: "Hamburg",
            reason: "user_interaction_honk",
            thumbnailURL: nil,
            clips: [
                SentryClip(clipTimestamp: Date(timeIntervalSince1970: 1_734_800_000), cameraURLs: [:])
            ]
        ),
    ]
}
