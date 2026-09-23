//
//  EventComposition.swift
//  TeslaViewer
//
//  Baut pro Kamera eine durchgehende AVMutableComposition über alle Clips
//  eines Ereignisses, damit das gesamte Ereignis eine einzige Zeitachse hat.
//

import AVFoundation

struct EventComposition {
    let items: [String: AVPlayerItem]
    let duration: Double
    /// Sekunden-Offsets der Clipgrenzen innerhalb der Ereignis-Zeitachse (ohne die letzte,
    /// die mit `duration` zusammenfällt) — für die Teilstriche der Timeline.
    let clipBoundaries: [Double]
    /// Sekunden zwischen Ereignisbeginn und dem tatsächlichen Auslöse-Zeitpunkt.
    let triggerOffset: Double?

    static let empty = EventComposition(items: [:], duration: 0, clipBoundaries: [], triggerOffset: nil)
}

enum EventCompositionBuilder {
    /// Baut pro Kamera eine Komposition, die alle Clips des Ereignisses hintereinander enthält.
    /// Fehlt eine Kamera in einem Clip, bleibt die entsprechende Zeitspanne in ihrer Spur
    /// unbelegt (und erscheint beim Abspielen leer), während der Cursor trotzdem um die volle
    /// Clipdauer weiterrückt — so bleiben alle Kameras zeitlich deckungsgleich.
    static func make(for event: SentryEvent) async -> EventComposition {
        let clips = event.clips
        guard !clips.isEmpty else { return .empty }

        let cameraNames = Set(clips.flatMap(\.cameraURLs.keys))

        // Referenzdauer pro Clip (bevorzugt "front", sonst die erste vorhandene Kamera) —
        // maßgeblich für alle Kameras, damit keine Kamera aus dem Takt gerät.
        var clipDurations: [Double] = []
        for clip in clips {
            let referenceURL = clip.cameraURLs["front"] ?? clip.cameraURLs.values.first
            var seconds = 0.0
            if let referenceURL {
                let asset = AVURLAsset(url: referenceURL)
                if let cmDuration = try? await asset.load(.duration) {
                    let value = CMTimeGetSeconds(cmDuration)
                    if value.isFinite, value > 0 { seconds = value }
                }
            }
            clipDurations.append(seconds)
        }

        var boundaries: [Double] = []
        var running: Double = 0
        for seconds in clipDurations {
            running += seconds
            boundaries.append(running)
        }
        let totalDuration = running

        var items: [String: AVPlayerItem] = [:]
        for camera in cameraNames {
            let composition = AVMutableComposition()
            let track = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
            )

            var cursor = CMTime.zero
            for (index, clip) in clips.enumerated() {
                let clipDuration = CMTime(seconds: clipDurations[index], preferredTimescale: 600)
                if let url = clip.cameraURLs[camera] {
                    let asset = AVURLAsset(url: url)
                    let videoTrack = (try? await asset.load(.tracks))?.first { $0.mediaType == .video }
                    if let videoTrack {
                        try? track?.insertTimeRange(
                            CMTimeRange(start: .zero, duration: clipDuration), of: videoTrack, at: cursor
                        )
                    }
                }
                cursor = cursor + clipDuration
            }

            items[camera] = AVPlayerItem(asset: composition)
        }

        let triggerOffset = event.triggerOffset.map { max(0, min($0, totalDuration)) }

        return EventComposition(
            items: items,
            duration: totalDuration,
            clipBoundaries: Array(boundaries.dropLast()),
            triggerOffset: triggerOffset
        )
    }
}
