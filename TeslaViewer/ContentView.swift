//
//  ContentView.swift
//  TeslaViewer
//
//  Tesla Dashcam & Sentry Mode Viewer for macOS
//  Zeigt alle 6 Kameras synchron in einem 3x2 Grid.
//

import SwiftUI
import AVKit
import AVFoundation
import Observation

// MARK: - Datenmodelle

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

struct SentryClip: Identifiable, Sendable {
    let id = UUID()
    let clipTimestamp: Date
    var cameraURLs: [String: URL] = [:]
}

struct SentryEvent: Identifiable, Hashable, Sendable {
    let id = UUID()
    let folderURL: URL
    let eventTimestamp: Date

    var city: String?
    var reason: String?
    var thumbnailURL: URL?
    var clips: [SentryClip] = []

    var reasonInfo: EventReason { EventReason(raw: reason ?? "") }

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    var displayDate: String {
        Self.displayDateFormatter.string(from: eventTimestamp)
    }

    static func == (lhs: SentryEvent, rhs: SentryEvent) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Event-Loader

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

        var event = SentryEvent(folderURL: folderURL, eventTimestamp: date)

        // event.json parsen
        struct Metadata: Decodable { var city: String?; var reason: String? }
        let jsonURL = folderURL.appendingPathComponent("event.json")
        if let data = try? Data(contentsOf: jsonURL),
           let meta = try? JSONDecoder().decode(Metadata.self, from: data) {
            event.city = meta.city
            event.reason = meta.reason
        }

        // Thumbnail
        let thumb = folderURL.appendingPathComponent("thumb.png")
        if FileManager.default.fileExists(atPath: thumb.path) {
            event.thumbnailURL = thumb
        }

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

        event.clips = groups.compactMap { prefix, urls -> SentryClip? in
            guard let clipDate = dateFormatter.date(from: prefix) else { return nil }
            var clip = SentryClip(clipTimestamp: clipDate)
            for url in urls {
                let stem = url.deletingPathExtension().lastPathComponent
                // Kameraname beginnt nach den 19 Timestamp-Zeichen + dem Trennzeichen "-"
                let separatorOffset = timestampPrefixLength + 1 // +1 für "-" Trennzeichen
                if stem.count > separatorOffset {
                    clip.cameraURLs[String(stem.dropFirst(separatorOffset))] = url
                }
            }
            return clip
        }.sorted { $0.clipTimestamp < $1.clipTimestamp }

        return event
    }
}

// MARK: - VideoPlayerManager

@Observable
class VideoPlayerManager {
    var players: [String: AVPlayer] = [:]
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 60
    var currentClipIndex: Int = 0
    var isSeeking = false

    private var clips: [SentryClip] = []
    private var timeObserverToken: Any?
    private var trackingPlayer: AVPlayer?
    private var endObserver: NSObjectProtocol?

    var totalClips: Int { clips.count }

    func setup(clips: [SentryClip]) {
        self.clips = clips
        guard !clips.isEmpty else { return }
        loadClip(at: 0)
    }

    func loadClip(at index: Int) {
        guard clips.indices.contains(index) else { return }
        removeObservers()

        let clip = clips[index]
        currentClipIndex = index
        currentTime = 0
        duration = 60 // Standard-Clip-Länge; wird sobald geladen überschrieben

        // Neue Player erstellen
        var newPlayers: [String: AVPlayer] = [:]
        for (camera, url) in clip.cameraURLs {
            newPlayers[camera] = AVPlayer(url: url)
        }
        players = newPlayers

        // Primären Player für Zeitverfolgung wählen
        guard let primaryURL = clip.cameraURLs["front"] ?? clip.cameraURLs.values.first,
              let primary = newPlayers["front"] ?? newPlayers.values.first else { return }
        trackingPlayer = primary

        // Dauer asynchron laden (modernes async/await ab macOS 13)
        let asset = AVURLAsset(url: primaryURL)
        Task { @MainActor [weak self] in
            if let cmDur = try? await asset.load(.duration) {
                let dur = CMTimeGetSeconds(cmDur)
                if !dur.isNaN && dur > 0 { self?.duration = dur }
            }
        }

        // Zeitbeobachter
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = primary.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            guard let self, !self.isSeeking else { return }
            let t = CMTimeGetSeconds(time)
            if !t.isNaN { self.currentTime = max(0, t) }
        }

