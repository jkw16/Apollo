import XCTest
@testable import ApolloCore

final class FisheyeStrengthTests: XCTestCase {
    func testZeroAtLineBoundariesAndBadInput() {
        XCTAssertEqual(FisheyeStrength.active(progress: 0, elapsed: 0), 0)
        XCTAssertEqual(FisheyeStrength.active(progress: 1, elapsed: 60), 0)
        XCTAssertEqual(FisheyeStrength.active(progress: 0.5, elapsed: -1), 0)
        XCTAssertEqual(FisheyeStrength.active(progress: .nan, elapsed: 1), 0)
        XCTAssertEqual(FisheyeStrength.active(progress: 1.5, elapsed: 1), 0)
        XCTAssertEqual(FisheyeStrength.active(progress: 0.5, elapsed: .infinity), 0)
    }

    func testRampInIncreasesAndDecayDecreases() {
        var last = -1.0
        for f in stride(from: 0.0, through: FisheyeStrength.attack, by: 0.01) {
            let value = FisheyeStrength.active(progress: f, elapsed: 3)
            XCTAssertGreaterThan(value, last, "ramp-in must increase at \(f)")
            last = value
        }
        last = .infinity
        for f in stride(from: FisheyeStrength.attack + 0.01, through: 0.99, by: 0.01) {
            let value = FisheyeStrength.active(progress: f, elapsed: 3)
            XCTAssertLessThan(value, last, "decay must decrease at \(f)")
            last = value
        }
    }

    func testStrengthStaysInsideEnvelope() {
        for f in stride(from: 0.01, through: 0.99, by: 0.01) {
            for e in stride(from: 0.0, through: 12.0, by: 0.17) {
                let value = FisheyeStrength.active(progress: f, elapsed: e)
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, FisheyeStrength.maxScale + 1e-9)
            }
        }
    }

    func testBreathingIsPeriodic() {
        let first = FisheyeStrength.active(progress: 0.5, elapsed: 0.6)
        let wrapped = FisheyeStrength.active(progress: 0.5, elapsed: FisheyeStrength.period + 0.6)
        XCTAssertEqual(first, wrapped, accuracy: 1e-9)
    }

    func testPeakSitsInsideTheRampNotAtLineStart() {
        // The envelope is ramp × decay, so the maximum must be past the
        // ramp-in window, never at progress → 0.
        let values = (0..<100).map { FisheyeStrength.active(progress: Double($0) / 100, elapsed: 3) }
        guard let maximum = values.max() else { return }
        XCTAssertEqual(maximum, FisheyeStrength.maxScale, accuracy: 0.1)
        guard let best = values.firstIndex(of: maximum) else { return }
        XCTAssertGreaterThan(Double(best) / 100, FisheyeStrength.attack / 2)
    }
}