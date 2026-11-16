import SwiftUI
import SwiftData

struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]

    @State private var showingAddAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(playlists) { playlist in
                    NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                        HStack {
                            Image(systemName: "music.note.list")
                                .foregroundColor(.purple)
                            Text(playlist.name)
                                .font(.headline)
                            Spacer()
                            Text("\(playlist.tracks.count) треков")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        modelContext.delete(playlists[index])
                    }
                }
            }
            .navigationTitle("Плейлисты")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddAlert = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Новый плейлист", isPresented: $showingAddAlert) {
                TextField("Название", text: $newPlaylistName)
                Button("Создать") {
                    if !newPlaylistName.isEmpty {
                        let newPlaylist = Playlist(name: newPlaylistName)
                        modelContext.insert(newPlaylist)
                        newPlaylistName = ""
                    }
                }
                Button("Отмена", role: .cancel) {
                    newPlaylistName = ""
                }
            }
        }
    }
}
