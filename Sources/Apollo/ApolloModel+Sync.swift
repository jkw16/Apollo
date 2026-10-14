// Album-cover auto-sync: keeps the wall's catalog aligned with the Music
// library. Each run enumerates the library's albums (read-only Apple
// Events), diffs them against the catalog, and resolves the missing ones
// through iTunes — lookup-by-artist first (its full album list includes
// titles the term-search endpoint hides), term search as the fallback.
// Throttled to the ~20 requests/min informal cap, cached per artist/album.
// Passive capture still adds whatever is played in between.
import Foundation
import ApolloCore

extension ApolloModel {
    static let searchThrottle: TimeInterval = 3.5
    var searchCacheURL: URL { supportDirectory.appendingPathComponent("cover-search-cache.json") }

    func syncCovers() {
        if syncInFlight { return }
        syncInFlight = true
        Task { [weak self] in
            defer { self?.syncInFlight = false }
            guard let model = self else { return }
            let albums: [(artist: String, album: String)]
            do { albums = try await model.bridge.libraryAlbums() }
            catch {
                model.coverStatus = "Sync needs the Music app: \(error.localizedDescription)"
                return
            }
            await model.runSync(albums: albums)
        }
    }

    private func runSync(albums: [(artist: String, album: String)]) async {
        var cache = Self.loadCache(from: searchCacheURL)
        var calls = 0
        var added = 0

        // Group unresolved albums by normalized artist: one lookup per
        // artist covers all of their releases, including titles that the
        // term-search endpoint never surfaces.
        var wanted: [String: (display: String, entries: [(album: String, albumKey: String)])] = [:]
        for entry in albums {
            guard coverCatalog.covers.count < Self.coverCap else { break }
            guard !catalogContains(artist: entry.artist, album: entry.album) else { continue }
            let artistKey = wallNormalized(entry.artist)
            let albumKey = "\(artistKey) ~ \(wallNormalized(entry.album))"
            var group = wanted[artistKey] ?? (entry.artist, [])
            group.entries.append((entry.album, albumKey))
            wanted[artistKey] = group
        }

        for (artistKey, group) in wanted {
            guard coverCatalog.covers.count < Self.coverCap else { break }
            if let cachedArtist = cache.artists[artistKey], cachedArtist.isEmpty {
                continue // known: nothing on the storefront for this artist
            }
            if cache.artists[artistKey] == nil {
                cache.artists[artistKey] = await artistID(for: group.display, calls: &calls)
            }
        }
        saveCache(cache, to: searchCacheURL)

        // Batched release lists: one lookup resolves up to 25 artists'
        // full album lists in a single call, each row tagged with its own
        // artistId, so remaining wall-time is the artist-discovery pace only.
        var releaseLists: [String: [ItunesAlbum]] = [:] // in memory for this run
        let known = cache.artists.filter { !$0.value.isEmpty }.map(\.value)
        var toResolve = Array(Set(known).subtracting([]))
        while !toResolve.isEmpty {
            let chunk = Array(toResolve.prefix(25))
            toResolve.removeFirst(min(25, toResolve.count))
            let list = await batchedReleases(ids: chunk, calls: &calls)
            for album in list {
                guard let id = album.artistId else { continue }
                releaseLists[String(id), default: []].append(album)
            }
        }

        for (artistKey, group) in wanted {
            guard coverCatalog.covers.count < Self.coverCap else { break }
            guard let artistID = cache.artists[artistKey], !artistID.isEmpty else { continue }
            let releases = releaseLists[artistID] ?? []
            for entry in group.entries {
                var winner = ArtworkChoice.chooseArtwork(results: releases, artist: group.display, title: entry.album)
                if winner == nil {
                    // Fallback: term search by artist + album title.
                    let results = await termSearch(group.display, entry.album, calls: &calls)
                    winner = ArtworkChoice.chooseArtwork(results: results, artist: group.display, title: entry.album)
                }
                guard let artwork = winner?.artworkUrl100 else {
                    cache.albums[entry.albumKey] = "" // negative cache: no storefront match
                    continue
                }
                cache.albums[entry.albumKey] = artwork
                guard let big = ArtworkChoice.scaled(artwork, size: 300),
                      let url = URL(string: big),
                      let bytes = await ApolloModel.fetchCover(url),
                      let file = ApolloModel.store(bytes, in: supportDirectory), !file.isEmpty,
                      !coverCatalog.covers.contains(where: { $0.file == file }),
                      coverCatalog.covers.count < Self.coverCap else { continue }
                coverCatalog.covers.append(CoverRecord(artist: group.display, title: entry.album, file: file))
                added += 1
                saveCovers()
            }
        }
        saveCache(cache, to: searchCacheURL)
        coverStatus = added == 0
            ? "Wall matches your library · \(coverCatalog.covers.count) covers"
            : "Synced \(added) covers · \(coverCatalog.covers.count) total"
        if added > 0 { UserDefaults.standard.set(true, forKey: "wallSeeded") }
    }

