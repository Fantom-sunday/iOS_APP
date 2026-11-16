import Foundation

enum FileStore {
    static var musicDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let musicDir = documentsDirectory.appendingPathComponent("MusicFiles", isDirectory: true)

        if !FileManager.default.fileExists(atPath: musicDir.path) {
            try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        }

        return musicDir
    }

    static func url(for fileName: String) -> URL? {
        guard !fileName.isEmpty else { return nil }
        let url = musicDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func exists(_ fileName: String) -> Bool {
        url(for: fileName) != nil
    }

    static func remove(fileName: String) {
        guard let url = url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func size(of fileName: String) -> Int64 {
        guard let url = url(for: fileName),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attrs[.size] as? NSNumber else { return 0 }
        return number.int64Value
    }
}
