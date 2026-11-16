import SwiftUI
import SwiftData

func formatTime(_ seconds: Double) -> String {
    let t = Int(seconds.isFinite ? seconds : 0)
    return String(format: "%d:%02d", t / 60, t % 60)
}

struct ArtworkView: View {
    let data: Data?
    var size: CGFloat
    var urlString: String? = nil

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil, let backup = Self.backupURL(for: urlString) {
                        AsyncImage(url: backup) { second in
                            if let image = second.image {
                                image.resizable().scaledToFill()
                            } else {
                                placeholder
                            }
                        }
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.1))
    }


    private static func backupURL(for string: String) -> URL? {
        guard string.contains("hq720") else { return nil }
        return URL(string: string.replacingOccurrences(of: "hq720", with: "mqdefault"))
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "music.note").foregroundStyle(.secondary)
        }
    }
}

extension ArtworkView {
    init(track: Track?, size: CGFloat) {
        self.init(data: track?.artworkData, size: size, urlString: track?.artworkSourceURL)
    }
}

struct TrackRow: View {
    let track: Track
    private let downloads = DownloadService.shared

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(track: track, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).lineLimit(1)
                Text("\(track.artist) · \(track.album)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if downloads.isDownloading(track) {
                ProgressView().controlSize(.small)
            } else if track.hasRemoteSource && track.isDownloaded {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green).font(.caption)
            }
            if track.isFavorite {
                Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(track.isFavorite ? "Убрать из избранного" : "В избранное",
                   systemImage: track.isFavorite ? "heart.slash" : "heart") {
                track.isFavorite.toggle()
            }
            if track.hasRemoteSource {
                if track.isDownloaded {
                    Button("Удалить загрузку", systemImage: "trash") {
                        downloads.removeDownload(track)
                    }
                } else {
                    Button("Скачать для офлайна", systemImage: "arrow.down.circle") {
                        Task { await downloads.download(track) }
                    }
                }
            }
            AddToPlaylistMenu(track: track)
        }
    }
}

struct AddToPlaylistMenu: View {
    let track: Track
    @Query private var playlists: [Playlist]

    var body: some View {
        Menu("Добавить в плейлист", systemImage: "text.badge.plus") {
            if playlists.isEmpty {
                Text("Сначала создайте плейлист")
            }
            ForEach(playlists) { p in
                Button(p.name) {
                    if !p.tracks.contains(where: { $0.id == track.id }) {
                        p.tracks.append(track)
                    }
                }
            }
        }
    }
}



struct MiniPlayerInset: ViewModifier {
    @Environment(PlayerService.self) private var player
    @State private var showFull = false

    func body(content: Content) -> some View {
        content
            .modifier(AppBackgroundModifier())
            .safeAreaInset(edge: .bottom) {
                if let track = player.currentTrack {
                    HStack(spacing: 12) {
                        ArtworkView(track: track, size: 40)
                        VStack(alignment: .leading) {
                            Text(track.title).lineLimit(1)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if player.isLoadingTrack {
                            ProgressView().tint(.secondary)
                        } else {
                            Button { player.togglePlayPause() } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                            }
                        }
                        Button { player.next() } label: {
                            Image(systemName: "forward.fill").font(.title3)
                        }
                        .disabled(player.isLoadingTrack)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .contentShape(Rectangle())
                    .onTapGesture { showFull = true }
                }
            }
            .sheet(isPresented: $showFull) { NowPlayingView() }
    }
}

extension View {
    func miniPlayerInset() -> some View { modifier(MiniPlayerInset()) }
}



struct NowPlayingView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.modelContext) private var modelContext
    @State private var scrubbing = false
    @State private var scrubValue = 0.0
    private let downloads = DownloadService.shared

    private var shownTime: Double { scrubbing ? scrubValue : player.currentTime }


    @ViewBuilder
    private func downloadButton(for track: Track) -> some View {
        if downloads.isDownloading(track) {
            ProgressView()
        } else if track.isDownloaded {
            Menu {
                Button("Удалить загрузку", systemImage: "trash", role: .destructive) {
                    downloads.removeDownload(track)
                }
            } label: {
                Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(.green)
            }
        } else {
            Button { startDownload(track) } label: {
                Image(systemName: "arrow.down.circle").font(.title2)
            }
        }
    }

    @MainActor
    private func startDownload(_ track: Track) {
        var target = track

        if track.modelContext == nil {
            let result = SearchResultTrack(
                title: track.title,
                artist: track.artist,
                album: track.album.isEmpty ? nil : track.album,
                duration: track.duration,
                artworkURL: track.artworkURL,
                source: "YouTube",
                previewURL: track.streamingURL,
                youtubeVideoID: track.youtubeVideoID
            )
            target = TrackSaver.saveOrFetch(result, defaultAlbum: "YouTube", in: modelContext)
            player.replaceCurrent(with: target)
        }
        Task { await downloads.download(target) }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()


            ZStack {
                ArtworkView(track: player.currentTrack, size: 300)
                    .shadow(radius: 12)
                if player.isLoadingTrack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.currentTrack?.title ?? "—").font(.title2.bold()).lineLimit(1)
                    Text(player.currentTrack?.artist ?? "").foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let track = player.currentTrack, track.hasRemoteSource {
                    downloadButton(for: track)
                        .padding(.trailing, 8)
                }
                if let track = player.currentTrack {
                    Button { track.isFavorite.toggle() } label: {
                        Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                            .font(.title2).foregroundStyle(.pink)
                    }
                }
            }
            .padding(.horizontal)

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { scrubbing ? scrubValue : player.currentTime },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...max(player.duration, 1)
                ) { editing in
                    if editing {
                        scrubValue = player.currentTime
                        scrubbing = true
                    } else {
                        player.seek(to: scrubValue)
                        scrubbing = false
                    }
                }
                .disabled(player.isLoadingTrack)

                HStack {
                    Text(formatTime(shownTime))
                    Spacer()
                    Text("-" + formatTime(max(0, player.duration - shownTime)))
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()

                if let message = player.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.horizontal)

            HStack(spacing: 44) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.title)
                }
                .disabled(player.isLoadingTrack)

                Button { player.togglePlayPause() } label: {
                    if player.isLoadingTrack {
                        ProgressView().scaleEffect(1.8).frame(width: 68, height: 68)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 68))
                    }
                }

                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title)
                }
                .disabled(player.isLoadingTrack)
            }
            .foregroundStyle(.primary)

            Spacer()
        }
        .padding()
        .background { AppBackground(grouped: false) }
        .presentationDragIndicator(.visible)
    }
}
