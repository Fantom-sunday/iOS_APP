import SwiftUI
import SwiftData

struct RecommendationsView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Track> { $0.isFavorite }, sort: \Track.addedAt, order: .reverse)
    private var favorites: [Track]
    @Query private var library: [Track]
    @State private var recommendations: [SearchResultTrack] = []
    @State private var isLoading = false
    @State private var message = "Добавь пару любимых треков, и подберём похожее."
    private let search = YouTubeMusicSearchService()

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack { Spacer(); ProgressView("Подбираем музыку…"); Spacer() }
                        .listRowSeparator(.hidden)
                }
                if recommendations.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "Пока нет рекомендаций",
                        systemImage: "sparkles",
                        description: Text(message)
                    )
                    .listRowSeparator(.hidden)
                }
                ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, track in
                    Button {
                        playFrom(index: index)
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: track.artworkURL ?? "")) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                ZStack {
                                    Color.gray.opacity(0.15)
                                    Image(systemName: "music.note")
                                }
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title).lineLimit(1).foregroundStyle(.primary)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button {
                                saveToLibrary(track)
                            } label: {
                                Image(systemName: "plus.circle").font(.title3)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Для тебя")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadRecommendations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task { await loadRecommendations() }
            .miniPlayerInset()
        }
    }

    private func playFrom(index: Int) {
        let playable = recommendations.map { t in
            Track(
                title: t.title,
                artist: t.artist,
                album: t.album ?? "Рекомендации",
                duration: t.duration ?? 30,
                fileName: "",
                youtubeVideoID: t.youtubeVideoID
            )
        }
        player.play(playable, startAt: index)
    }

    private func saveToLibrary(_ track: SearchResultTrack) {
        let t = Track(
            title: track.title,
            artist: track.artist,
            album: track.album ?? "Рекомендации",
            duration: track.duration ?? 30,
            fileName: "",
            youtubeVideoID: track.youtubeVideoID
        )
        modelContext.insert(t)
        try? modelContext.save()
    }

    @MainActor
    private func loadRecommendations() async {
        guard !isLoading else { return }
        let seed = favorites.first ?? library.first
        guard let seed else {
            recommendations = []
            message = "Добавь треки в медиатеку и поставь сердечко хотя бы паре из них."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let results = try await search.search(query: seed.artist)
            let saved = Set(library.map { "\($0.title.lowercased())|\($0.artist.lowercased())" })
            recommendations = results.filter {
                !saved.contains("\($0.title.lowercased())|\($0.artist.lowercased())")
            }
            if recommendations.isEmpty {
                message = "Не удалось найти похожие треки. Попробуй обновить позже."
            }
        } catch {
            message = "Не удалось загрузить рекомендации. Проверь подключение к интернету."
        }
    }
}
