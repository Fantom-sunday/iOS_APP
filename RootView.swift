import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Медиатека", systemImage: "square.stack") }

            SongsView()
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }

            AlbumsView()
                .tabItem { Label("Альбомы", systemImage: "square.stack.3d.up") }

            MoodRootView()
                .tabItem { Label("Место", systemImage: "sensor.tag.radiowaves.forward.fill") }

            RecommendationsView()
                .tabItem { Label("Для тебя", systemImage: "sparkles") }

            PlaylistsView()
                .tabItem { Label("Плейлисты", systemImage: "music.note.list") }

            FavoritesView()
                .tabItem { Label("Избранное", systemImage: "heart") }
        }
        .tint(.green)
    }
}
