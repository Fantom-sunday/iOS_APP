import Foundation
import YouTubeKit


enum StreamResolver {
    private static let pipedInstances = [
        "https://pipedapi.ducks.party",
        "https://pipedapi.adminforge.de",
        "https://pipedapi.leptons.xyz"
    ]

    static func resolve(videoID: String) async -> URL? {
        do {
            let youtube = YouTube(videoID: videoID)
            let streams = try await youtube.streams
            let audioOnly = streams.filterAudioOnly().filter { $0.isNativelyPlayable }
            let withAudio = streams.filter { $0.includesAudioTrack && $0.isNativelyPlayable }

            let candidates: [YouTubeKit.Stream?] = [
                audioOnly.highestAudioBitrateStream(),
                audioOnly.lowestAudioBitrateStream(),
                withAudio.highestAudioBitrateStream(),
                withAudio.lowestAudioBitrateStream()
            ]

            for candidate in candidates {
                if let stream = candidate { return stream.url }
            }
        } catch {
            print("YouTubeKit ошибка: \(error)")
        }

        return await fetchFromPiped(videoID: videoID)
    }

    private static func fetchFromPiped(videoID: String) async -> URL? {
        for base in pipedInstances {
            guard let url = URL(string: "\(base)/streams/\(videoID)") else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let audioStreams = json["audioStreams"] as? [[String: Any]],
                      !audioStreams.isEmpty else { continue }

                let sorted = audioStreams
                    .filter { ($0["mimeType"] as? String)?.contains("mp4") == true }
                    .sorted { ($0["bitrate"] as? Int ?? 0) > ($1["bitrate"] as? Int ?? 0) }

                for stream in sorted {
                    if let urlString = stream["url"] as? String,
                       let streamURL = URL(string: urlString) {
                        return streamURL
                    }
                }
            } catch { continue }
        }
        return nil
    }
}
