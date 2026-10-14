import XCTest
@testable import ApolloCore

final class WordStreamTests: XCTestCase {
    private let lyrics = LRC.parse("[00:01]Soaring ever higher\n[00:04]I flew\n[00:09]\n[00:10]The end")

    func testWordsCarryLengthWeightedSpans() {
        let words = WordStream.words(in: lyrics)
        XCTAssertEqual(words.map(\.text), ["Soaring", "ever", "higher", "I", "flew", "The", "end"])
        // "Soaring" (7 chars) over "Soaring ever higher" (17 total) spans 3 s x 7/17 ≈ 1.24
        XCTAssertEqual(words[0].start, 1)
        XCTAssertEqual(words[0].end, 1 + 3 * 7 / 17, accuracy: 1e-9)
        XCTAssertEqual(words[2].end, 4, accuracy: 1e-9) // line ends exactly where next begins
        XCTAssertEqual(words[5].start, 10)
    }

    func testBlankLinesProduceNoWordsButAdvanceClock() {
        let words = WordStream.words(in: lyrics)
        XCTAssertEqual(words.map(\.lineID), [0, 0, 0, 1, 1, 3, 3])
        XCTAssertNil(WordStream.activeIndex(in: words, at: 9.5), "instrumental gap is idle")
    }

    func testActiveIndexTracksAndGoesIdleAfterLastWord() {
        let words = WordStream.words(in: lyrics)
        XCTAssertEqual(WordStream.activeIndex(in: words, at: 10.4), 5)
        XCTAssertEqual(WordStream.activeIndex(in: words, at: 2.5), 1) // "ever" mid-word
        XCTAssertNil(WordStream.activeIndex(in: words, at: 0.5), "before the first word")
        XCTAssertNil(WordStream.activeIndex(in: words, at: 1000), "past the final word end")
        // Continuity: each word's start equals the previous word's end.
        for (prev, next) in zip(words, words.dropFirst()) where prev.lineID == next.lineID {
            XCTAssertEqual(prev.end, next.start, accuracy: 1e-9)
        }
    }

    func testEmptyLyricsAreSafe() {
        XCTAssertTrue(WordStream.words(in: []).isEmpty)
        XCTAssertNil(WordStream.activeIndex(in: [], at: 0))
    }
}

final class WordSymbolTests: XCTestCase {
    func testContainmentMatchesWords() {
        XCTAssertEqual(WordSymbol.resolve(word: "flew"), "airplane")
        XCTAssertEqual(WordSymbol.resolve(word: "blinded,"), "eye.slash")
        XCTAssertEqual(WordSymbol.resolve(word: "SHIP"), "ferry.fill")
        XCTAssertEqual(WordSymbol.resolve(word: "know"), "brain.filled")
        XCTAssertEqual(WordSymbol.resolve(word: "sunny"), "sun.max.fill")
    }

    func testLongestCueWins() {
        // "eyes" beats "eye"; "airplane" beats "air".
        XCTAssertNotEqual(WordSymbol.resolve(word: "flight"), "music.note")
        XCTAssertEqual(WordSymbol.resolve(word: "eyes"), "eye.fill")
    }

    func testUnmatchedAndBlankWordsResolveNil() {
        XCTAssertNil(WordSymbol.resolve(word: "qwerty"))
        XCTAssertNil(WordSymbol.resolve(word: "!!!"))
        XCTAssertNil(WordSymbol.resolve(word: ""))
    }
}