import XCTest
@testable import ApolloCore

final class ApolloCoreTests: XCTestCase {
    func testEmojiUsesCurrentLyricBeforeMetadata() {
        XCTAssertEqual(LyricEmoji.resolve(line: "Dancing under the rain", title: "Love", artist: "Sun"), "🌧️")
        XCTAssertEqual(LyricEmoji.resolve(line: "Nothing specific here", title: "Moonlight"), "🌙")
        XCTAssertEqual(LyricEmoji.resolve(line: "Nothing specific here"), "🎵")
        XCTAssertNil(LyricEmoji.resolve(line: "  \n", title: "Love"))
    }
    func testEmojiPhrasesTakePrecedence() {
        XCTAssertEqual(LyricEmoji.resolve(line: "You broke my heart, love"), "💔")
        XCTAssertEqual(LyricEmoji.resolve(line: "No more tears tonight"), "🌤️")
        XCTAssertEqual(LyricEmoji.resolve(line: "I don’t love you"), "💔")
        XCTAssertEqual(LyricEmoji.resolve(line: "Let you go, my love"), "🕊️")
    }
    func testEmojiWordBoundariesAndAccents() {
        XCTAssertEqual(LyricEmoji.resolve(line: "Start the carpool diet"), "🎵")
        XCTAssertEqual(LyricEmoji.resolve(line: "CORAZÓN ROTO!"), "💔")
        XCTAssertEqual(LyricEmoji.resolve(line: "Música, colores y luz"), "✨")
        XCTAssertEqual(LyricEmoji.resolve(line: "The OCEAN…"), "🌊")
    }
    func testRepeatedTimestampsFractionsAndOffset() {
        let lines = LRC.parse("[ar:Apollo]\n[offset:-250]\n[00:02.50][01:02.125]Hello 🌙\n[00:00.1]Start\n[00:65]Invalid")
        XCTAssertEqual(lines.map(\.time), [0, 2.25, 61.875])
        XCTAssertEqual(lines.map(\.text), ["Start", "Hello 🌙", "Hello 🌙"])
        XCTAssertEqual(Set(lines.map(\.id)).count, 3)
    }
    func testSeekBoundariesAndInterludes() {
        let lines = LRC.parse("[00:03]One\n[00:06]\n[00:09]Three")
        XCTAssertNil(LRC.activeIndex(in: lines, at: 2.99))
        XCTAssertEqual(LRC.activeIndex(in: lines, at: 3), 0)
        XCTAssertEqual(LRC.activeIndex(in: lines, at: 7), 1)
        XCTAssertEqual(LRC.activeIndex(in: lines, at: 100), 2)
        XCTAssertEqual(LRC.activeIndex(in: lines, at: 4), 0)
        XCTAssertNil(LRC.activeIndex(in: [], at: 0))
    }
    func testURLsAndUntrustedHosts() {
        for url in ["dQw4w9WgXcQ", "https://youtu.be/dQw4w9WgXcQ?t=10", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "https://youtube.com/shorts/dQw4w9WgXcQ"] {
            XCTAssertEqual(YouTubeURL.videoID(from: url), "dQw4w9WgXcQ")
        }
        for url in ["https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ", "javascript:alert(1)", "https://youtube.com/watch?v=<script>", "not a video"] {
            XCTAssertNil(YouTubeURL.videoID(from: url))
        }
    }
    func testPlaybackPauseSeekAndDurationClamp() {
        let start = Date(timeIntervalSince1970: 0)
        var clock = PlaybackClock(position: 10, duration: 30, playing: true, sampledAt: start)
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(3)), 13)
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(60)), 30)
        clock.playing = false
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(3)), 10)
        clock.position = 2
        XCTAssertEqual(clock.elapsed(at: start), 2)
    }
}
