// The cover catalog: import from an albums.json of artwork URLs, plus
// passive capture of the current track's artwork while listening. Images
// are content-addressed (sha256 of the downsampled bytes) so both paths
// dedupe for free. The manifest lives next to library.json.
import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import ApolloCore

extension ApolloModel {
    static let coverCap = 600

    // MARK: import

    func importCovers() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, UTType(filenameExtension: "json") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an albums.json with https cover URLs (artist, title, cover300)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importCoversFile(url)
    }

    /// Shared by the picker and the first-activation seed from the user's
    /// collected albums.json.
    func importCoversFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            // Our own manifest (round-trip import) or the collector shape.
            if let manifest = try? JSONDecoder().decode(CoverManifest.self, from: data) {
                adopt(localFiles: manifest.covers)
                return
            }
            let albums = try JSONDecoder().decode([CollectorAlbum].self, from: data)
            let targets = albums.compactMap { album -> (URL, String, String)? in
                guard let raw = album.cover300, let target = URL(string: raw),
                      target.scheme == "https" else { return nil }
                return (target, album.artist ?? "", album.title ?? "")
            }
            guard !targets.isEmpty else {
                error = "No https cover300 URLs found in that file."; return
            }
            download(targets)
        } catch is DecodingError {
            error = "That file isn't an albums.json (artist/title/cover300) or a saved covers manifest."
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// A previously exported manifest can only carry file names that already
    /// exist inside Apollo's covers directory; adopt those, nothing else.
    private func adopt(localFiles: [CoverRecord]) {
        let known = Set(coverCatalog.covers.map(\.file))
        var added = 0
        for record in localFiles where !known.contains(record.file) {
            guard FileManager.default.fileExists(atPath: supportDirectory.appendingPathComponent(record.file).path) else { continue }
            coverCatalog.covers.append(record)
            added += 1
        }
        saveCovers()
        coverStatus = added == 0 ? "No new covers in that manifest." : "Added \(added) covers"
    }

    private func download(_ targets: [(URL, String, String)]) {
        if coverStatus?.hasPrefix("Importing") == true { error = "An import is already running."; return }
        coverStatus = "Importing 0 of \(targets.count) covers…"
        Task {
            let store = self.coverStore
            var known = Set(coverCatalog.covers.map(\.file))
            var added: [CoverRecord] = []
            var done = 0
            await withTaskGroup(of: CoverRecord?.self) { group in
                var pending = ArraySlice(targets.prefix(Self.coverCap))
                var inFlight = 0
                func topUp() {
                    while inFlight < 2, let next = pending.first {
                        pending = pending.dropFirst(); inFlight += 1
                        group.addTask {
                            let (target, artist, title) = next
                            guard let bytes = await ApolloModel.fetchCover(target),
                                  let file = await store.storeImage(bytes) else { return nil }
                            return CoverRecord(artist: artist, title: title, file: file)
                        }
                    }
                }
                topUp()
                for await record in group {
                    inFlight -= 1
                    done += 1
                    topUp()
                    if let record, !known.contains(record.file) {
                        known.insert(record.file)
                        added.append(record)
                    }
                    if done % 5 == 0 || done == targets.count {
                        coverStatus = "Importing \(done) of \(targets.count) covers…"
                    }
                }
            }
            let room = max(0, Self.coverCap - coverCatalog.covers.count)
            let accepted = Array(added.prefix(room))
            if !accepted.isEmpty {
                coverCatalog.covers.append(contentsOf: accepted)
                saveCovers()
            }
            coverStatus = accepted.isEmpty
                ? "No new covers found; imports are deduplicated."
                : "Added \(accepted.count) covers · \(coverCatalog.covers.count) total"
        }
    }

    /// Fetch one artwork URL with the same guards as the Spotify artwork path.
    nonisolated static func fetchCover(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count < 20_000_000 else { return nil }
        return downsample(data, maxPixel: 300)
    }

    // MARK: passive capture

    /// Content-address the current track's artwork into the catalog. Called
    /// after both connection branches assign `artwork`; idempotent (hash
    /// dedupe) so stale or racing calls only skip, and silent on failure so
    /// it never nags during playback.
    func captureCover(_ data: Data, artist: String, album: String) {
        let key = WallAlbum.key(artist: artist, title: album)
        guard !coverCatalog.covers.contains(where: { WallAlbum.key(artist: $0.artist, title: $0.title) == key }) else { return }
        Task {
            guard let file = await coverStore.storeImage(data) else { return }
            mergeCovers([CoverRecord(artist: artist, title: album, file: file)])
        }
    }

    func mergeCovers(_ records: [CoverRecord]) {
        guard !records.isEmpty else { return }
        var updated = coverCatalog.covers
        for record in records {
            updated.removeAll { $0.file == record.file || WallAlbum.key(artist: $0.artist, title: $0.title) == WallAlbum.key(artist: record.artist, title: record.title) }
            updated.append(record)
        }
        // Prefer retaining the current playlist when evicting older cached covers.
        if updated.count > Self.coverCap {
            let inactive = updated.filter { !activeCoverKeys.contains(WallAlbum.key(artist: $0.artist, title: $0.title)) }
            let active = updated.filter { activeCoverKeys.contains(WallAlbum.key(artist: $0.artist, title: $0.title)) }
            updated = Array(inactive.suffix(max(0, Self.coverCap - active.count))) + Array(active.suffix(Self.coverCap))
        }
        coverCatalog.covers = updated
        saveCovers()
    }

    // MARK: persistence

    func loadCovers() {
        let file = supportDirectory.appendingPathComponent("covers.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { coverCatalog = try JSONDecoder().decode(CoverManifest.self, from: Data(contentsOf: file)) }
        catch {
            self.error = "Could not load the cover catalog: \(error.localizedDescription)"
            coverCatalog = CoverManifest()
            return
        }
        // Covers from the first build landed in the support directory root;
        // move any strays into covers/ before dropping unreachable entries.
        var changed = false
        for record in coverCatalog.covers {
            let inCovers = supportDirectory.appendingPathComponent("covers").appendingPathComponent(record.file)
            let strays = supportDirectory.appendingPathComponent(record.file)
            if !FileManager.default.fileExists(atPath: inCovers.path),
               FileManager.default.fileExists(atPath: strays.path) {
                try? FileManager.default.moveItem(at: strays, to: inCovers)
                changed = true
            }
        }
        // Drop manifest entries whose image vanished on disk.
        let intact = coverCatalog.covers.filter {
            FileManager.default.fileExists(atPath: supportDirectory.appendingPathComponent("covers").appendingPathComponent($0.file).path)
        }
        if intact.count != coverCatalog.covers.count || changed {
            coverCatalog.covers = intact
            saveCovers()
        }
    }

    func saveCovers() {
        let manifest = coverCatalog
        Task { await coverStore.save(manifest) }
    }

    // MARK: image processing

    /// Downsample through ImageIO so 640px+ artwork never bloats the tile
    /// cache; re-encode as JPEG 0.85 for small, dedup-stable files.
    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumb,
                                   [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Content-addressed filename: first 16 hex chars of the downsampled bytes' sha256.
    nonisolated static func store(_ bytes: Data, in directory: URL) -> String? {
        let name = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined().prefix(16)
        let file = String(name) + ".jpg"
        do {
            // Covers always live in the covers/ subdirectory of the support
            // directory; loadCovers() rescues anything left at the old path.
            try bytes.write(to: directory.appendingPathComponent("covers").appendingPathComponent(file), options: .atomic)
            return file
        } catch { return nil }
    }
}