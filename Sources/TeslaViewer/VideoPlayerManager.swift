//
//  VideoPlayerManager.swift
//  TeslaViewer
//
//  Verwaltet synchrone AVPlayer-Instanzen für alle Kameras eines Clips.
//

import AVFoundation

@MainActor
@Observable
class VideoPlayerManager {
    static let defaultClipDuration: Double = 60

    var players: [String: AVPlayer] = [:]
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = defaultClipDuration
    var currentClipIndex: Int = 0
    var isSeeking = false

    /// Position über alle Segmente hinweg (Sekunden seit Beginn des Ereignisses).
    var globalTime: Double = 0
    /// Gesamtdauer aller Segmente zusammen.
    var totalDuration: Double = defaultClipDuration

    private var clips: [SentryClip] = []
    /// Dauer je Segment (zunächst geschätzt, dann asynchron präzisiert).
    private var clipDurations: [Double] = []
    /// Kumulierte Startzeit je Segment (Präfixsumme von `clipDurations`).
    private var clipStarts: [Double] = []
    private var timeObserverToken: Any?
    private var trackingPlayer: AVPlayer?
    private var endObserver: NSObjectProtocol?

    var totalClips: Int { clips.count }

    func setup(clips: [SentryClip]) {
        self.clips = clips
        clipDurations = Array(repeating: Self.defaultClipDuration, count: clips.count)
        recomputeTimeline()
        guard !clips.isEmpty else { return }
        loadClip(at: 0)
        loadAllDurations()
    }

    func loadClip(at index: Int) {
        guard clips.indices.contains(index) else { return }
        removeObservers()

        let clip = clips[index]
        currentClipIndex = index
        currentTime = 0
        duration = clipDurations.indices.contains(index) ? clipDurations[index] : Self.defaultClipDuration
        globalTime = clipStarts.indices.contains(index) ? clipStarts[index] : 0

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

        // Dauer asynchron laden (präzisiert die Schätzung für dieses Segment)
        let asset = AVURLAsset(url: primaryURL)
        Task { [weak self] in
            if let cmDur = try? await asset.load(.duration) {
                let dur = CMTimeGetSeconds(cmDur)
                if !dur.isNaN && dur > 0 {
                    self?.updateDuration(dur, at: index)
                }
            }
        }

        // Zeitbeobachter
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = primary.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            guard let self, !self.isSeeking else { return }
            let t = CMTimeGetSeconds(time)
            if !t.isNaN {
                self.currentTime = max(0, t)
                let start = self.clipStarts.indices.contains(self.currentClipIndex)
                    ? self.clipStarts[self.currentClipIndex] : 0
                self.globalTime = start + self.currentTime
            }
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

    /// Sucht innerhalb des aktuellen Segments (lokale Zeit).
    func seekTo(time: Double) {
        let t = CMTime(seconds: time, preferredTimescale: 600)
        players.values.forEach { $0.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) }
    }

    /// Sucht über alle Segmente hinweg (globale Zeit). Wechselt bei Bedarf das Segment.
    func seekToGlobal(_ time: Double) {
        guard !clips.isEmpty else { return }
        let clamped = max(0, min(time, max(totalDuration - 0.05, 0)))

        // Zielsegment finden
        var index = 0
        for i in clips.indices where clamped >= clipStarts[i] {
            index = i
        }
        let offset = clamped - clipStarts[index]

        if index != currentClipIndex {
            loadClip(at: index)
        }
        currentTime = offset
        globalTime = clipStarts[index] + offset
        seekTo(time: offset)
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

    // MARK: - Timeline-Berechnung

    private func recomputeTimeline() {
        var starts: [Double] = []
        var acc: Double = 0
        for d in clipDurations {
            starts.append(acc)
            acc += d
        }
        clipStarts = starts
        totalDuration = max(acc, 0.01)
    }

    private func updateDuration(_ dur: Double, at index: Int) {
        guard clipDurations.indices.contains(index) else { return }
        clipDurations[index] = dur
        if index == currentClipIndex { duration = dur }
        recomputeTimeline()
    }

    /// Lädt die Dauer aller Segmente im Hintergrund, damit die Gesamt-Timeline stimmt.
    private func loadAllDurations() {
        let snapshot = clips
        for (index, clip) in snapshot.enumerated() {
            guard let url = clip.cameraURLs["front"] ?? clip.cameraURLs.values.first else { continue }
            let asset = AVURLAsset(url: url)
            Task { [weak self] in
                if let cmDur = try? await asset.load(.duration) {
                    let dur = CMTimeGetSeconds(cmDur)
                    if !dur.isNaN && dur > 0 {
                        self?.updateDuration(dur, at: index)
                    }
                }
            }
        }
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

    deinit {}
}
