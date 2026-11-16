import SwiftUI
import SwiftData

struct AlbumGroup: Identifiable, Hashable {
    let id: String
    let album: String
    let artist: String
    let tracks: [Track]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: AlbumGroup, r: AlbumGroup) -> Bool { l.id == r.id }
}

struct AlbumsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Track.addedAt) private var tracks: [Track]

    private var albums: [AlbumGroup] {
        Dictionary(grouping: tracks) { "\($0.album)|\($0.artist)" }
            .map { key, items in
                AlbumGroup(id: key, album: items[0].album, artist: items[0].artist, tracks: items)
            }
            .sorted { $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(albums) { group in
                    NavigationLink(value: group) {
                        HStack(spacing: 12) {
                            ArtworkView(data: group.tracks.first?.artworkData, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.album).lineLimit(1)
                                Text("\(group.artist) · треков: \(group.tracks.count)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteAlbums)
            }
            .overlay {
                if albums.isEmpty {
                    ContentUnavailableView("Нет альбомов", systemImage: "square.stack",
                                           description: Text("Альбомы появятся после импорта треков"))
                }
            }
            .navigationTitle("Альбомы")
            .navigationDestination(for: AlbumGroup.self) { AlbumDetailView(album: $0) }
            .miniPlayerInset()
        }
    }

    private func deleteAlbums(at offsets: IndexSet) {
        for index in offsets {
            let group = albums[index]
            for track in group.tracks {
                modelContext.delete(track)
            }
        }
    }
}

struct AlbumDetailView: View {
    let album: AlbumGroup
    @Environment(PlayerService.self) private var player
    @Environment(\.modelContext) private var modelContext
    private var allFavorite: Bool { album.tracks.allSatisfy(\.isFavorite) }

    var body: some View {
        List {
            VStack(spacing: 12) {
                ArtworkView(data: album.tracks.first?.artworkData, size: 200)
                Text(album.album).font(.title3.bold())
                Text(album.artist).foregroundStyle(.secondary)
                Button("Слушать", systemImage: "play.fill") { player.play(album.tracks) }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)

            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                Button { player.play(album.tracks, startAt: index) } label: {
                    TrackRow(track: track)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteTracks)
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let value = !allFavorite
                    album.tracks.forEach { $0.isFavorite = value }
                } label: {
                    Image(systemName: allFavorite ? "heart.fill" : "heart")
                }
            }
        }
    }

    private func deleteTracks(at offsets: IndexSet) {
        for index in offsets {
            let trackToDelete = album.tracks[index]
            modelContext.delete(trackToDelete)
        }
    }
}
