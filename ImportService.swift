import AVFoundation
import ImageIO
import SwiftData
import UIKit
import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ImportedTrack: Sendable {
    let id: UUID
    let fileName: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let artwork: Data?
}

@MainActor
class ImportService: ObservableObject {
    @Published var isImporting = false
    @Published var importProgress: String = ""

    func importTracks(from content: String, modelContext: ModelContext) {
        let lines = content.components(separatedBy: .newlines)
        var importedCount = 0

        importProgress = "Обработка треков..."

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let components = trimmedLine.components(separatedBy: " - ")
            let artist: String
            let title: String

            if components.count >= 2 {
                artist = components[0].trimmingCharacters(in: .whitespaces)
                title = components[1...].joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            } else {
                artist = "Неизвестный исполнитель"
                title = trimmedLine
            }

            let track = Track(
                title: title,
                artist: artist,
                album: "Яндекс.Музыка (Импорт)",
                duration: 0.0,
                    fileName: "imported_\(UUID().uuidString).mp3"
            )
            modelContext.insert(track)
            importedCount += 1
        }

        do {
            try modelContext.save()
            importProgress = "Импортировано треков: \(importedCount)"
        } catch {
            importProgress = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }

    static func importFiles(_ urls: [URL], into context: ModelContext) async {
        for url in urls {
            let imported = await Task.detached(priority: .userInitiated) {
                await prepare(url)
            }.value
            guard let t = imported else { continue }
            context.insert(Track(id: t.id, title: t.title, artist: t.artist, album: t.album,
                                 duration: t.duration, fileName: t.fileName, artworkData: t.artwork))
        }
        try? context.save()
    }

    nonisolated static func prepare(_ url: URL) async -> ImportedTrack? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        let fileName = "\(id.uuidString).\(url.pathExtension)"
        let dest = FileStore.musicDirectory.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            print("Не удалось скопировать \(url.lastPathComponent): \(error)")
            return nil
        }

        let asset = AVURLAsset(url: dest)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        let items = (try? await asset.load(.commonMetadata)) ?? []

        func string(_ id: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first else { return nil }
            let value = try? await item.load(.stringValue)
            return value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var artwork: Data?
        if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).first,
           let raw = try? await item.load(.dataValue) {
            artwork = downscale(raw)
        }

        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let title = await string(.commonIdentifierTitle)
        let artist = await string(.commonIdentifierArtist)
        let album = await string(.commonIdentifierAlbumName)

        return ImportedTrack(
            id: id,
            fileName: fileName,
            title: (title?.isEmpty == false ? title : nil) ?? fallbackTitle,
            artist: (artist?.isEmpty == false ? artist : nil) ?? "Неизвестный исполнитель",
            album: (album?.isEmpty == false ? album : nil) ?? "Неизвестный альбом",
            duration: seconds.isFinite ? seconds : 0,
            artwork: artwork
        )
    }

    nonisolated static func downscale(_ data: Data, maxPixel: Int = 600) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.8)
    }
}
