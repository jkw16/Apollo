import XCTest
@testable import ApolloCore

final class PlaylistWallTests: XCTestCase {
    func testPlaylistMembershipRemovesOldCoversAndHandlesDuplicates() {
        let cached = [CoverRecord(artist: "Artist", title: "Old", file: "old.jpg"),
                      CoverRecord(artist: "ARTIST", title: "New", file: "new.jpg"),
                      CoverRecord(artist: "ARTIST", title: "New", file: "new.jpg")]
        let keys = Set([WallAlbum.key(artist: "artist", title: "New")])
        XCTAssertEqual(WallBudget.select(cached, keys: keys).map(\.file), ["new.jpg"])
        XCTAssertTrue(WallBudget.select(cached, keys: []).isEmpty)
    }
    func testAlbumAndDisplayBudgetsAreBounded() {
        let albums = (0..<1000).map { WallAlbum(artist: "Artist", title: "Album \($0)") }
        XCTAssertEqual(WallBudget.unique(albums + albums).count, 120)
        let covers = albums.map { CoverRecord(artist: $0.artist, title: $0.title, file: $0.title) }
        XCTAssertEqual(WallBudget.select(covers, keys: Set(albums.map(\.key))).count, 120)
    }
    func testDuplicateAlbumsUseFirstArtworkAndSkipBlankTitles() {
        let entries = [WallAlbum(artist: "A", title: ""), WallAlbum(artist: "Beyoncé", title: "Album"),
                       WallAlbum(artist: "BEYONCE", title: "album")]
        XCTAssertEqual(WallBudget.unique(entries).count, 1)
    }
}

final class SpotifyPlaylistTests: XCTestCase {
    private func client() -> SpotifyPlaylistClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlaylistStub.self]
        return SpotifyPlaylistClient(session: URLSession(configuration: config))
    }
    private func playback(_ uri: String = "spotify:track:local", playlist: String = "one") -> String {
        "{\"context\":{\"type\":\"playlist\",\"uri\":\"spotify:playlist:\(playlist)\"},\"item\":{\"uri\":\"\(uri)\"}}"
    }
    private func page(_ title: String, next: Bool = false) -> String {
        "{\"items\":[{\"item\":{\"album\":{\"name\":\"\(title)\",\"artists\":[{\"name\":\"Test\"}],\"images\":[{\"url\":\"https://i.scdn.co/image/test\",\"width\":300}]}}}],\"next\":\(next ? "\"https://api.spotify.com/next\"" : "null")}"
    }
    func testPaginationRevisionCacheAndPlaylistEdits() async throws {
        var revision = "v1"
        var pages = 0
        PlaylistStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test")
            let path = request.url!.path
            if path.contains("currently-playing") { return (200, [:], self.playback()) }
            if path.hasSuffix("/items") {
                pages += 1
                let second = request.url!.query!.contains("offset=1")
                return (200, [:], self.page(second ? "Second" : revision, next: !second))
            }
            return (200, [:], "{\"name\":\"Test playlist\",\"snapshot_id\":\"\(revision)\"}")
        }
        let client = client()
        let first = try await client.playlist(token: "test", localTrackURI: "spotify:track:local")
        XCTAssertEqual(first?.albums.map(\.title), ["v1", "Second"])
        _ = try await client.playlist(token: "test", localTrackURI: "spotify:track:local")
        XCTAssertEqual(pages, 2, "Unchanged playlists reuse metadata without paging again")
        revision = "v2"
        let edited = try await client.playlist(token: "test", localTrackURI: "spotify:track:local")
        XCTAssertEqual(edited?.albums.map(\.title), ["v2", "Second"])
        XCTAssertEqual(pages, 4)
    }
    func testRemotePlaybackDoesNotReplaceLocalWall() async throws {
        PlaylistStub.handler = { _ in (200, [:], self.playback("spotify:track:remote")) }
        do { _ = try await client().playlist(token: "test", localTrackURI: "spotify:track:local"); XCTFail() }
        catch SpotifyWallError.changed { }
    }
    func testRateLimitHonorsRetryAfterWithoutAnotherRequest() async throws {
        var calls = 0
        PlaylistStub.handler = { _ in calls += 1; return (429, ["Retry-After": "120"], "") }
        let client = client()
        for _ in 0..<2 {
            do { _ = try await client.playlist(token: "test", localTrackURI: "spotify:track:local"); XCTFail() }
            catch SpotifyWallError.rateLimited { }
        }
        XCTAssertEqual(calls, 1)
    }
    func testRestrictedPlaylistIsReportedAndDoesNotReadItems() async throws {
        PlaylistStub.handler = { request in
            if request.url!.path.contains("currently-playing") { return (200, [:], self.playback()) }
            XCTAssertFalse(request.url!.path.hasSuffix("/items"))
            return (403, [:], "")
        }
        do { _ = try await client().playlist(token: "test", localTrackURI: "spotify:track:local"); XCTFail() }
        catch SpotifyWallError.restricted { }
    }
    func testCancellationDoesNotBeginRequests() async throws {
        PlaylistStub.handler = { _ in XCTFail("Cancelled sync must not call the API"); return (500, [:], "") }
        let client = client()
        let task = Task {
            try await Task.sleep(for: .seconds(1))
            return try await client.playlist(token: "test", localTrackURI: "spotify:track:local")
        }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch is CancellationError { }
    }
    func testNoPlaybackReturnsNoPlaylist() async throws {
        PlaylistStub.handler = { _ in (204, [:], "") }
        let result = try await client().playlist(token: "test", localTrackURI: "spotify:track:local")
        XCTAssertNil(result)
    }
}

private final class PlaylistStub: URLProtocol {
    static var handler: ((URLRequest) -> (Int, [String: String], String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, headers, body) = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
