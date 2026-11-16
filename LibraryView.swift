import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Track.addedAt, order: .reverse) private var tracks: [Track]
    @State private var query = ""
    @State private var showImporter = false

    private var filtered: [Track] {
        guard !query.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.artist.localizedCaseInsensitiveContains(query) ||
            $0.album.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    ContentUnavailableView("Медиатека пуста", systemImage: "music.note",
                        description: Text("Найди музыку во вкладке «Поиск» или импортируй аудиофайлы."))
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, track in
                        Button { player.play(filtered, startAt: index) } label: { TrackRow(track: track) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        offsets.map { filtered[$0] }.forEach(modelContext.delete)
                        try? modelContext.save()
                    }
                }
            }
            .searchable(text: $query, prompt: "Треки, исполнители, альбомы")
            .navigationTitle("Медиатека")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Слушать", systemImage: "play.fill") { player.play(filtered) }
                        .disabled(filtered.isEmpty)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .mp3, .mpeg4Audio], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await ImportService.importFiles(urls, into: modelContext) }
                }
            }
            .miniPlayerInset()
        }
    }
}
