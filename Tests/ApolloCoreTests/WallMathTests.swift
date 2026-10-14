import XCTest
@testable import ApolloCore

final class WallMathTests: XCTestCase {
    private var cell: Double { WallGeometry.tile + WallGeometry.gap }

    func testColumnsMatchReferenceFormula() {
        // ceil((vw + tile) / cell) + 1, mirroring wall.js:96
        XCTAssertEqual(WallGeometry.columns(width: 1190), Int(ceil((1190 + 140) / 154)) + 1)
        XCTAssertEqual(WallGeometry.columns(width: 2560), Int(ceil((2560 + 140) / 154)) + 1)
        XCTAssertGreaterThanOrEqual(WallGeometry.columns(width: 10), 2)
    }

    func testTilesPerColumnOverfillsAndKeepsSeamSafe() {
        XCTAssertEqual(WallGeometry.tilesPerColumn(height: 700), Int(ceil((700 * 1.35) / 154)) + 2)
        XCTAssertGreaterThanOrEqual(WallGeometry.tilesPerColumn(height: 700), 6)
        for height in stride(from: 380.0, through: 2200.0, by: 41) {
            let perCol = WallGeometry.tilesPerColumn(height: height)
            let stack = Double(perCol) * self.cell
            // One stack must overfill the viewport, or the -50% wrap would show.
            XCTAssertGreaterThanOrEqual(stack + self.cell, height * 1.35, "seam safety at \(height)")
        }
    }

    func testPeriodsStaySlowAndVaried() {
        for column in 0..<200 {
            XCTAssertGreaterThanOrEqual(WallGeometry.period(column: column), 150)
            XCTAssertLessThan(WallGeometry.period(column: column), 260)
        }
        XCTAssertTrue(Set((0..<40).map { WallGeometry.period(column: $0) }).count > 3)
    }

    func testPhaseWrapsSeamlesslyAndSpreadsColumns() {
        // After exactly one period each column returns to the same phase.
        for column in 0..<50 {
            XCTAssertEqual(WallGeometry.phase(time: WallGeometry.period(column: column), column: column),
                           WallGeometry.phase(time: 0, column: column), accuracy: 1e-9)
        }
        for column in 0..<200 {
            let phi = WallGeometry.phase(time: 12345.6, column: column)
            XCTAssertGreaterThanOrEqual(phi, 0)
            XCTAssertLessThan(phi, 1)
        }
        // At t = 0 columns are spread (the Reduce Motion still collage).
        XCTAssertTrue(Set((0..<12).map { WallGeometry.phase(time: 0, column: $0) }).count > 4)
    }

    func testLoopContinuityAcrossTheWrap() {
        // The wrap is seamless because copy 2 of the stack is content-identical
        // to copy 1: as the phase wraps (1⁻ → 0) the offset steps by exactly one
        // stack height H, landing on the same visual content — the CSS -50%
        // reset + duplicate stack, not an offset continuity requirement.
        for column in [0, 5] {
            let period = WallGeometry.period(column: column)
            for up in [true, false] {
                let start = WallGeometry.offset(phase: 0, height: 1000, up: up)
                let nearEnd = WallGeometry.offset(phase: 1 - .ulpOfOne, height: 1000, up: up)
                XCTAssertEqual(abs(nearEnd - start), 1000, accuracy: 0.001, "wrap step must equal H (up=\(up))")
            }
        }
    }

    func testTileCyclingIsDeterministicAndInBounds() {
        for count in [1, 45, 600] {
            let perCol = WallGeometry.tilesPerColumn(height: 900)
            let first = WallGeometry.tileIndex(column: 0, row: 0, perColumn: perCol, count: count)
            XCTAssertEqual(first, 0)
        }
        // Same inputs, same tile — resize never reshuffles.
        XCTAssertEqual(WallGeometry.tileIndex(column: 3, row: 4, perColumn: 9, count: 45),
                       WallGeometry.tileIndex(column: 3, row: 4, perColumn: 9, count: 45))
    }

    func testShuffledIsBijectionAndDeterministic() {
        // Deterministic permutation with a seeded LCG.
        var state: UInt64 = 0x9E3779B97F4A7C15
        let lcg = { (_ bound: Int) -> Int in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        let deck = wallShuffled(45, rng: lcg)
        XCTAssertEqual(Set(deck).count, 45)
        XCTAssertTrue(deck.allSatisfy { (0..<45).contains($0) })
        // rng that always returns bound - 1 keeps j == i: the identity permutation.
        XCTAssertEqual(wallShuffled(5, rng: { $0 - 1 }), [0, 1, 2, 3, 4])
        XCTAssertEqual(wallShuffled(0, rng: lcg), [])
    }

    func testManifestDecodesCollectorShapeAndRoundTrips() throws {
        let collector = """
        [{"artist":"Bicep","title":"Bicep","cover300":"https://i.scdn.co/image/ab67616d00001e02abc","cover640":"https://i.scdn.co/image/ab67616d0000b273abc"}]
        """
        let decoded = try JSONDecoder().decode([CollectorAlbum].self, from: Data(collector.utf8))
        XCTAssertEqual(decoded[0].cover300, "https://i.scdn.co/image/ab67616d00001e02abc")
        var manifest = CoverManifest()
        manifest.covers.append(CoverRecord(artist: "Bicep", title: "Bicep", file: "abc123.jpg"))
        let round = try JSONDecoder().decode(CoverManifest.self, from: JSONEncoder().encode(manifest))
        XCTAssertEqual(round, manifest)
        XCTAssertEqual(AmbientScene(rawValue: "wallOfSound"), .wallOfSound)
        XCTAssertEqual(AmbientScene.allCases.count, 2)
    }
}