//
//  VideoGridView.swift
//  TeslaViewer
//
//  Zeigt alle 6 Kamera-Feeds in einem 3x2 Grid mit einer durchgehenden
//  Zeitleiste über das gesamte Ereignis.
//

import SwiftUI
import AVFoundation

// MARK: - Fokussierte Wiedergabe-Aktionen (für die Menüleiste)

struct PlaybackActions {
    var togglePlayback: () -> Void
    var stepBackward: () -> Void
    var stepForward: () -> Void
    var jumpToTrigger: (() -> Void)?
    var exitFocus: (() -> Void)?
    var revealInFinder: () -> Void
}

private struct PlaybackActionsKey: FocusedValueKey {
    typealias Value = PlaybackActions
}

extension FocusedValues {
    var playbackActions: PlaybackActions? {
        get { self[PlaybackActionsKey.self] }
        set { self[PlaybackActionsKey.self] = newValue }
    }
}

// MARK: - Video-Grid

struct VideoGridView: View {
    let event: SentryEvent
    @State private var manager = VideoPlayerManager()
    @State private var zoomedCamera: String?
    @Namespace private var cameraNamespace

    // Kamera-Layout: 3 Spalten x 2 Zeilen
    // [left_pillar  ] [  front  ] [right_pillar  ]  ← nach vorn gerichtet
    // [left_repeater] [  back   ] [right_repeater]  ← nach hinten gerichtet
    private static let layout: [[String]] = [
        ["left_pillar",   "front", "right_pillar"],
        ["left_repeater",  "back", "right_repeater"]
    ]

    private static let cameraLabels: [String: String] = [
        "front":           "Front",
        "back":            "Hinten",
        "left_pillar":     "Links vorne",
        "right_pillar":    "Rechts vorne",
        "left_repeater":   "Links hinten",
        "right_repeater":  "Rechts hinten"
    ]

    var body: some View {
        content
            .safeAreaInset(edge: .top) { headerBar }
            .safeAreaInset(edge: .bottom) {
                if !event.clips.isEmpty { controlBar }
            }
            .background(Color.black)
            .task(id: event.id) {
                await manager.load(event)
            }
            .onDisappear { manager.tearDown() }
            .focusedSceneValue(\.playbackActions, playbackActions)
    }

