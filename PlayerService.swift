import Foundation
import AVFoundation
import Observation
import MediaPlayer
import UIKit
import YouTubeKit

@Observable
final class PlayerService {
    @ObservationIgnored private let player = AVPlayer()

    var queue: [Track] = []
    var currentIndex: Int = 0
    var currentTime: TimeInterval = 0
    var duration: Double = 0
    var isPlaying = false
    var isShuffling = false
    var errorMessage: String?
    var isLoadingTrack = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var rateObserver: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var itemFailObserver: NSObjectProtocol?
    @ObservationIgnored private var itemStatusObserver: NSKeyValueObservation?
    @ObservationIgnored private var loadToken = UUID()

    init() {
        setupAudioSession()
        setupRemoteCommands()

        rateObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            DispatchQueue.main.async {
                self?.isPlaying = playing
                self?.updateNowPlaying()
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            if seconds.isFinite { self.currentTime = seconds }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let item = notification.object as? AVPlayerItem,
                  item === self.player.currentItem else { return }
            self.next()
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let itemFailObserver { NotificationCenter.default.removeObserver(itemFailObserver) }
        itemStatusObserver?.invalidate()
        MPRemoteCommandCenter.shared().playCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.removeTarget(nil)
    }

    var currentTrack: Track? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }


    func play(_ tracks: [Track], startAt index: Int = 0) {
        guard !tracks.isEmpty, tracks.indices.contains(index) else { return }
        queue = tracks
        load(index)
    }

    func togglePlayPause() {
        if player.currentItem == nil {
            if currentTrack != nil { load(currentIndex) }
            return
        }
        if player.timeControlStatus == .paused {
            player.play()
        } else {
            player.pause()
        }
    }

    func seek(to time: TimeInterval) {
        guard player.currentItem != nil else { return }
        let upper = duration > 0 ? duration : time
        let target = min(max(0, time), upper)
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func next() {
        if currentIndex + 1 < queue.count {
            load(currentIndex + 1)
        } else {
            player.pause()
            seek(to: 0)
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 || currentIndex == 0 {
            seek(to: 0)
        } else {
            load(currentIndex - 1)
        }
    }

    func toggleShuffle() {
        guard queue.count > 1, let current = currentTrack else { return }
        isShuffling.toggle()
        let remaining = queue.enumerated().filter { $0.offset != currentIndex }.map(\.element)
        let reordered = isShuffling ? remaining.shuffled() : remaining.sorted { $0.addedAt < $1.addedAt }
        queue = [current] + reordered
        currentIndex = 0
    }

    func replaceCurrent(with track: Track) {
        guard queue.indices.contains(currentIndex) else { return }
        queue[currentIndex] = track
    }


    private func load(_ index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        currentTime = 0
        errorMessage = nil
        duration = 0

        if let obs = itemFailObserver {
            NotificationCenter.default.removeObserver(obs)
            itemFailObserver = nil
        }
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil

        let token = UUID()
        loadToken = token

        let track = queue[index]

        if let local = FileStore.url(for: track.fileName) {
            isLoadingTrack = true
            player.replaceCurrentItem(with: nil)
            startAudio(url: local, token: token)
            return
        }

        if let urlString = track.streamingURL, let url = URL(string: urlString) {
            isLoadingTrack = true
            player.replaceCurrentItem(with: nil)
            startAudio(url: url, token: token)
            return
        }

        guard let videoID = track.youtubeVideoID else {
            errorMessage = "Нет источника для «\(track.title)»"
            player.pause()
            return
        }

        isLoadingTrack = true
        player.replaceCurrentItem(with: nil)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let url = await StreamResolver.resolve(videoID: videoID)
            guard self.loadToken == token else { return }
            if let url {
                self.startAudio(url: url, token: token)
            } else {
                self.errorMessage = "Не удалось загрузить «\(track.title)»"
                self.isLoadingTrack = false
            }
        }
    }

    private func startAudio(url: URL, token: UUID) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        itemFailObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.errorMessage = "Ошибка воспроизведения"
            self?.isLoadingTrack = false
        }

        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let reason = item.error?.localizedDescription ?? "неизвестная ошибка"
            print("AVPlayerItem failed: \(String(describing: item.error))")
            DispatchQueue.main.async {
                guard let self, self.loadToken == token else { return }
                self.errorMessage = "Не удалось воспроизвести: \(reason)"
                self.isLoadingTrack = false
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let dur = try? await asset.load(.duration).seconds,
               dur.isFinite, dur > 0 {
                guard self.loadToken == token else { return }
                let known = self.currentTrack?.duration ?? 0
                if known > 0, abs(dur - known * 2) < max(3, known * 0.05) {
                    self.duration = known
                } else {
                    self.duration = dur
                }
            }
            guard self.loadToken == token else { return }
            self.player.replaceCurrentItem(with: item)
            self.player.play()
            self.isLoadingTrack = false
            self.updateNowPlaying()
        }
    }


    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("PlayerService: ошибка AVAudioSession: \(error)")
        }
    }


    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.player.play(); return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause(); return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause(); return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.next(); return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous(); return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
    }


    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let data = track.artworkData, let img = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
