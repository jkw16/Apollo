// Pure math for the drifting wall of covers — ported from
// wall-of-sound's wall.js/wall.css so the app view stays a renderer.
import Foundation

public enum WallGeometry {
    /// Column width in points and the gap between tiles.
    public static let tile: Double = 140
    public static let gap: Double = 14

    /// Columns derived from the container width with bleed past each edge
    /// (the `+ tile` numerator and trailing `+ 1`), so the wall never ends
    /// at the viewport.
    public static func columns(width: Double, tile: Double = WallGeometry.tile, gap: Double = WallGeometry.gap) -> Int {
        max(2, Int(ceil((width + tile) / (tile + gap))) + 1)
    }

    /// Tiles so ONE stack overfills the container height — the precondition
    /// for the seamless two-copy loop.
    public static func tilesPerColumn(height: Double, tile: Double = WallGeometry.tile, gap: Double = WallGeometry.gap, minimum: Int = 6) -> Int {
        max(minimum, Int(ceil((height * 1.35) / (tile + gap))) + 2)
    }

    /// Drift periods: slow (150–259 s) and gently varied across columns.
    /// The biggest mood lever — higher is calmer.
    public static func period(column: Int) -> TimeInterval { TimeInterval(150 + (column * 37) % 110) }

    /// Phase in [0, 1) from the absolute clock, with the reference's
    /// negative-delay desync folded in as a per-column start offset.
    /// At t = 0 columns sit at different phases, which is also what
    /// Reduce Motion freezes into.
    public static func phase(time: TimeInterval, column: Int) -> Double {
        let p = period(column: column).magnitude
        let start = (Double(column.magnitude % 1_000) * 17).truncatingRemainder(dividingBy: p)
        var phi = ((time.magnitude + start) / p).truncatingRemainder(dividingBy: 1)
        if phi < 0 { phi += 1 }
        return phi
    }

    /// Copy 1 of the stack occupies [0, H), copy 2 [H, 2H); moving either
    /// direction wraps by returning to content identical to the start.
    public static func offset(phase: Double, height: Double, up: Bool) -> Double {
        up ? -phase * height : -(1 - phase) * height
    }

    /// Deterministic tile assignment so a resize never reshuffles.
    public static func tileIndex(column: Int, row: Int, perColumn: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (abs(column) * perColumn + abs(row)) % count
    }
}

/// Fisher–Yates over the cover indexes; `rng` takes an exclusive upper
/// bound (the app passes `Int.random(in:)`, tests pass a seeded LCG).
public func wallShuffled(_ count: Int, rng: (Int) -> Int) -> [Int] {
    var a = Array(0..<max(0, count))
    for i in stride(from: a.count - 1, to: 0, by: -1) {
        let j = min(max(0, rng(i + 1)), i)
        a.swapAt(i, j)
    }
    return a
}