    @ViewBuilder
    private var content: some View {
        if event.clips.isEmpty {
            ContentUnavailableView(
                "Keine Videodateien gefunden",
                systemImage: "exclamationmark.triangle",
                description: Text("Für dieses Ereignis wurden keine Kameraaufnahmen gefunden.")
            )
        } else if let zoomed = zoomedCamera {
            CameraCell(player: manager.players[zoomed], label: Self.cameraLabels[zoomed] ?? zoomed)
                .matchedGeometryEffect(id: zoomed, in: cameraNamespace)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { exitFocus() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Tippen, um zur Rasteransicht zurückzukehren.")
        } else {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(Self.layout, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { camera in
                            CameraCell(player: manager.players[camera], label: Self.cameraLabels[camera] ?? camera)
                                .matchedGeometryEffect(id: camera, in: cameraNamespace)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture { focus(on: camera) }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint("Tippen, um diese Kamera zu vergrößern.")
                        }
                    }
                }
            }
        }
    }

    private func focus(on camera: String) {
        withAnimation(.easeInOut(duration: 0.25)) { zoomedCamera = camera }
    }

    private func exitFocus() {
        withAnimation(.easeInOut(duration: 0.25)) { zoomedCamera = nil }
    }

    private var playbackActions: PlaybackActions {
        PlaybackActions(
            togglePlayback: { manager.togglePlayback() },
            stepBackward: { manager.step(by: -1) },
            stepForward: { manager.step(by: 1) },
            jumpToTrigger: manager.triggerOffset != nil ? { manager.jumpToTrigger() } : nil,
            exitFocus: zoomedCamera != nil ? { exitFocus() } : nil,
            revealInFinder: { NSWorkspace.shared.activateFileViewerSelecting([event.folderURL]) }
        )
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayDate)
                    .font(.subheadline).fontWeight(.semibold)
                let location = [event.street, event.city].compactMap { $0 }.joined(separator: ", ")
                if !location.isEmpty {
                    Text(location)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Label(event.reasonInfo.display, systemImage: event.reasonInfo.systemIcon)
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(event.reasonInfo.severityColor.opacity(0.15))
                .foregroundStyle(event.reasonInfo.severityColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Steuerleiste

    private var controlBar: some View {
        GlassEffectContainer {
            HStack(spacing: 14) {
                Button {
                    manager.togglePlayback()
                } label: {
                    Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 18)
                }
                .buttonStyle(.plain)

                Text(timeStr(manager.currentTime))
                    .font(.caption.monospacedDigit())
                    .frame(width: 42, alignment: .trailing)

                EventTimelineView(
                    duration: manager.duration,
                    clipBoundaries: manager.clipBoundaries,
                    triggerOffset: manager.triggerOffset,
                    severityColor: event.reasonInfo.severityColor,
                    currentTime: manager.currentTime,
                    onScrub: { time in
                        manager.isSeeking = true
                        manager.seek(to: time, precise: false)
                    },
                    onCommit: { time in
                        manager.seek(to: time, precise: true)
                        manager.isSeeking = false
                    }
                )

                Text(timeStr(manager.duration))
                    .font(.caption.monospacedDigit())
                    .frame(width: 42)

                if manager.triggerOffset != nil {
                    Button {
                        manager.jumpToTrigger()
                    } label: {
                        Image(systemName: "bolt.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Zum Ereignis springen")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 20))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func timeStr(_ seconds: Double) -> String {
        let clamped = Int(max(0, seconds))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}

// MARK: - Zeitleiste

/// Eine durchgehende Zeitleiste über das gesamte Ereignis mit Teilstrichen an den
/// Clipgrenzen und einer Markierung am tatsächlichen Auslöse-Zeitpunkt.
private struct EventTimelineView: View {
    let duration: Double
    let clipBoundaries: [Double]
    let triggerOffset: Double?
    let severityColor: Color
    let currentTime: Double
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(height: 4)

                Capsule()
                    .fill(.white)
                    .frame(width: xPosition(for: currentTime, in: width), height: 4)

                ForEach(clipBoundaries, id: \.self) { boundary in
                    Rectangle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 1, height: 8)
                        .offset(x: xPosition(for: boundary, in: width))
                }

                if let triggerOffset {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(severityColor)
                        .offset(x: xPosition(for: triggerOffset, in: width) - 4, y: -10)
                }

                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .offset(x: xPosition(for: currentTime, in: width) - 6)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onScrub(time(forX: value.location.x, in: width)) }
                    .onEnded { value in onCommit(time(forX: value.location.x, in: width)) }
            )
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Zeitleiste")
        .accessibilityValue(timeStr(currentTime))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onCommit(min(currentTime + 5, duration))
            case .decrement: onCommit(max(currentTime - 5, 0))
            @unknown default: break
            }
        }
    }

    private func xPosition(for time: Double, in width: Double) -> Double {
        guard duration > 0 else { return 0 }
        return (time / duration) * width
    }

    private func time(forX x: Double, in width: Double) -> Double {
        guard width > 0 else { return 0 }
        return max(0, min(duration, (x / width) * duration))
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

/// Zeigt einen `AVPlayer` über eine reine `AVPlayerLayer` an, statt über die schwerere
/// `AVPlayerView`-Wiedergabe-UI von AVKit, die bei sechs parallelen Kacheln unnötig Last erzeugt.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        playerLayer.videoGravity = .resizeAspect
        layer = playerLayer
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) wird nicht unterstützt")
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
