import Foundation

struct SearchResultTrack: Identifiable {
    let id: UUID
    let title: String
    let artist: String
    let album: String?
    let duration: Double?
    let artworkURL: String?
    let source: String
    let previewURL: String?
    let artistID: Int?
    let albumID: Int?
    let youtubeVideoID: String?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String? = nil,
        duration: Double? = nil,
        artworkURL: String? = nil,
        source: String,
        previewURL: String? = nil,
        artistID: Int? = nil,
        albumID: Int? = nil,
        youtubeVideoID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
        self.source = source
        self.previewURL = previewURL
        self.artistID = artistID
        self.albumID = albumID
        self.youtubeVideoID = youtubeVideoID
    }
}

protocol MusicSearchProvider {
    var name: String { get }
    func search(query: String) async throws -> [SearchResultTrack]
}

final class ITunesMusicProvider: MusicSearchProvider {
    var name: String { "Apple Music / iTunes" }

    func search(query: String) async throws -> [SearchResultTrack] {
        guard
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://itunes.apple.com/search?term=\(encodedQuery)&entity=song&limit=20")
        else { return [] }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }

        let decoded = try JSONDecoder().decode(ITunesResponse.self, from: data)
        return decoded.results.map { item in
            SearchResultTrack(
                title: item.trackName,
                artist: item.artistName,
                album: item.collectionName,
                duration: item.trackTimeMillis.map { Double($0) / 1000.0 },
                artworkURL: item.artworkUrl100,
                source: "iTunes",
                previewURL: item.previewUrl
            )
        }
    }
}

private struct ITunesResponse: Decodable {
    let results: [ITunesItem]
}

private struct ITunesItem: Decodable {
    let trackName: String
    let artistName: String
    let collectionName: String?
    let trackTimeMillis: Int?
    let artworkUrl100: String?
    let previewUrl: String?
}

final class DeezerMusicProvider: MusicSearchProvider {
    var name: String { "Deezer" }

    func search(query: String) async throws -> [SearchResultTrack] {
        guard
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://api.deezer.com/search?q=\(encodedQuery)")
        else { return [] }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }

        let decoded = try JSONDecoder().decode(DeezerResponse.self, from: data)
        return decoded.data.map { item in
            SearchResultTrack(
                title: item.title,
                artist: item.artist.name,
                album: item.album.title,
                duration: Double(item.duration),
                artworkURL: item.album.cover_medium,
                source: "Deezer",
                previewURL: item.preview
            )
        }
    }
}

private struct DeezerResponse: Decodable {
    let data: [DeezerTrack]
}

private struct DeezerTrack: Decodable {
    let title: String
    let duration: Int
    let preview: String?
    let artist: DeezerArtist
    let album: DeezerAlbum
}

private struct DeezerArtist: Decodable {
    let name: String
}

private struct DeezerAlbum: Decodable {
    let title: String
    let cover_medium: String?
}

final class CombinedMusicSearchService: MusicSearchProvider {
    var name: String { "Все источники" }

    private let providers: [MusicSearchProvider] = [
        ITunesMusicProvider(),
        DeezerMusicProvider()
    ]

    func search(query: String) async throws -> [SearchResultTrack] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        return await withTaskGroup(of: [SearchResultTrack].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.search(query: trimmedQuery)
                    } catch {
                        print("Ошибка поиска (\(provider.name)): \(error)")
                        return []
                    }
                }
            }

            var allTracks: [SearchResultTrack] = []
            for await tracks in group {
                allTracks.append(contentsOf: tracks)
            }
            return allTracks
        }
    }
}
