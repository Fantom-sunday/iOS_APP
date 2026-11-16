import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Environment(PlayerService.self) private var player
    @Query(filter: #Predicate<Track> { $0.isFavorite }, sort: \Track.title)
    private var tracks: [Track]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button { player.play(tracks, startAt: index) } label: {
                        TrackRow(track: track)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if tracks.isEmpty {
                    ContentUnavailableView("Нет избранного", systemImage: "heart",
                                           description: Text("Зажми трек и выбери «В избранное»"))
                }
            }
            .navigationTitle("Избранное")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Слушать", systemImage: "play.fill") { player.play(tracks) }
                        .disabled(tracks.isEmpty)
                }
            }
            .miniPlayerInset()
        }
    }
}
