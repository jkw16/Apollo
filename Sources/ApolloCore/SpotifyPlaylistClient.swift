import Foundation

public enum SpotifyWallError: LocalizedError {
    case signIn, unavailable, restricted, changed, rateLimited(Date)
    public var errorDescription: String? {
        switch self {
        case .signIn: return "Connect Spotify in wall settings to read your playlists."
        case .unavailable: return "Spotify playlist lookup failed. It will retry later."
        case .restricted: return "Spotify only shares playlists you own or collaborate on. Showing the playing album instead."
        case .changed: return "Waiting for Spotify playback on this Mac to match the connected account."
        case .rateLimited: return "Spotify requested a pause. Sync will resume after its retry delay."
        }
    }
}

/// Read-only Web API access. Cache by playlist revision, paginate with a hard
/// work limit, and honor 429 across calls. The caller supplies a short-lived token.
public actor SpotifyPlaylistClient {
    private let session: URLSession
    private var retryAfter = Date.distantPast
    private var cached: (id: String, revision: String, snapshot: WallSnapshot)?
    public init(session: URLSession = .shared) { self.session = session }
    public func reset() { cached = nil }

    public func playlist(token: String, localTrackURI: String) async throws -> WallSnapshot? {
        guard let data = try await get("me/player/currently-playing", token: token) else { return nil }
        let playback = try JSONDecoder().decode(Playback.self, from: data)
        guard playback.item?.uri == localTrackURI else { throw SpotifyWallError.changed }
        guard let context = playback.context, context.type == "playlist",
              let id = context.uri.split(separator: ":").last.map(String.init),
              !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        guard let metaData = try await get("playlists/\(id)?fields=name,snapshot_id", token: token) else { return nil }
        let meta = try JSONDecoder().decode(Metadata.self, from: metaData)
        if let cached, cached.id == id, cached.revision == meta.snapshot_id { return cached.snapshot }
        var albums: [WallAlbum] = []
        var offset = 0
        var more = true
        while more && offset < WallBudget.tracks && WallBudget.unique(albums).count < WallBudget.albums {
            try Task.checkCancellation()
            guard let bytes = try await get("playlists/\(id)/items?limit=50&offset=\(offset)", token: token) else { break }
            let page = try JSONDecoder().decode(Page.self, from: bytes)
            for entry in page.items {
                guard let album = (entry.item ?? entry.track)?.album else { continue }
                let image = album.images.filter { $0.url.scheme == "https" }
                    .sorted { abs(($0.width ?? 300) - 300) < abs(($1.width ?? 300) - 300) }.first
                albums.append(WallAlbum(artist: album.artists.first?.name ?? "", title: album.name, artworkURL: image?.url))
            }
            offset += page.items.count
            more = page.next != nil && !page.items.isEmpty
            if more { try await Task.sleep(for: .milliseconds(150)) }
        }
        // Do not publish a mixture of playlist revisions if it changed while paging.
        guard let endData = try await get("playlists/\(id)?fields=name,snapshot_id", token: token),
              try JSONDecoder().decode(Metadata.self, from: endData).snapshot_id == meta.snapshot_id else {
            throw SpotifyWallError.changed
        }
        let result = WallSnapshot(id: "spotify:\(id)", name: meta.name,
                                  albums: WallBudget.unique(albums), limited: more)
        cached = (id, meta.snapshot_id, result)
        return result
    }

    private func get(_ path: String, token: String) async throws -> Data? {
        try Task.checkCancellation()
        guard Date() >= retryAfter else { throw SpotifyWallError.rateLimited(retryAfter) }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/" + path)!)
        request.timeoutInterval = 12
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, data.count < 8_000_000 else { throw SpotifyWallError.unavailable }
        switch http.statusCode {
        case 200: return data
        case 204: return nil
        case 401: cached = nil; throw SpotifyWallError.signIn
        case 403: throw SpotifyWallError.restricted
        case 429:
            retryAfter = Date().addingTimeInterval(max(1, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60))
            throw SpotifyWallError.rateLimited(retryAfter)
        default: throw SpotifyWallError.unavailable
        }
    }

    private struct Playback: Decodable { let context: Context?; let item: Track? }
    private struct Context: Decodable { let type: String; let uri: String }
    private struct Metadata: Decodable { let name: String; let snapshot_id: String }
    private struct Page: Decodable { let items: [Entry]; let next: String? }
    private struct Entry: Decodable { let item: Track?; let track: Track? }
    private struct Track: Decodable { let uri: String?; let album: Album? }
    private struct Album: Decodable { let name: String; let artists: [Artist]; let images: [Artwork] }
    private struct Artist: Decodable { let name: String }
    private struct Artwork: Decodable { let url: URL; let width: Int? }
}
