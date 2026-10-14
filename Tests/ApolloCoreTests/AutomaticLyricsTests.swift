import XCTest
@testable import ApolloCore

final class AutomaticLyricsTests: XCTestCase {
    private let query = LyricQuery(title: "Stars & Sky", artist: "Apollo", album: "Demo", duration: 60)
    private let fixture = Data(#"{"id":1,"trackName":"Stars & Sky","artistName":"Apollo","albumName":"Demo","duration":60,"instrumental":false,"plainLyrics":"An original test line","syncedLyrics":"[00:03]An original test line"}"#.utf8)

    func testRequestEscapesMetadataAndIdentifiesClient() {
        let request = query.request()
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.host, "lrclib.net")
        XCTAssertEqual(components.queryItems?.first?.value, "Stars & Sky")
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")!.contains("Apollo"))
    }

    func testMatchingRejectsWrongVersionAndArtist() throws {
        let record = try JSONDecoder().decode(AutomaticLyrics.self, from: fixture)
        XCTAssertTrue(record.matches(query))
        XCTAssertFalse(record.matches(LyricQuery(title: query.title, artist: "Someone else", album: "Demo", duration: 60)))
        XCTAssertFalse(record.matches(LyricQuery(title: query.title, artist: query.artist, album: "Live", duration: 90)))
        XCTAssertFalse(record.matches(LyricQuery(title: "Stars & Sky (Live)", artist: query.artist, album: "Live", duration: 60)))
        XCTAssertEqual(LRC.activeIndex(in: LRC.parse(record.syncedLyrics!), at: 12), 0)
    }

    func testLookupFallsBackAfterMissingAlbumMatch() async throws {
        let fixture = fixture
        LyricStub.handler = { request in
            request.url!.path == "/api/get" ? (404, [:], Data()) : (200, [:], Data("[".utf8) + fixture + Data("]".utf8))
        }
        let client = makeClient()
        let record = try await client.lookup(query)
        XCTAssertEqual(record?.id, 1)
    }

    func testRateLimitStopsSubsequentRequests() async throws {
        LyricStub.handler = { _ in (429, ["Retry-After": "120"], Data()) }
        let client = makeClient()
        do { _ = try await client.lookup(query); XCTFail("Expected backoff") } catch { XCTAssertTrue(error is LyricLookupError) }
        LyricStub.handler = { _ in XCTFail("Must honor Retry-After"); return (500, [:], Data()) }
        do { _ = try await client.lookup(query); XCTFail("Expected backoff") } catch { XCTAssertTrue(error is LyricLookupError) }
    }

    func testTimeoutRetriesOnceAndRecovers() async throws {
        var attempts = 0
        let fixture = fixture
        LyricStub.handler = { request in
            XCTAssertEqual(request.timeoutInterval, 30)
            attempts += 1
            if attempts == 1 { throw URLError(.timedOut) }
            return (200, [:], fixture)
        }
        let record = try await makeClient().lookup(query)
        XCTAssertEqual(record?.id, 1)
        XCTAssertEqual(attempts, 2)
    }

    func testRepeatedTimeoutStopsAfterTwoAttempts() async throws {
        var attempts = 0
        LyricStub.handler = { _ in attempts += 1; throw URLError(.timedOut) }
        do { _ = try await makeClient().lookup(query); XCTFail("Expected timeout") }
        catch LyricLookupError.timedOut { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(attempts, 2)
    }

    func testOfflineDoesNotRetry() async throws {
        var attempts = 0
        LyricStub.handler = { _ in attempts += 1; throw URLError(.notConnectedToInternet) }
        do { _ = try await makeClient().lookup(query); XCTFail("Expected offline") }
        catch LyricLookupError.offline { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(attempts, 1)
    }

    private func makeClient() -> AutomaticLyricClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricStub.self]
        return AutomaticLyricClient(session: URLSession(configuration: configuration))
    }
}

private final class LyricStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
        let (status, headers, data) = try Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