    private func catalogContains(artist: String, album: String) -> Bool {
        coverCatalog.covers.contains {
            wallNormalized($0.artist) == wallNormalized(artist)
                && wallNormalized($0.title) == wallNormalized(album)
        }
    }

    private func artistID(for display: String, calls: inout Int) async -> String {
        let pairs = ["term": percent(display), "entity": "musicArtist", "limit": "3"]
        try? await Task.sleep(for: .seconds(Self.searchThrottle))
        calls += 1
        coverStatus = "Syncing · \(calls) catalog call\(calls == 1 ? "" : "s") (finding artists)…"
        guard let url = URL(string: "https://itunes.apple.com/search?" + query(pairs)),
              let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ItunesArtists.self, from: data) else { return "" }
        let want = wallNormalized(display)
        let match = decoded.results.first {
            let have = wallNormalized($0.artistName)
            return have == want || have.contains(want) || want.contains(have)
        }
        return match?.artistId.map { String($0) } ?? ""
    }

    /// Full-release lookups for up to 25 artist IDs in one call.
    private func batchedReleases(ids: [String], calls: inout Int) async -> [ItunesAlbum] {
        let idList = ids.joined(separator: ",")
        guard !idList.isEmpty,
              let url = URL(string: "https://itunes.apple.com/lookup?id=\(idList)&entity=album&limit=500") else { return [] }
        calls += 1
        try? await Task.sleep(for: .seconds(Self.searchThrottle))
        coverStatus = "Syncing · \(calls) catalog call\(calls == 1 ? "" : "s") (batched album lists)…"
        guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ItunesResults.self, from: data) else { return [] }
        return decoded.results.filter { $0.artworkUrl100 != nil && $0.artistId != nil }
    }

    private func termSearch(_ artist: String, _ album: String, calls: inout Int) async -> [ItunesAlbum] {
        let pairs = ["term": percent("\(artist) \(album)"), "entity": "album", "limit": "5"]
        try? await Task.sleep(for: .seconds(Self.searchThrottle))
        calls += 1
        coverStatus = "Syncing · \(calls) catalog call\(calls == 1 ? "" : "s") (title search)…"
        guard let url = URL(string: "https://itunes.apple.com/search?" + query(pairs)),
              let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ItunesResults.self, from: data) else { return [] }
        return decoded.results.filter { $0.artworkUrl100 != nil }
    }

    private func percent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
    private func query(_ pairs: [String: String]) -> String {
        pairs.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    }
    private static func loadCache(from url: URL) -> CoverSearchCache {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CoverSearchCache.self, from: data) else { return CoverSearchCache() }
        return decoded
    }
    private func saveCache(_ cache: CoverSearchCache, to url: URL) {
        do { try JSONEncoder().encode(cache).write(to: url, options: .atomic) } catch { }
    }
}

// iTunes lookup/search envelopes: only what matching needs.
struct ItunesResults: Codable {
    var results: [ItunesAlbum] = []
}

struct ItunesArtists: Codable {
    var results: [ItunesArtist] = []
}

struct ItunesArtist: Codable {
    var artistId: Int?
    var artistName: String
}

struct CoverSearchCache: Codable {
    var version = 1
    var artists: [String: String] = [:] // normalized artist -> artist id ("" = not on storefront)
    var albums: [String: String] = [:]  // "artist ~ album" -> artworkUrl100 ("" = no match)
}