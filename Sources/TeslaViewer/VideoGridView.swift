//
//  VideoGridView.swift
//  TeslaViewer
//
//  Zeigt alle 6 Kamera-Feeds in einem 3x2 Grid mit Steuerleiste.
//

import SwiftUI
import AVKit
import MapKit
import UniformTypeIdentifiers

// MARK: - Video-Grid

struct VideoGridView: View {
    let event: SentryEvent
    @State private var manager = VideoPlayerManager()
    @State private var zoomedCamera: String?
    @State private var showingMap = false
    @State private var isExporting = false
    @State private var exportError: String?

    // Kamera-Layout: 3 Spalten x 2 Zeilen
    // [left_repeater] [  front  ] [right_repeater]
    // [left_pillar  ] [  back   ] [right_pillar  ]
    private static let layout: [[String]] = [
        ["left_repeater", "front",  "right_repeater"],
        ["left_pillar",   "back",   "right_pillar"]
    ]

    private static let cameraLabels: [String: String] = [
        "front":           "Front",
        "back":            "Hinten",
        "left_repeater":   "Links",
        "right_repeater":  "Rechts",
        "left_pillar":     "Links hinten",
        "right_pillar":    "Rechts hinten"
    ]

    private var currentClip: SentryClip? {
        event.clips.indices.contains(manager.currentClipIndex) ? event.clips[manager.currentClipIndex] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if event.clips.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Keine Videodateien gefunden")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if let zoomed = zoomedCamera {
                // Einzelkamera-Zoom
                CameraCell(
                    player: manager.players[zoomed],
                    label: Self.cameraLabels[zoomed] ?? zoomed
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.25)) { zoomedCamera = nil }
                }
                .background(Color.black)
                .transition(.opacity)
            } else {
                // 3x2 Kamera-Grid
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    ForEach(Self.layout, id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.self) { camera in
                                CameraCell(
                                    player: manager.players[camera],
                                    label: Self.cameraLabels[camera] ?? camera
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onTapGesture(count: 2) {
                                    withAnimation(.easeInOut(duration: 0.25)) { zoomedCamera = camera }
                                }
                            }
                        }
                    }
                }
                .background(Color.black)
                .transition(.opacity)
            }

            Divider()
            controlBar
        }
        .overlay {
            if isExporting {
                ExportOverlay()
            }
        }
        .alert("Export fehlgeschlagen", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .focusable()
        .onKeyPress(.space) {
            manager.togglePlayback()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            manager.advanceToNextClip()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            manager.goToPreviousClip()
            return .handled
        }
        .onKeyPress(.escape) {
            guard zoomedCamera != nil else { return .ignored }
            withAnimation(.easeInOut(duration: 0.25)) { zoomedCamera = nil }
            return .handled
        }
        .onAppear { manager.setup(clips: event.clips) }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayDate)
                    .font(.subheadline).fontWeight(.semibold)
                if let city = event.city {
                    Text(city)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Auslöse-Badge
            Label(event.reasonInfo.display, systemImage: event.reasonInfo.systemIcon)
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Karte (nur wenn GPS vorhanden)
            if let coordinate = event.coordinate {
                Button {
                    showingMap.toggle()
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .buttonStyle(.borderless)
                .help("Ort auf Karte anzeigen")
                .popover(isPresented: $showingMap, arrowEdge: .bottom) {
                    MapPopover(coordinate: coordinate, title: event.city ?? "Tesla-Ereignis")
                }
            }

            // Export / Teilen
            Menu {
                Button {
                    ClipExporter.revealInFinder(event.folderURL)
                } label: {
                    Label("Im Finder zeigen", systemImage: "folder")
                }

                Divider()

                Button {
                    exportGrid()
                } label: {
                    Label("Segment als 6-Kamera-MP4…", systemImage: "square.grid.3x2")
                }
                .disabled(currentClip == nil)

                Menu {
                    ForEach(Self.layout.flatMap { $0 }, id: \.self) { camera in
                        Button(Self.cameraLabels[camera] ?? camera) {
                            exportCamera(camera)
                        }
                        .disabled(currentClip?.cameraURLs[camera] == nil)
                    }
                } label: {
                    Label("Einzelne Kamera sichern", systemImage: "video")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Exportieren & Teilen")

            // Clip-Navigation (nur bei mehreren Clips)
            if event.clips.count > 1 {
                HStack(spacing: 6) {
                    Button {
                        manager.goToPreviousClip()
                    } label: {
                        Image(systemName: "backward.frame.fill")
                    }
                    .disabled(manager.currentClipIndex == 0)

                    Text("Clip \(manager.currentClipIndex + 1) / \(manager.totalClips)")
                        .font(.caption.monospacedDigit())

                    Button {
                        manager.advanceToNextClip()
                    } label: {
                        Image(systemName: "forward.frame.fill")
                    }
                    .disabled(manager.currentClipIndex == manager.totalClips - 1)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Steuerleiste

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button {
                manager.togglePlayback()
            } label: {
                Image(systemName: manager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.borderless)

            Text(timeStr(manager.globalTime))
                .font(.caption.monospacedDigit())
                .frame(width: 46, alignment: .trailing)

            // Durchgehende Timeline über alle Segmente
            Slider(
                value: $manager.globalTime,
                in: 0...max(manager.totalDuration, 0.01)
            ) { editing in
                manager.isSeeking = editing
                if !editing { manager.seekToGlobal(manager.globalTime) }
            }

            Text(timeStr(manager.totalDuration))
                .font(.caption.monospacedDigit())
                .frame(width: 46)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func timeStr(_ seconds: Double) -> String {
        let clamped = Int(max(0, seconds))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    // MARK: - Export-Aktionen

    private var baseName: String {
        EventLoader.dateFormatter.string(from: currentClip?.clipTimestamp ?? event.eventTimestamp)
    }

    private func exportGrid() {
        guard let clip = currentClip else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(baseName)-6cam.mp4"
        panel.message = "6-Kamera-Ansicht des aktuellen Segments exportieren"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        Task {
            do {
                try await ClipExporter.exportGrid(clip: clip, to: url)
            } catch {
                await MainActor.run { exportError = error.localizedDescription }
            }
            await MainActor.run { isExporting = false }
        }
    }

    private func exportCamera(_ camera: String) {
        guard let src = currentClip?.cameraURLs[camera] else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(baseName)-\(camera).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ClipExporter.copyCamera(from: src, to: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - Karten-Popover

struct MapPopover: View {
    let coordinate: CLLocationCoordinate2D
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            ))) {
                Marker(title, coordinate: coordinate)
            }
            .frame(width: 320, height: 240)

            Divider()

            Button {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                item.name = title
                item.openInMaps()
            } label: {
                Label("In Apple Karten öffnen", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }
}

// MARK: - Export-Overlay

struct ExportOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Exportiere…")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .ignoresSafeArea()
    }
}

// MARK: - Kamera-Zelle

struct CameraCell: View {
    let player: AVPlayer?
    let label: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let player {
                PlayerView(player: player)
            } else {
                Color.black.overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "video.slash.fill")
                            .foregroundStyle(Color.gray.opacity(0.6))
                        Text("Kein Signal")
                            .font(.caption2)
                            .foregroundStyle(Color.gray.opacity(0.6))
                    }
                )
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(5)
        }
    }
}

// MARK: - NSViewRepresentable

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .none
        v.videoGravity = .resizeAspect
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
}

// MARK: - Previews

#Preview("Video-Grid") {
    VideoGridView(event: .preview)
        .frame(width: 900, height: 550)
}

#Preview("Kamera-Zelle (kein Signal)") {
    CameraCell(player: nil, label: "Front")
        .frame(width: 300, height: 200)
}

#Preview("Karten-Popover") {
    MapPopover(coordinate: .init(latitude: 52.52, longitude: 13.405), title: "Berlin")
}
