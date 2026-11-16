import Foundation

struct YouTubeMusicSearchService {

    private let instances = [
        "https://pipedapi.ducks.party",
        "https://pipedapi.adminforge.de",
        "https://pipedapi.leptons.xyz"
    ]

    func search(query: String) async throws -> [SearchResultTrack] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        for base in instances {
            guard let url = URL(string: "\(base)/search?q=\(encoded)&filter=videos") else { continue }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }

                let results = parseResults(data: data)
                if !results.isEmpty {
                    return results
                }
            } catch {
                continue
            }
        }

        return []
    }

    private func parseResults(data: Data) -> [SearchResultTrack] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }

        var results: [SearchResultTrack] = []

        for item in items {
            let type = item["type"] as? String ?? ""
            guard type == "stream" || type == "video" else { continue }

            let title = item["title"] as? String ?? "Без названия"
            let uploader = item["uploaderName"] as? String ?? "YouTube"
            let duration = item["duration"] as? Double ?? 0
            let thumbnail = item["thumbnail"] as? String

            var videoId: String? = nil
            if let urlString = item["url"] as? String {
                if let range = urlString.range(of: "v=") {
                    videoId = String(urlString[range.upperBound...])
                } else if urlString.count == 11 {
                    videoId = urlString
                } else if let last = urlString.split(separator: "/").last, last.count == 11 {
                    videoId = String(last)
                }
            }

            if videoId == nil {
                videoId = item["id"] as? String
            }

            guard let videoId, !videoId.isEmpty else { continue }

            let track = SearchResultTrack(
                title: title,
                artist: uploader,
                album: nil,
                duration: duration,
                artworkURL: thumbnail,
                source: "YouTube Music",
                previewURL: nil,
                youtubeVideoID: videoId
            )
            results.append(track)
        }

        return results
    }
}
