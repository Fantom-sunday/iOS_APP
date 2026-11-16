import Foundation
import SwiftData
import Observation


extension Track {
    var hasRemoteSource: Bool { streamingURL != nil || youtubeVideoID != nil }
    var isDownloaded: Bool { FileStore.exists(fileName) }
    var artworkCandidates: [String] {
        if let url = artworkURL, !url.isEmpty { return [url] }
        if let id = youtubeVideoID, !id.isEmpty {
            return ["https://i.ytimg.com/vi/\(id)/hq720.jpg", "https://i.ytimg.com/vi/\(id)/mqdefault.jpg"]
        }
        return []
    }
    var artworkSourceURL: String? { artworkCandidates.first }
}


@Observable
@MainActor
final class DownloadService {
    static let shared = DownloadService()

    private(set) var active: Set<UUID> = []
    private(set) var failed: Set<UUID> = []

    func isDownloading(_ track: Track) -> Bool { active.contains(track.id) }

    func trackSaved(_ track: Track) {
        let auto = UserDefaults.standard.object(forKey: "autoDownload") as? Bool ?? true
        Task { @MainActor in
            if auto {
                await download(track)
            } else {
                await cacheArtwork(for: track)
            }
        }
    }

    func download(_ track: Track) async {
        guard track.hasRemoteSource, !track.isDownloaded, !active.contains(track.id) else { return }
        active.insert(track.id)
        failed.remove(track.id)
        defer { active.remove(track.id) }

        await cacheArtwork(for: track)

        guard let source = await sourceURL(for: track) else {
            failed.insert(track.id)
            return
        }

        do {
            let (tmp, response) = try await URLSession.shared.download(from: source.url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            guard track.modelContext != nil else {
                try? FileManager.default.removeItem(at: tmp)
                return
            }
            let name = "\(track.id.uuidString).\(source.ext)"
            let dest = FileStore.musicDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            track.fileName = name
        } catch {
            failed.insert(track.id)
            print("Не удалось скачать «\(track.title)»: \(error)")
        }
    }

    func downloadAll(_ tracks: [Track]) async {
        for track in tracks where track.hasRemoteSource && !track.isDownloaded {
            await download(track)
        }
    }

    func removeDownload(_ track: Track) {
        guard track.hasRemoteSource else { return }
        FileStore.remove(fileName: track.fileName)
        track.fileName = ""
    }

    func cacheArtwork(for track: Track) async {
        guard track.artworkData == nil else { return }
        for string in track.artworkCandidates {
            guard let url = URL(string: string),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            guard track.modelContext != nil else { return }
            track.artworkData = ImportService.downscale(data) ?? data
            return
        }
    }

    private func sourceURL(for track: Track) async -> (url: URL, ext: String)? {
        if let string = track.streamingURL, let url = URL(string: string) {
            return (url, url.pathExtension.isEmpty ? "mp3" : url.pathExtension)
        }
        if let videoID = track.youtubeVideoID,
           let url = await StreamResolver.resolve(videoID: videoID) {
            return (url, "m4a")
        }
        return nil
    }
}


enum TrackSaver {
    @MainActor
    @discardableResult
    static func saveOrFetch(_ r: SearchResultTrack, defaultAlbum: String, in context: ModelContext) -> Track {
        let all = (try? context.fetch(FetchDescriptor<Track>())) ?? []

        if let vid = r.youtubeVideoID, !vid.isEmpty,
           let found = all.first(where: { $0.youtubeVideoID == vid }) {
            return found
        }
        if r.youtubeVideoID == nil,
           let found = all.first(where: {
               $0.title.lowercased() == r.title.lowercased() && $0.artist.lowercased() == r.artist.lowercased()
           }) {
            return found
        }

        let track = Track(
            title: r.title,
            artist: r.artist,
            album: r.album ?? defaultAlbum,
            duration: r.duration ?? 0,
            fileName: "",
            streamingURL: r.previewURL,
            youtubeVideoID: r.youtubeVideoID,
            artworkData: nil,
            artworkURL: r.artworkURL
        )
        context.insert(track)
        try? context.save()
        DownloadService.shared.trackSaved(track)
        return track
    }
}
