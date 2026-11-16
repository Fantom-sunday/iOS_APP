import SwiftUI
import SwiftData

struct RemoteImage: View {
    let urlString: String?
    var size: CGFloat
    var circle = false

    var body: some View {
        AsyncImage(url: urlString.flatMap { URL(string: $0) }) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color.gray.opacity(0.2)
                Image(systemName: circle ? "person.fill" : "music.note")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: circle ? size / 2 : size * 0.1))
    }
}

struct SaveAlbumButton: View {
    let albumID: Int
    @Environment(\.modelContext) private var modelContext
    @State private var phase: Phase = .idle

    private enum Phase { case idle, loading, done, failed }

    var body: some View {
        Button {
            Task { @MainActor in await save() }
        } label: {
            switch phase {
            case .idle:
                Image(systemName: "arrow.down.circle").font(.title2)
            case .loading:
                ProgressView()
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.circle").font(.title2).foregroundStyle(.red)
            }
        }
        .buttonStyle(.borderless)
        .disabled(phase == .loading || phase == .done)
    }

    @MainActor
    private func save() async {
        phase = .loading
        let added = await LibraryImporter.saveAlbum(id: albumID, in: modelContext)
        phase = (added == nil) ? .failed : .done
    }
}

struct ArtistRow: View {
    let artist: ArtistResult

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(urlString: artist.pictureURL, size: 52, circle: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name).font(.headline).lineLimit(1)
                if let fans = artist.fans {
                    Text("Подписчики: \(fans.formatted(.number.notation(.compactName)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct AlbumRow: View {
    let album: AlbumResult
    var showArtist = true

    private var subtitle: String {
        var parts: [String] = []
        if showArtist, !album.artistName.isEmpty { parts.append(album.artistName) }
        if let type = album.typeLabel { parts.append(type) }
        if let year = album.year { parts.append(year) }
        if let count = album.trackCount, count > 0 { parts.append("треков: \(count)") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(urlString: album.coverURL, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title).font(.headline).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            SaveAlbumButton(albumID: album.id)
        }
        .padding(.vertical, 2)
    }
}

struct CatalogTrackRow: View {
    let track: SearchResultTrack
    let subtitle: String
    let isSaved: Bool
    var number: Int? = nil
    let onSave: () -> Void
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let number {
                Text("\(number)")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(width: 28)
            } else {
                RemoteImage(urlString: track.artworkURL, size: 50)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.headline).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            if isSaved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(.green)
            } else {
                Button(action: onSave) {
                    Image(systemName: "plus.circle").font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(track.previewURL == nil)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}


struct ArtistDetailView: View {
    let artist: ArtistResult

    @Environment(\.modelContext) private var modelContext
    @Environment(PlayerService.self) private var playerService
    @Query private var localTracks: [Track]

    @State private var info: ArtistResult?
    @State private var topTracks: [SearchResultTrack] = []
    @State private var albums: [AlbumResult] = []
    @State private var isLoading = true
    @State private var failed = false

    private let catalog = DeezerCatalog()

    var body: some View {
        let saved = SavedIndex(localTracks)
        let shown = info ?? artist

        List {
            VStack(spacing: 10) {
                RemoteImage(urlString: shown.pictureURL?.largeImage, size: 180, circle: true)
                    .shadow(radius: 8)
                Text(shown.name).font(.title2.bold()).multilineTextAlignment(.center)
                if let fans = shown.fans {
                    Text("Подписчики: \(fans.formatted(.number.notation(.compactName)))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)

            if !topTracks.isEmpty {
                Section("Популярные треки") {
                    ForEach(Array(topTracks.enumerated()), id: \.element.id) { index, track in
                        CatalogTrackRow(
                            track: track,
                            subtitle: track.album ?? "",
                            isSaved: saved.contains(track),
                            onSave: { save(track) },
                            onTap: {
                                playTracks(topTracks, albumName: shown.name, startAt: index)
                            }
                        )
                    }
                }
            }

            if !albums.isEmpty {
                Section("Дискография") {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            AlbumRow(album: album, showArtist: false)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(shown.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading && topTracks.isEmpty && albums.isEmpty {
                ProgressView()
            } else if failed {
                ContentUnavailableView("Не удалось загрузить", systemImage: "wifi.slash",
                                      description: Text("Проверь подключение к интернету."))
            }
        }
        .task { await load() }
        .miniPlayerInset()
    }

    private func playTracks(_ results: [SearchResultTrack], albumName: String, startAt index: Int) {
        let playable = results.map { t in
            Track(
                title: t.title,
                artist: t.artist,
                album: t.album ?? albumName,
                duration: t.duration ?? 30,
                fileName: "",
                streamingURL: t.previewURL
            )
        }
        playerService.play(playable, startAt: index)
    }

    @MainActor
    private func load() async {
        async let infoTask = try? await catalog.artist(id: artist.id)
        async let topTask = try? await catalog.topTracks(artistID: artist.id)
        async let albumsTask = try? await catalog.albums(artistID: artist.id, artistName: artist.name)

        let (loadedInfo, loadedTop, loadedAlbums) = await (infoTask, topTask, albumsTask)
        guard !Task.isCancelled else { return }

        info = loadedInfo
        topTracks = loadedTop ?? []
        albums = loadedAlbums ?? []
        failed = (loadedTop == nil && loadedAlbums == nil)
        isLoading = false
    }

    private func save(_ track: SearchResultTrack) {
        Task { @MainActor in
            await LibraryImporter.save([track], in: modelContext)
        }
    }
}


struct AlbumPreviewView: View {
    let album: AlbumResult

    @Environment(\.modelContext) private var modelContext
    @Environment(PlayerService.self) private var playerService
    @Query private var localTracks: [Track]

    @State private var details: AlbumDetails?
    @State private var isLoading = true
    @State private var failed = false
    @State private var isSaving = false

    private let catalog = DeezerCatalog()

    var body: some View {
        let saved = SavedIndex(localTracks)
        let tracks = details?.tracks ?? []
        let saveable = tracks.filter { $0.previewURL != nil }
        let allSaved = !saveable.isEmpty && saveable.allSatisfy { saved.contains($0) }
        let shown = details?.album ?? album

        List {
            VStack(spacing: 10) {
                RemoteImage(urlString: shown.coverURL?.largeImage, size: 200)
                    .shadow(radius: 8)
                Text(shown.title).font(.title3.bold()).multilineTextAlignment(.center)
                Text(shown.artistName).foregroundStyle(.secondary)
                Text(metaLine(for: shown, trackCount: tracks.count))
                    .font(.caption).foregroundStyle(.secondary)

                Button {
                    Task { @MainActor in await saveAll(tracks) }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Label(allSaved ? "Альбом в медиатеке" : "Сохранить альбом",
                              systemImage: allSaved ? "checkmark" : "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || allSaved || saveable.isEmpty)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                CatalogTrackRow(
                    track: track,
                    subtitle: "\(track.artist) · \(formatTime(track.duration ?? 0))",
                    isSaved: saved.contains(track),
                    number: index + 1,
                    onSave: { saveOne(track) },
                    onTap: {
                        playTracks(tracks, albumTitle: shown.title, startAt: index)
                    }
                )
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let artistID = shown.artistID {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: ArtistResult(id: artistID, name: shown.artistName)) {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if failed {
                ContentUnavailableView("Не удалось загрузить альбом", systemImage: "wifi.slash",
                                      description: Text("Проверь подключение к интернету."))
            }
        }
        .task { await load() }
        .miniPlayerInset()
    }

    private func playTracks(_ results: [SearchResultTrack], albumTitle: String, startAt index: Int) {
        let playable = results.map { t in
            Track(
                title: t.title,
                artist: t.artist,
                album: albumTitle,
                duration: t.duration ?? 30,
                fileName: "",
                streamingURL: t.previewURL
            )
        }
        playerService.play(playable, startAt: index)
    }

    private func metaLine(for album: AlbumResult, trackCount: Int) -> String {
        var parts: [String] = []
        if let type = album.typeLabel { parts.append(type) }
        if let year = album.year { parts.append(year) }
        let count = trackCount > 0 ? trackCount : (album.trackCount ?? 0)
        if count > 0 { parts.append("треков: \(count)") }
        return parts.joined(separator: " · ")
    }

    @MainActor
    private func load() async {
        do {
            let loaded = try await catalog.album(id: album.id)
            guard !Task.isCancelled else { return }
            details = loaded
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
        isLoading = false
    }

    @MainActor
    private func saveAll(_ tracks: [SearchResultTrack]) async {
        isSaving = true
        await LibraryImporter.save(tracks, albumArtist: (details?.album ?? album).artistName, in: modelContext)
        isSaving = false
    }

    private func saveOne(_ track: SearchResultTrack) {
        Task { @MainActor in
            await LibraryImporter.save([track], albumArtist: (details?.album ?? album).artistName, in: modelContext)
        }
    }
}
