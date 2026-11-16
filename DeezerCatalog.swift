import Foundation
import SwiftData


struct ArtistResult: Identifiable, Hashable {
    let id: Int
    let name: String
    var pictureURL: String?
    var fans: Int?
}

struct AlbumResult: Identifiable, Hashable {
    let id: Int
    let title: String
    var artistName: String
    var artistID: Int?
    var coverURL: String?
    var trackCount: Int?
    var releaseDate: String?
    var recordType: String?

    var year: String? {
        guard let date = releaseDate, date.count >= 4 else { return nil }
        let y = String(date.prefix(4))
        return y == "0000" ? nil : y
    }

    var typeLabel: String? {
        switch recordType ?? "" {
        case "single": return "Сингл"
        case "ep": return "EP"
        case "compile": return "Сборник"
        case "album": return "Альбом"
        default: return nil
        }
    }
}

struct AlbumDetails {
    let album: AlbumResult
    let tracks: [SearchResultTrack]
}

extension String {
    var largeImage: String {
        replacingOccurrences(of: "250x250", with: "500x500")
    }
}


private struct DZList<T: Decodable>: Decodable {
    let data: [T]
}

private struct DZArtist: Decodable {
    let id: Int
    let name: String
    let picture_medium: String?
    let nb_fan: Int?
}

private struct DZAlbum: Decodable {
    let id: Int
    let title: String
    let cover_medium: String?
    let nb_tracks: Int?
    let release_date: String?
    let record_type: String?
    let artist: DZArtist?
}

private struct DZTrack: Decodable {
    let id: Int
    let title: String
    let duration: Int?
    let preview: String?
    let artist: DZArtist?
    let album: DZAlbum?
}

private struct DZAlbumFull: Decodable {
    let id: Int
    let title: String
    let cover_medium: String?
    let nb_tracks: Int?
    let release_date: String?
    let record_type: String?
    let artist: DZArtist?
    let tracks: DZList<DZTrack>?
}


struct DeezerCatalog {
    private static let unreserved = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var components = URLComponents(string: "https://api.deezer.com" + path)
        if !query.isEmpty {
            components?.percentEncodedQueryItems = query.map { key, value in
                URLQueryItem(
                    name: key,
                    value: value.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? value
                )
            }
        }
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }


    func searchTracks(_ query: String) async throws -> [SearchResultTrack] {
        let list: DZList<DZTrack> = try await get("/search", query: ["q": query, "limit": "30"])
        return list.data.map { makeTrack($0) }
    }

    func searchArtists(_ query: String) async throws -> [ArtistResult] {
        let list: DZList<DZArtist> = try await get("/search/artist", query: ["q": query, "limit": "20"])
        return list.data.map { makeArtist($0) }
    }

    func searchAlbums(_ query: String) async throws -> [AlbumResult] {
        let list: DZList<DZAlbum> = try await get("/search/album", query: ["q": query, "limit": "30"])
        return list.data.map { makeAlbum($0) }
    }


    func artist(id: Int) async throws -> ArtistResult {
        let dz: DZArtist = try await get("/artist/\(id)")
        return makeArtist(dz)
    }

    func topTracks(artistID: Int, limit: Int = 10) async throws -> [SearchResultTrack] {
        let list: DZList<DZTrack> = try await get("/artist/\(artistID)/top", query: ["limit": String(limit)])
        return list.data.map { makeTrack($0) }
    }

    func albums(artistID: Int, artistName: String) async throws -> [AlbumResult] {
        let list: DZList<DZAlbum> = try await get("/artist/\(artistID)/albums", query: ["limit": "100"])
        return list.data
            .map { makeAlbum($0, artistName: artistName, artistID: artistID) }
            .sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    }


    func album(id: Int) async throws -> AlbumDetails {
        let full: DZAlbumFull = try await get("/album/\(id)")
        let allTracks: DZList<DZTrack>? = try? await get("/album/\(id)/tracks", query: ["limit": "200"])

        let album = AlbumResult(
            id: full.id,
            title: full.title,
            artistName: full.artist?.name ?? "",
            artistID: full.artist?.id,
            coverURL: full.cover_medium,
            trackCount: full.nb_tracks,
            releaseDate: full.release_date,
            recordType: full.record_type
        )
        let dzTracks = allTracks?.data ?? full.tracks?.data ?? []
        return AlbumDetails(album: album, tracks: dzTracks.map { makeTrack($0, album: album) })
    }


    private func makeArtist(_ a: DZArtist) -> ArtistResult {
        ArtistResult(id: a.id, name: a.name, pictureURL: a.picture_medium, fans: a.nb_fan)
    }

    private func makeAlbum(_ a: DZAlbum, artistName: String? = nil, artistID: Int? = nil) -> AlbumResult {
        AlbumResult(
            id: a.id,
            title: a.title,
            artistName: a.artist?.name ?? artistName ?? "",
            artistID: a.artist?.id ?? artistID,
            coverURL: a.cover_medium,
            trackCount: a.nb_tracks,
            releaseDate: a.release_date,
            recordType: a.record_type
        )
    }

    private func makeTrack(_ t: DZTrack, album: AlbumResult? = nil) -> SearchResultTrack {
        let preview = (t.preview?.isEmpty == false) ? t.preview : nil
        return SearchResultTrack(
            title: t.title,
            artist: t.artist?.name ?? album?.artistName ?? "Неизвестный исполнитель",
            album: t.album?.title ?? album?.title,
            duration: t.duration.map { Double($0) },
            artworkURL: t.album?.cover_medium ?? album?.coverURL,
            source: "Deezer",
            previewURL: preview,
            artistID: t.artist?.id ?? album?.artistID,
            albumID: t.album?.id ?? album?.id
        )
    }
}


