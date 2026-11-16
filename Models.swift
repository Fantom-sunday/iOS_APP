import Foundation
import SwiftData

@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var fileName: String
    var streamingURL: String?
    var youtubeVideoID: String?
    var addedAt: Date
    var isFavorite: Bool
    var artworkURL: String?
    @Attribute(.externalStorage) var artworkData: Data?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String,
        duration: Double,
        fileName: String,
        streamingURL: String? = nil,
        youtubeVideoID: String? = nil,
        artworkData: Data? = nil,
        artworkURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileName = fileName
        self.streamingURL = streamingURL
        self.youtubeVideoID = youtubeVideoID
        self.addedAt = Date()
        self.isFavorite = false
        self.artworkData = artworkData
    }
}