        // Clip-Ende-Benachrichtigung
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: primary.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.advanceToNextClip()
        }

        if isPlaying {
            newPlayers.values.forEach { $0.play() }
        }
    }

    func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            players.values.forEach { $0.play() }
        } else {
            players.values.forEach { $0.pause() }
        }
    }

    func seekTo(time: Double) {
        let t = CMTime(seconds: time, preferredTimescale: 600)
        players.values.forEach { $0.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) }
    }

    func advanceToNextClip() {
        if currentClipIndex < clips.count - 1 {
            loadClip(at: currentClipIndex + 1)
        } else {
            isPlaying = false
            players.values.forEach { $0.pause() }
        }
    }

    func goToPreviousClip() {
        if currentClipIndex > 0 { loadClip(at: currentClipIndex - 1) }
    }

    private func removeObservers() {
        if let token = timeObserverToken, let player = trackingPlayer {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        trackingPlayer = nil

        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        players.values.forEach { $0.pause() }
    }

    deinit { removeObservers() }
}

// MARK: - Haupt-Views

struct ContentView: View {
    @State private var events: [SentryEvent] = []
    @State private var selectedEvent: SentryEvent?
    @State private var isLoading = false
    @State private var securityScopedURL: URL?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                events: events,
                selectedEvent: $selectedEvent,
                isLoading: isLoading,
                onSelectFolder: loadFolder
            )
            .frame(minWidth: 240)
        } detail: {
            if let event = selectedEvent {
                VideoGridView(event: event)
                    .id(event.id)
            } else {
                PlaceholderView(hasEvents: !events.isEmpty)
            }
        }
    }

    private func loadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "TeslaCam-Ordner oder SentryClips-Ordner auswählen"
        panel.prompt = "Öffnen"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        securityScopedURL?.stopAccessingSecurityScopedResource()
        let granted = url.startAccessingSecurityScopedResource()
        securityScopedURL = granted ? url : nil
        isLoading = true
        events = []
        selectedEvent = nil

        Task.detached(priority: .userInitiated) {
            let loaded = EventLoader.loadEvents(from: url)
            await MainActor.run {
                self.events = loaded
                self.selectedEvent = loaded.first
                self.isLoading = false
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let events: [SentryEvent]
    @Binding var selectedEvent: SentryEvent?
    let isLoading: Bool
    let onSelectFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onSelectFolder) {
                    Label("Öffnen", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                if !events.isEmpty {
                    Text("\(events.count) Ereignisse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Lade Ereignisse…")
                Spacer()
            } else if events.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "car.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Kein Ordner geladen")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(events, selection: $selectedEvent) { event in
                    EventRowView(event: event).tag(event)
                }
                .listStyle(.sidebar)
            }
        }
    }
}

struct EventRowView: View {
    let event: SentryEvent
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail
            Group {
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 62, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 62, height: 40)
                        .overlay(
                            Image(systemName: "video")
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .task(id: event.thumbnailURL) {
                guard let url = event.thumbnailURL else { return }
                thumbnail = await Task.detached {
                    NSImage(contentsOf: url)
                }.value
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayDate)
                    .font(.caption).fontWeight(.semibold)
                    .lineLimit(1)

                if let city = event.city {
                    Text(city)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Label(event.reasonInfo.display, systemImage: event.reasonInfo.systemIcon)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)

                Text("\(event.clips.count) Clip\(event.clips.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct PlaceholderView: View {
    let hasEvents: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasEvents ? "car.rear.fill" : "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(hasEvents ? "Ereignis aus der Liste wählen" : "TeslaCam-Ordner öffnen")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Video-Grid

struct VideoGridView: View {
    let event: SentryEvent
    @State private var manager = VideoPlayerManager()

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
            } else {
                GeometryReader { geo in
                    let colCount = 3
                    let rowCount = 2
                    let spacing: CGFloat = 2
                    let w = (geo.size.width  - CGFloat(colCount - 1) * spacing) / CGFloat(colCount)
                    let h = (geo.size.height - CGFloat(rowCount - 1) * spacing) / CGFloat(rowCount)

                    VStack(spacing: spacing) {
                        ForEach(0..<Self.layout.count, id: \.self) { row in
                            HStack(spacing: spacing) {
                                ForEach(Self.layout[row], id: \.self) { camera in
                                    CameraCell(
                                        player: manager.players[camera],
                                        label: Self.cameraLabels[camera] ?? camera
                                    )
                                    .frame(width: w, height: h)
                                }
                            }
                        }
                    }
                }
                .background(Color.black)
            }

            Divider()
            controlBar
        }
        .onAppear { manager.setup(clips: event.clips) }
    }

    // MARK: Header

    var headerBar: some View {
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

    var controlBar: some View {
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
                value: Binding(
                    get: { manager.currentTime },
                    set: { manager.currentTime = $0 }
                ),
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
            if let player = player {
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
