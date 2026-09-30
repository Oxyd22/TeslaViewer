//
//  ClipExporter.swift
//  TeslaViewer
//
//  Export- und Teilen-Funktionen: im Finder zeigen, einzelne Kamera kopieren,
//  oder die 6-Kamera-Ansicht eines Segments zu einer MP4 zusammenrechnen.
//

import AVFoundation
import AppKit

enum ExportError: LocalizedError {
    case noVideoTrack
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:           "Keine Videospur gefunden."
        case .exportFailed(let msg):  "Export fehlgeschlagen: \(msg)"
        }
    }
}

enum ClipExporter {
    /// Reihenfolge wie im Grid: 3 Spalten × 2 Zeilen.
    /// (Spalte, Zeile) — Zeile 0 = oben.
    static let gridLayout: [(camera: String, col: Int, row: Int)] = [
        ("left_repeater", 0, 0), ("front", 1, 0), ("right_repeater", 2, 0),
        ("left_pillar",   0, 1), ("back",  1, 1), ("right_pillar",   2, 1),
    ]

    // MARK: - Finder

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Einzelne Kamera (verlustfrei kopieren)

    /// Kopiert die MP4 einer einzelnen Kamera (verlustfrei) ans Ziel.
    static func copyCamera(from sourceURL: URL, to destURL: URL) throws {
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
    }

    // MARK: - 6-Kamera-Grid zu einer MP4

    /// Rechnet alle vorhandenen Kameras eines Clips in ein 3×2-Raster und
    /// exportiert das Ergebnis als eine MP4 nach `destURL`.
    static func exportGrid(
        clip: SentryClip,
        to destURL: URL,
        cellSize: CGSize = CGSize(width: 640, height: 480)
    ) async throws {
        let renderSize = CGSize(width: cellSize.width * 3, height: cellSize.height * 2)

        // 1. Durchgang: Quellen laden, gemeinsame Mindestlänge bestimmen.
        struct Source {
            let asset: AVURLAsset   // festhalten, sonst wird die AVAssetTrack ungültig
            let track: AVAssetTrack
            let naturalSize: CGSize
            let col: Int
            let row: Int
        }
        var sources: [Source] = []
        var minDuration = CMTime.positiveInfinity

        for entry in gridLayout {
            guard let url = clip.cameraURLs[entry.camera] else { continue }
            let asset = AVURLAsset(url: url)
            guard let srcTrack = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let dur = try await asset.load(.duration)
            guard dur.isValid, dur.seconds > 0 else { continue }
            let naturalSize = try await srcTrack.load(.naturalSize)
            minDuration = CMTimeMinimum(minDuration, dur)
            sources.append(Source(asset: asset, track: srcTrack, naturalSize: naturalSize, col: entry.col, row: entry.row))
        }

        guard !sources.isEmpty, minDuration.isValid, minDuration != .positiveInfinity else {
            throw ExportError.noVideoTrack
        }

        // 2. Durchgang: alle Spuren auf dieselbe Länge trimmen, damit die
        // Komposition lückenlos ist (sonst AVErrorInvalidVideoComposition).
        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: minDuration)
        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []

        for source in sources {
            guard let compTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            try compTrack.insertTimeRange(range, of: source.track, at: .zero)

            let transform = gridTransform(
                naturalSize: source.naturalSize, cellSize: cellSize, col: source.col, row: source.row
            )
            let layerInst = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
            layerInst.setTransform(transform, at: .zero)
            layerInstructions.append(layerInst)
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: minDuration)
        instruction.backgroundColor = NSColor.black.cgColor
        instruction.layerInstructions = layerInstructions

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportFailed("Export-Session konnte nicht erstellt werden.")
        }
        session.videoComposition = videoComposition
        session.outputURL = destURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }

        await session.export()

        if session.status != .completed {
            throw ExportError.exportFailed(session.error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    /// Skaliert eine Kamera in ihre Rasterzelle (Aspect-Fit, zentriert).
    private static func gridTransform(
        naturalSize: CGSize, cellSize: CGSize, col: Int, row: Int
    ) -> CGAffineTransform {
        let scale = min(cellSize.width / naturalSize.width, cellSize.height / naturalSize.height)
        let scaledW = naturalSize.width * scale
        let scaledH = naturalSize.height * scale
        let dx = (cellSize.width - scaledW) / 2
        let dy = (cellSize.height - scaledH) / 2
        let cellX = CGFloat(col) * cellSize.width
        let cellY = CGFloat(row) * cellSize.height

        var transform = CGAffineTransform(scaleX: scale, y: scale)
        transform.tx = cellX + dx
        transform.ty = cellY + dy
        return transform
    }
}
