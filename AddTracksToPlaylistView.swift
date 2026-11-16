import SwiftUI
import SwiftData

struct AddTracksToPlaylistView: View {
    let playlist: Playlist
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Track.addedAt, order: .reverse) private var savedTracks: [Track]

    @State private var searchText = ""
    @State private var searchResults: [SearchResultTrack] = []
    @State private var isSearching = false

    private let searchProvider = CombinedMusicSearchService()

    var body: some View {
        NavigationStack {
            VStack {
                if searchText.isEmpty {

                    if savedTracks.isEmpty {
                        ContentUnavailableView(
                            "Нет сохраненных треков",
                            systemImage: "folder.badge.questionmark",
                            description: Text("Сначала найди музыку через поиск и сохрани её")
                        )
                    } else {
                        List(savedTracks) { track in
                            let isAlreadyAdded = playlist.tracks.contains(where: { $0.id == track.id })
                            HStack {
                                ArtworkView(data: track.artworkData, size: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title).font(.headline)
                                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(action: {
                                    if !isAlreadyAdded {
                                        playlist.tracks.append(track)
                                    }
                                }) {
                                    Image(systemName: isAlreadyAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(isAlreadyAdded ? .green : .blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    if isSearching {
                        ProgressView("Ищем в сети...")
                            .frame(maxHeight: .infinity)
                    } else if searchResults.isEmpty {
                        ContentUnavailableView(
                            "Ничего не найдено",
                            systemImage: "magnifyingglass",
                            description: Text("Попробуй изменить запрос")
                        )
                    } else {
                        List(searchResults) { searchTrack in
                            HStack {
                                AsyncImage(url: URL(string: searchTrack.artworkURL ?? "")) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    ZStack {
                                        Color.gray.opacity(0.2)
                                        Image(systemName: "music.note").foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(searchTrack.title).font(.headline).lineLimit(1)
                                    Text(searchTrack.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                }

                                Spacer()

                                Text(searchTrack.source)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.2))
                                    .clipShape(Capsule())

                                Button(action: {
                                    addOnlineTrackToPlaylist(searchTrack)
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Добавить в плейлист")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Поиск по сохраненным или в сети...")
            .onChange(of: searchText) { _, newValue in
                performSearch(query: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        Task {
            do {
                let results = try await searchProvider.search(query: trimmed)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                }
            }
        }
    }

    private func addOnlineTrackToPlaylist(_ searchTrack: SearchResultTrack) {

        let newTrack = Track(
            title: searchTrack.title,
            artist: searchTrack.artist,
            album: searchTrack.album ?? "Неизвестный альбом",
            duration: searchTrack.duration ?? 0.0,
            fileName: "",
            streamingURL: searchTrack.previewURL,
            youtubeVideoID: searchTrack.youtubeVideoID,
            artworkData: nil
        )
        modelContext.insert(newTrack)
        playlist.tracks.append(newTrack)
    }
}
