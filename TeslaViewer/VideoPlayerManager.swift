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
        duration = Self.defaultClipDuration

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

        // Dauer asynchron laden
        let asset = AVURLAsset(url: primaryURL)
        Task { [weak self] in
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

    deinit {}
}
