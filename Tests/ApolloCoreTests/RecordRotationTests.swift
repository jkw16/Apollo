import XCTest
@testable import ApolloCore

final class RecordRotationTests: XCTestCase {
    func testPauseHoldsAngleAndResumeContinues() {
        var rotation = RecordRotation()
        XCTAssertEqual(rotation.angle(at: 100), 0)
        rotation.setPlaying(true, at: 100)
        XCTAssertEqual(rotation.angle(at: 101), 200)
        rotation.setPlaying(false, at: 101)
        XCTAssertEqual(rotation.angle(at: 900), 200)
        rotation.setPlaying(true, at: 900)
        XCTAssertEqual(rotation.angle(at: 900.5), 300)
    }
    func testRepeatedPlaybackPollDoesNotResetRotation() {
        var rotation = RecordRotation()
        rotation.setPlaying(true, at: 10)
        rotation.setPlaying(true, at: 11)
        XCTAssertEqual(rotation.angle(at: 12), 40)
        rotation.setPlaying(false, at: 12)
        rotation.setPlaying(false, at: 13)
        XCTAssertEqual(rotation.angle(at: 14), 40)
    }
}
