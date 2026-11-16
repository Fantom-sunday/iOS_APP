import SwiftUI
import SwiftData

@main
struct MusicApp: App {
    @State private var player = PlayerService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
        }
        .modelContainer(for: [Track.self, Playlist.self])
    }
}
