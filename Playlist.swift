import Foundation
import SwiftData

@Model
final class Playlist {
    var id: UUID = UUID()
    var name: String
    var tracks: [Track] = []
    var createdAt: Date = Date()

    init(name: String) {
        self.name = name
    }
}
