import XCTest
@testable import ApolloCore

final class WordFlowMotionTests: XCTestCase {
    func testWordKeepsItsGeometryAcrossRoleChanges() {
        for age in 1...2 {
            let before = WordFlowMotion.pose(age: age, progress: 1, singing: true)
            let after = WordFlowMotion.pose(age: age + 1, progress: 0, singing: true)
            XCTAssertEqual(before, after)
        }
    }
    func testSettledStageHasOnlyThreeVisibleWords() {
        let poses = (0...4).map { WordFlowMotion.pose(age: $0, progress: 1, singing: true) }
        XCTAssertEqual(poses.filter { $0.opacity > 0 }.count, 3)
        XCTAssertEqual(poses[0].y, 0)
        XCTAssertGreaterThan(poses[0].scale, poses[1].scale)
        XCTAssertGreaterThan(poses[0].scale, poses[2].scale)
    }
    func testShortWordsFinishTheirTransitionBeforeNextWord() {
        let word = TimedWord(id: 0, lineID: 0, text: "a", start: 2, end: 2.1)
        XCTAssertEqual(WordFlowMotion.progress(position: 2.05, word: word), 1)
        XCTAssertEqual(WordFlowMotion.progress(position: 1, word: word), 0)
        XCTAssertEqual(WordFlowMotion.progress(position: 2, word: word, reduceMotion: true), 1)
    }
    func testCurrentWordIsCenteredAndReadableAtItsTimestamp() {
        let current = WordFlowMotion.pose(age: 0, progress: 0, singing: true)
        let previous = WordFlowMotion.pose(age: 1, progress: 0, singing: true)
        XCTAssertEqual(current.y, 0)
        XCTAssertEqual(current.opacity, 1)
        XCTAssertEqual(current.tape, 1)
        XCTAssertGreaterThan(current.scale, previous.scale)
        XCTAssertLessThan(previous.y, 0)
    }
    func testInstrumentalGapsHaveNoActiveTape() {
        for age in 0...3 {
            XCTAssertEqual(WordFlowMotion.pose(age: age, progress: 1, singing: false).tape, 0)
        }
    }
}
