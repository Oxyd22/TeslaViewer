//
//  VideoGridView.swift
//  TeslaViewer
//
//  Zeigt alle 6 Kamera-Feeds in einem 3x2 Grid mit Steuerleiste.
//

import SwiftUI
import AVKit

// MARK: - Video-Grid

struct VideoGridView: View {
    let event: SentryEvent
    @State private var manager = VideoPlayerManager()
    @State private var zoomedCamera: String?

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

            Text(timeStr(manager.currentTime))
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .trailing)

            Slider(
                value: $manager.currentTime,
                in: 0...max(manager.duration, 0.01)
            ) { editing in
                manager.isSeeking = editing
                if !editing { manager.seekTo(time: manager.currentTime) }
            }

            Text(timeStr(manager.duration))
                .font(.caption.monospacedDigit())
                .frame(width: 42)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func timeStr(_ seconds: Double) -> String {
        let clamped = Int(max(0, seconds))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
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
