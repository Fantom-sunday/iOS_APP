import SwiftUI
import SwiftData

struct SongsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlayerService.self) private var playerService

    @State private var searchText = ""
    @State private var tracks: [SearchResultTrack] = []
    @State private var isLoading = false
    @State private var failed = false
    @State private var lastQuery = ""

    private let search = YouTubeMusicSearchService()

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: track.artworkURL ?? "")) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ZStack {
                                Color.gray.opacity(0.2)
                                Image(systemName: "music.note")
                            }
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).lineLimit(1)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }

                        Spacer()

                        Button {
                            save(track)
                        } label: {
                            Image(systemName: "plus.circle").font(.title2)
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playTracks(tracks, startAt: index)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if isLoading && tracks.isEmpty {
                    ProgressView()
                } else if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("Найди музыку", systemImage: "magnifyingglass",
                                           description: Text("Введи название трека или исполнителя"))
                } else if failed {
                    ContentUnavailableView("Не удалось загрузить", systemImage: "wifi.slash",
                                           description: Text("Проверь подключение к интернету"))
                } else if tracks.isEmpty {
                    ContentUnavailableView("Ничего не найдено", systemImage: "music.note",
                                           description: Text("Попробуй изменить запрос"))
                }
            }
            .navigationTitle("Поиск")
            .searchable(text: $searchText, prompt: "Трек или исполнитель")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .task(id: searchText) {
                if searchText != lastQuery {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                }
                lastQuery = searchText
                await runSearch()
            }
            .miniPlayerInset()
        }
    }

    private func playTracks(_ results: [SearchResultTrack], startAt index: Int) {
        let playable = results.map { t in
            Track(
                title: t.title,
                artist: t.artist,
                album: t.album ?? "",
                duration: t.duration ?? 0,
                fileName: "",
                streamingURL: nil,
                youtubeVideoID: t.youtubeVideoID
            )
        }
        playerService.play(playable, startAt: index)
    }

    private func save(_ track: SearchResultTrack) {
        Task { @MainActor in
            let newTrack = Track(
                title: track.title,
                artist: track.artist,
                album: track.album ?? "YouTube",
                duration: track.duration ?? 0,
                fileName: "",
                streamingURL: nil,
                youtubeVideoID: track.youtubeVideoID
            )
            modelContext.insert(newTrack)
            try? modelContext.save()
        }
    }

    @MainActor
    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            tracks = []
            isLoading = false
            failed = false
            return
        }

        isLoading = true
        failed = false
        do {
            let result = try await search.search(query: query)
            guard !Task.isCancelled else { return }
            tracks = result
        } catch {
            guard !Task.isCancelled else { return }
            tracks = []
            failed = true
            print("Ошибка поиска: \(error)")
        }
        isLoading = false
    }
}
