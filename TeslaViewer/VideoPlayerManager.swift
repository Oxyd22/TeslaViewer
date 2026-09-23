//
//  VideoPlayerManager.swift
//  TeslaViewer
//
//  Verwaltet synchrone AVPlayer-Instanzen über die durchgehende Zeitachse eines Ereignisses.
//

import AVFoundation
import CoreMedia

@MainActor
@Observable
final class VideoPlayerManager {
    private(set) var players: [String: AVPlayer] = [:]
    private(set) var duration: Double = 0
    private(set) var clipBoundaries: [Double] = []
    private(set) var triggerOffset: Double?
    private(set) var isLoading = false

    var isPlaying = false
    var currentTime: Double = 0
    var isSeeking = false

    private var trackingPlayer: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?

    func load(_ event: SentryEvent) async {
        tearDown()
        isLoading = true
        let composition = await EventCompositionBuilder.make(for: event)
        isLoading = false

        var newPlayers: [String: AVPlayer] = [:]
        for (camera, item) in composition.items {
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            player.isMuted = camera != "front"
            newPlayers[camera] = player
        }
        players = newPlayers
        duration = composition.duration
        clipBoundaries = composition.clipBoundaries
        triggerOffset = composition.triggerOffset

        trackingPlayer = newPlayers["front"] ?? newPlayers.values.first
        guard let trackingPlayer else { return }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = trackingPlayer.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite { self.currentTime = max(0, seconds) }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: trackingPlayer.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
                self?.players.values.forEach { $0.pause() }
            }
        }
    }

    func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            playSynchronized()
        } else {
            players.values.forEach { $0.pause() }
        }
    }

    /// Sucht alle Kameras zum selben Zeitpunkt an. `precise` erzwingt exakte Frametreue
    /// (langsamer); beim Ziehen des Sliders reicht eine Toleranz für flüssiges Scrubbing.
    func seek(to time: Double, precise: Bool) {
        let clamped = max(0, min(time, duration))
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        let tolerance = precise ? CMTime.zero : CMTime(seconds: 0.25, preferredTimescale: 600)
        for player in players.values {
            player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
        currentTime = clamped
    }

    func step(by seconds: Double) {
        seek(to: currentTime + seconds, precise: true)
    }

    func jumpToTrigger() {
        guard let triggerOffset else { return }
        seek(to: triggerOffset, precise: true)
    }

    func tearDown() {
        if let timeObserverToken, let trackingPlayer {
            trackingPlayer.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        players.values.forEach { $0.pause() }
        players = [:]
        trackingPlayer = nil
        duration = 0
        clipBoundaries = []
        triggerOffset = nil
        currentTime = 0
        isPlaying = false
    }

    /// Startet alle Kameras exakt zum selben Host-Zeitpunkt, statt jeder für sich, sobald
    /// ihr eigener Puffer bereit ist — sonst laufen die 6 Feeds sichtbar gegeneinander.
    private func playSynchronized() {
        guard let trackingPlayer else { return }
        let itemTime = trackingPlayer.currentTime()
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
            + CMTime(seconds: 0.15, preferredTimescale: 600)
        for player in players.values {
            player.setRate(1, time: itemTime, atHostTime: hostTime)
        }
    }
}
