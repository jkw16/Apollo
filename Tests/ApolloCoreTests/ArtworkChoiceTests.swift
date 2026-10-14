import XCTest
@testable import ApolloCore

final class ArtworkChoiceTests: XCTestCase {
    func testExactArtistAndTitleWin() {
        // Equal title agreement: the exact-length match beats the deluxe
        // variant through the length penalty (mirrors the collector's choice).
        let results = [
            ItunesAlbum(artistName: "Tycho", collectionName: "Awake - Single", artworkUrl100: "a"),
            ItunesAlbum(artistName: "Tycho", collectionName: "Awake (Deluxe Edition)", artworkUrl100: "b")
        ]
        XCTAssertEqual(ArtworkChoice.chooseArtwork(results: results, artist: "Tycho", title: "Awake")?.artworkUrl100, "a")
    }

    func testTitleOnlyMatchesAreRejected() {
        // Regression: exact title, wrong artist — wrong cover on the wall.
        let results = [ItunesAlbum(artistName: "Hannah Stater", collectionName: "A Moment Apart - Single", artworkUrl100: "a")]
        XCTAssertNil(ArtworkChoice.chooseArtwork(results: results, artist: "ODESZA", title: "A Moment Apart"))
    }

    func testArtistOnlyMatchesAreRejected() {
        // Regression: exact artist, no title agreement resolves a DJ mix or
        // mixtape to an unrelated single's artwork.
        let results = [ItunesAlbum(artistName: "Lane 8", collectionName: "Grapevine (feat. Elderbrook)", artworkUrl100: "a")]
        XCTAssertNil(ArtworkChoice.chooseArtwork(results: results, artist: "Lane 8", title: "Lane 8 Summer 2020 Mixtape (DJ Mix)"))
    }

    func testNormalizationStripsParensDiacriticsAndPunctuation() {
        XCTAssertEqual(wallNormalized("Ben Böhmer"), wallNormalized("ben bohmer"))
        XCTAssertEqual(wallNormalized("Some Minds (feat. Andrew Wyatt) - Single"), wallNormalized("some minds single"))
        XCTAssertEqual(wallNormalized("Dangerous: The Double Album (Bonus)"), wallNormalized("dangerous the double album"))
        XCTAssertEqual(wallNormalized("ERNEST — FLOWER SHOPS"), wallNormalized("ernest flower shops"))
    }

    func testSizeSuffixSwap() {
        XCTAssertEqual(ArtworkChoice.scaled("https://mzstatic/image/thumb/100x100bb.jpg", size: 300),
                       "https://mzstatic/image/thumb/300x300bb.jpg")
        XCTAssertNil(ArtworkChoice.scaled("https://mzstatic/no-suffix", size: 300))
    }
}