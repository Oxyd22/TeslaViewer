//
//  Models.swift
//  TeslaViewer
//
//  Datenmodelle für Sentry-Ereignisse und Clips.
//

import SwiftUI

// MARK: - EventReason

nonisolated enum EventReason: Hashable, Sendable {
    case objectDetected
    case objectNearVehicle
    case personDetected
    case handlePulled
    case collision
    case acceleration(magnitude: Double?)
    case honk
    case manuallySaved
    case generic
    case unknown(String)

    init(raw: String?) {
        guard let raw, !raw.isEmpty else {
            self = .generic
            return
        }
        switch raw {
        case "sentry_aware_object_detection":
            self = .objectDetected
        case "sentry_aware_acc_object_detection":
            self = .objectNearVehicle
        case "sentry_aware_body_cam_object_detection":
            self = .personDetected
        case "sentry_locked_handle_pulled":
            self = .handlePulled
        case "sentry_aware_collision":
            self = .collision
        case "user_interaction_honk":
            self = .honk
        case "user_interaction_dashcam_icon_tapped",
             "user_interaction_dashcam_panel_save",
             "user_interaction_dashcam_multifunction_selected",
             "user_interaction_dashcam_launcher_action_tapped":
            self = .manuallySaved
        default:
            let accelPrefix = "sentry_aware_accel_"
            if raw.hasPrefix(accelPrefix) {
                self = .acceleration(magnitude: Double(raw.dropFirst(accelPrefix.count)))
            } else {
                self = .unknown(raw)
            }
        }
    }

    var display: String {
        switch self {
        case .objectDetected: "Objekt erkannt"
        case .objectNearVehicle: "Objekt nahe Fahrzeug"
        case .personDetected: "Person erkannt"
        case .handlePulled: "Türgriff gezogen"
        case .collision: "Kollision"
        case .acceleration: "Erschütterung"
        case .honk: "Hupe betätigt"
        case .manuallySaved: "Manuell gespeichert"
        case .generic: "Sentry-Ereignis"
        case .unknown(let raw): raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var systemIcon: String {
        switch self {
        case .objectDetected, .objectNearVehicle: "eye.fill"
        case .personDetected: "figure.walk"
        case .handlePulled: "hand.raised.fill"
        case .collision: "exclamationmark.triangle.fill"
        case .acceleration: "waveform.path.ecg"
        case .honk: "speaker.wave.2.fill"
        case .manuallySaved: "square.and.arrow.down"
        case .generic, .unknown: "video.fill"
        }
    }

    var severityColor: Color {
        switch self {
        case .collision: .red
        case .objectDetected, .objectNearVehicle, .personDetected, .handlePulled, .acceleration: .orange
        case .honk, .manuallySaved, .generic, .unknown: .accentColor
        }
    }
}

// MARK: - ClipSource

nonisolated enum ClipSource: String, Sendable {
    case sentry
    case saved

    var displayName: String {
        switch self {
        case .sentry: "Sentry-Ereignisse"
        case .saved: "Gespeicherte Clips"
        }
    }

    var systemIcon: String {
        switch self {
        case .sentry: "shield.lefthalf.filled"
        case .saved: "bookmark.fill"
        }
    }
}

// MARK: - SentryClip

nonisolated struct SentryClip: Identifiable, Sendable {
    let id = UUID()
    let clipTimestamp: Date
    let cameraURLs: [String: URL]
}

// MARK: - SentryEvent

nonisolated struct SentryEvent: Identifiable, Hashable, Sendable {
    let folderURL: URL
    let eventTimestamp: Date
    let triggerTimestamp: Date?
    let city: String?
    let street: String?
    let reason: String?
    let thumbnailURL: URL?
    let source: ClipSource
    let clips: [SentryClip]

    var id: URL { folderURL }

    var reasonInfo: EventReason { EventReason(raw: reason) }

    /// Sekunden zwischen Ereignisbeginn (erster Clip) und dem tatsächlichen Auslöse-Zeitpunkt.
    var triggerOffset: Double? {
        guard let triggerTimestamp, let firstClip = clips.first else { return nil }
        return triggerTimestamp.timeIntervalSince(firstClip.clipTimestamp)
    }

    var displayDate: String {
        eventTimestamp.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }

    var displayDay: String {
        eventTimestamp.formatted(.dateTime.day().month(.wide).year())
    }

    var displayTime: String {
        eventTimestamp.formatted(.dateTime.hour().minute())
    }

    static func == (lhs: SentryEvent, rhs: SentryEvent) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Preview-Beispieldaten

extension SentryEvent {
    static let preview = SentryEvent(
        folderURL: URL(fileURLWithPath: "/tmp/2025-12-23_12-00-00"),
        eventTimestamp: Date(timeIntervalSince1970: 1_735_000_000),
        triggerTimestamp: Date(timeIntervalSince1970: 1_735_000_057),
        city: "Berlin",
        street: "Unter den Linden",
        reason: "sentry_aware_object_detection",
        thumbnailURL: nil,
        source: .sentry,
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
            triggerTimestamp: nil,
            city: "München",
            street: nil,
            reason: "sentry_aware_collision",
            thumbnailURL: nil,
            source: .sentry,
            clips: [
                SentryClip(clipTimestamp: Date(timeIntervalSince1970: 1_734_900_000), cameraURLs: [:])
            ]
        ),
        SentryEvent(
            folderURL: URL(fileURLWithPath: "/tmp/2025-12-21_14-15-00"),
            eventTimestamp: Date(timeIntervalSince1970: 1_734_800_000),
            triggerTimestamp: nil,
            city: "Hamburg",
            street: nil,
            reason: "user_interaction_dashcam_launcher_action_tapped",
            thumbnailURL: nil,
            source: .saved,
            clips: [
                SentryClip(clipTimestamp: Date(timeIntervalSince1970: 1_734_800_000), cameraURLs: [:])
            ]
        ),
    ]
}
