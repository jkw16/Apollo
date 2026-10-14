// The wall of sound: square album covers in columns that drift very
// slowly in alternating directions, a SwiftUI port of wall-of-sound's
// wall.js / wall.css. Decorative only — hit testing and accessibility
// are disabled, and Reduce Motion freezes it into a still collage.
import SwiftUI
import AppKit
import ApolloCore

private let placeholderTint = Color(red: 0.09, green: 0.085, blue: 0.11)
private let wallBackdrop = Color(red: 0.05, green: 0.045, blue: 0.06)

struct WallOfSound: View {
    let covers: [CoverRecord]
    let directory: URL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cache = NSCache<NSString, NSImage>()
    @State private var loaded = 0
    @State private var deck: [Int] = []

    var body: some View {
        GeometryReader { proxy in
            let vw = max(WallGeometry.tile, proxy.size.width)
            let vh = max(1, proxy.size.height)
            ZStack {
                wallBackdrop
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                    // Like Aurora: freeze t at 0 under Reduce Motion so the
                    // still collage keeps the columns' varied phases instead
                    // of collapsing into an aligned grid.
                    let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    let cols = WallGeometry.columns(width: vw)
                    let perCol = WallGeometry.tilesPerColumn(height: vh)
                    HStack(spacing: WallGeometry.gap) {
                        ForEach(0..<cols, id: \.self) { column in
                            WallColumn(deck: deck, covers: covers, column: column, perColumn: perCol,
                                       directory: directory, cache: cache, loaded: loaded,
                                       up: column % 2 == 0,
                                       phase: WallGeometry.phase(time: t, column: column),
                                       bleed: -0.22 * vh)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { refreshDeck(); fillCache() }
        .onChange(of: covers) { _, _ in refreshDeck(); fillCache() }
    }

    private func refreshDeck() {
        guard !covers.isEmpty else { deck = []; return }
        deck = wallShuffled(covers.count, rng: { Int.random(in: 0..<$0) })
    }

    private func fillCache() {
        guard !covers.isEmpty else { return }
        let manifest = covers
        let target = directory
        let imageCache = cache
        Task.detached(priority: .utility) {
            for record in manifest where imageCache.object(forKey: record.file as NSString) == nil {
                if let image = NSImage(contentsOf: target.appendingPathComponent(record.file)) {
                    imageCache.setObject(image, forKey: record.file as NSString, cost: estimateCost(image))
                }
            }
            await MainActor.run {
                if !manifest.isEmpty { loaded += 1 }
            }
        }
    }
}

/// One drifting column: a stack built once, rendered as two copies so the
/// loop wraps seamlessly. The offset sits OUTSIDE the drawingGroup — the
/// texture never changes per tick; only the column's transform moves.
private struct WallColumn: View {
    let deck: [Int]
    let covers: [CoverRecord]
    let column: Int
    let perColumn: Int
    let directory: URL
    let cache: NSCache<NSString, NSImage>
    let loaded: Int
    let up: Bool
    let phase: Double
    let bleed: Double

    var body: some View {
        VStack(spacing: 0) {
            // Two full copies; every tile carries the bottom padding rather
            // than using VStack spacing, so the track is exactly 2 halves.
            ForEach(0..<(perColumn * 2), id: \.self) { row in
                tile(row % perColumn).padding(.bottom, WallGeometry.gap)
            }
        }
        .drawingGroup()
        .offset(y: bleed + WallGeometry.offset(
            phase: phase, height: Double(perColumn) * (WallGeometry.tile + WallGeometry.gap), up: up))
    }

    @ViewBuilder
    private func tile(_ row: Int) -> some View {
        let slot = deck.isEmpty ? row
            : deck[WallGeometry.tileIndex(column: column, row: row, perColumn: perColumn, count: deck.count)]
        ZStack {
            placeholderTint
            if slot < covers.count,
               let image = cache.object(forKey: covers[slot].file as NSString) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: WallGeometry.tile, height: WallGeometry.tile).clipped()
            }
        }
        .frame(width: WallGeometry.tile, height: WallGeometry.tile)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Rough decoded-pixel budget for NSCache eviction (4 bytes per pixel).
private func estimateCost(_ image: NSImage) -> Int {
    let pixels = image.representations.map { $0.pixelsWide * $0.pixelsHigh }.max() ?? 0
    return Int(pixels * 4)
}