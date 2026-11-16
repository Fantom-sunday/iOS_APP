import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    @Bindable var playlist: Playlist
    @Environment(\.modelContext) private var modelContext
    @Environment(PlayerService.self) private var player
    @State private var showingAddTracksSheet = false

    var body: some View {
        List {
            if playlist.tracks.isEmpty {
                ContentUnavailableView(
                    "Плейлист пуст",
                    systemImage: "music.note.list",
                    description: Text("Нажми на плюс сверху, чтобы добавить треки")
                )
            } else {
                ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        player.play(playlist.tracks, startAt: index)
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkView(data: track.artworkData, size: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text(track.artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if track.isFavorite {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.pink)
                                    .font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("В избранное", systemImage: track.isFavorite ? "heart.slash" : "heart") {
                            track.isFavorite.toggle()
                        }
                    }
                }
                .onDelete { indexSet in
                    playlist.tracks.remove(atOffsets: indexSet)
                }
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !playlist.tracks.isEmpty {
                    Button {
                        player.play(playlist.tracks)
                    } label: {
                        Label("Слушать", systemImage: "play.fill")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddTracksSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showingAddTracksSheet) {
            AddTracksToPlaylistView(playlist: playlist)
        }
        .miniPlayerInset()
    }
}
