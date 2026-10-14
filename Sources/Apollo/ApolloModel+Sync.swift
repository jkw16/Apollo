import AppKit
import ApolloCore

extension ApolloModel {
    /// One sync at a time, only while the wall can be seen. The regular
    /// playback poll checks this gate; it never waits for artwork downloads.
    func requestCoverSync(force: Bool = false) {
        guard source != .demo, connected, ambientScene == .wallOfSound,
              moviePlayer == nil, videoID == nil, NSApp.isActive,
              NSApp.windows.contains(where: { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) }),
              force || autoSyncCovers, !syncInFlight,
              Date() >= nextCoverSync else { return }
        nextCoverSync = Date().addingTimeInterval(WallBudget.interval)
        let selected = source, generation = coverGeneration, expectedTrack = trackID
        syncInFlight = true
        coverSyncTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if coverGeneration == generation { syncInFlight = false; coverSyncTask = nil }
            }
            do {
                let snapshot: WallSnapshot?
                if selected == .apple { snapshot = try await applePlaylist() }
                else {
                    let token = try await spotifyConnection.accessToken()
                    snapshot = try await spotifyPlaylists.playlist(token: token,
                        localTrackURI: String(expectedTrack.dropFirst("Spotify:".count)))
                }
                try Task.checkCancellation()
                guard generation == coverGeneration, source == selected, trackID == expectedTrack else { return }
                guard let snapshot else {
                    usePlayingAlbum(message: "No readable playlist context · showing the playing album.")
                    return
                }
                activeCoverKeys = Set(snapshot.albums.map(\.key))
                coverStatus = "\(snapshot.name) · updating covers…"
                let now = Date()
                let missing = snapshot.albums.filter { album in
                    !self.coverCatalog.covers.contains { WallAlbum.key(artist: $0.artist, title: $0.title) == album.key }
                        && (self.coverFailures[album.key] ?? .distantPast) <= now
                }
                var records: [CoverRecord] = []
                for album in missing.prefix(WallBudget.downloadsPerPass) {
                    try Task.checkCancellation()
                    let data: Data?
                    if selected == .apple, let id = album.trackID {
                        data = try? await coverBridge.playlistArtwork(playlistID: snapshot.id, trackID: id)
                    } else if let url = album.artworkURL {
                        data = await Self.fetchCover(url)
                    } else { data = nil }
                    try Task.checkCancellation()
                    if let data, let file = await coverStore.storeImage(data) {
                        records.append(CoverRecord(artist: album.artist, title: album.title, file: file))
                    } else { coverFailures[album.key] = Date().addingTimeInterval(300) }
                    try await Task.sleep(for: .milliseconds(120))
                }
                try Task.checkCancellation()
                guard generation == coverGeneration, source == selected, trackID == expectedTrack else { return }
                mergeCovers(records)
                let count = wallCovers.count
                let remaining = snapshot.albums.count - count
                coverStatus = "\(snapshot.name) · \(count) covers" + (remaining > 0 ? " · more artwork pending or unavailable" : "")
                    + (snapshot.limited ? " · preview limited to 120 albums / 1,000 tracks" : "")
            } catch is CancellationError { }
            catch {
                guard generation == coverGeneration else { return }
                if case SpotifyWallError.rateLimited(let until) = error { nextCoverSync = max(nextCoverSync, until) }
                if case SpotifyWallError.signIn = error { spotifyConnection.disconnect() }
                usePlayingAlbum(message: error.localizedDescription)
            }
        }
    }

    func syncCovers() {
        nextCoverSync = .distantPast
        requestCoverSync(force: true)
    }

    func resetCoverSync() {
        coverGeneration = UUID()
        coverSyncTask?.cancel(); coverSyncTask = nil; syncInFlight = false
        nextCoverSync = .distantPast
        activeCoverKeys = []
        coverFailures = coverFailures.filter { $0.value > Date() }
    }

    func usePlayingAlbum(message: String? = nil) {
        activeCoverKeys = album.isEmpty ? [] : [WallAlbum.key(artist: artist, title: album)]
        if let message { coverStatus = message }
    }

    private func applePlaylist() async throws -> WallSnapshot {
        let header = try await coverBridge.playlistHeader()
        var albums: [WallAlbum] = []
        let count = min(WallBudget.tracks, header.count)
        if count > 0 {
            for start in stride(from: 1, through: count, by: 100) {
                try Task.checkCancellation()
                albums += try await coverBridge.playlistPage(id: header.id, start: start, end: min(count, start + 99))
                if WallBudget.unique(albums).count >= WallBudget.albums { break }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        let final = try await coverBridge.playlistHeader()
        guard final.id == header.id, final.count == header.count else { throw SpotifyWallError.changed }
        return WallSnapshot(id: header.id, name: header.name, albums: WallBudget.unique(albums),
                            limited: header.count > count || Set(albums.map(\.key)).count >= WallBudget.albums)
    }
}