struct SavedIndex {
    private let keys: Set<String>

    init(_ tracks: [Track]) {
        keys = Set(tracks.map { LibraryImporter.key(title: $0.title, album: $0.album) })
    }

    func contains(_ track: SearchResultTrack) -> Bool {
        keys.contains(LibraryImporter.key(title: track.title, album: track.album ?? "Неизвестный альбом"))
    }
}


enum LibraryImporter {
    static func key(title: String, album: String) -> String {
        "\(title.lowercased())|\(album.lowercased())"
    }

    @MainActor
    @discardableResult
    static func save(_ items: [SearchResultTrack], albumArtist: String? = nil, in context: ModelContext) async -> Int {
        let existing = (try? context.fetch(FetchDescriptor<Track>())) ?? []
        var known = Set(existing.map { key(title: $0.title, album: $0.album) })

        var covers: [String: Data] = [:]
        var failedCovers: Set<String> = []
        var added = 0

        for item in items {
            guard let preview = item.previewURL else { continue }
            let albumName = item.album ?? "Неизвестный альбом"
            let itemKey = key(title: item.title, album: albumName)
            guard !known.contains(itemKey) else { continue }
            known.insert(itemKey)

            var artwork: Data?
            if let urlString = item.artworkURL, !failedCovers.contains(urlString) {
                if let cached = covers[urlString] {
                    artwork = cached
                } else if let data = await downloadImage(urlString.largeImage) {
                    covers[urlString] = data
                    artwork = data
                } else {
                    failedCovers.insert(urlString)
                }
            }

            let track = Track(
                title: item.title,
                artist: albumArtist ?? item.artist,
                album: albumName,
                duration: item.duration ?? 30,
                fileName: "",
                streamingURL: preview,
                artworkData: artwork
            )
            context.insert(track)
            added += 1
        }

        if added > 0 { try? context.save() }
        return added
    }

    @MainActor
    static func saveAlbum(id: Int, in context: ModelContext) async -> Int? {
        guard let details = try? await DeezerCatalog().album(id: id) else { return nil }
        return await save(details.tracks, albumArtist: details.album.artistName, in: context)
    }

    private static func downloadImage(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
