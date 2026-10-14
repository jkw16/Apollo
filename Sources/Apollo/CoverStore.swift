import Foundation
import ApolloCore

/// Serial disk and image work, isolated from SwiftUI's main actor.
actor CoverStore {
    let directory: URL
    private var pending: [String: Date] = [:]
    init(directory: URL) { self.directory = directory }
    func storeImage(_ data: Data) -> String? {
        guard data.count <= 20_000_000,
              let bytes = ApolloModel.downsample(data, maxPixel: 300) else { return nil }
        guard let file = ApolloModel.store(bytes, in: directory) else { return nil }
        pending[file] = Date()
        return file
    }
    func save(_ manifest: CoverManifest) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: directory.appendingPathComponent("covers.json"), options: .atomic)
        let keep = Set(manifest.covers.map(\.file))
        pending = pending.filter { !keep.contains($0.key) && Date().timeIntervalSince($0.value) < 600 }
        let folder = directory.appendingPathComponent("covers")
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            let name = file.lastPathComponent
            let stem = file.deletingPathExtension().lastPathComponent
            // Only remove generated cache files, never imported originals.
            if file.pathExtension == "jpg", stem.count == 16, stem.allSatisfy(\.isHexDigit), !keep.contains(name), pending[name] == nil {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
