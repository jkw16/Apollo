import SwiftUI
import AppKit
import ImageIO
import ApolloCore

/// Thumbnail work is cancellable, serial, and bounded to 120 × 300px images
/// (about 42 MiB of decoded pixels, excluding framework/GPU overhead).
@MainActor private final class WallImages: ObservableObject {
    @Published var images: [String: NSImage] = [:]
    func load(_ covers: [CoverRecord], directory: URL) async {
        let existing = images
        let worker = Task.detached(priority: .utility) {
            var result: [String: NSImage] = [:]
            for record in covers.prefix(WallBudget.albums) {
                guard !Task.isCancelled else { return result }
                if let cached = existing[record.file] { result[record.file] = cached; continue }
                // Files come from the app's cache; never decode original-size artwork.
                guard let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(record.file) as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 300,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { continue }
                result[record.file] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
            return result
        }
        let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled else { return }
        images = result
    }
}

struct WallOfSound: View {
    let covers: [CoverRecord]
    let directory: URL
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var loader = WallImages()
    @State private var visible = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var phaseTime = Date().timeIntervalSinceReferenceDate
    @State private var lastTick: Date?

    private var paused: Bool { reduceMotion || !playing || scenePhase != .active || !visible }
    var body: some View {
        GeometryReader { geometry in
            let width = max(WallGeometry.tile, geometry.size.width)
            let height = max(1, geometry.size.height)
            let columns = WallGeometry.columns(width: width)
            let rows = WallGeometry.tilesPerColumn(height: height)
            ZStack {
                Color(red: 0.05, green: 0.045, blue: 0.06)
                TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 12 : 1.0 / 24, paused: paused)) { timeline in
                    HStack(spacing: WallGeometry.gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            WallColumn(covers: covers, images: loader.images, column: column, rows: rows)
                                .offset(y: -0.22 * height + WallGeometry.offset(
                                    phase: WallGeometry.phase(time: reduceMotion ? 0 : phaseTime, column: column),
                                    height: Double(rows) * (WallGeometry.tile + WallGeometry.gap), up: column % 2 == 0))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .onChange(of: timeline.date) { _, now in
                        if !paused, let lastTick { phaseTime += min(0.1, max(0, now.timeIntervalSince(lastTick))) }
                        lastTick = now
                    }
                }
            }.clipped()
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: covers.map(\.file)) { await loader.load(covers, directory: directory) }
        .onChange(of: paused) { _, _ in lastTick = nil }
        .onAppear { updateVisibility() }
        .onDisappear { loader.images = [:] }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { _ in updateVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
    private func updateVisibility() {
        visible = NSApp.windows.contains { $0.identifier?.rawValue == "apollo" && $0.occlusionState.contains(.visible) && !$0.isMiniaturized }
    }
}

private struct WallColumn: View {
    let covers: [CoverRecord]
    let images: [String: NSImage]
    let column: Int
    let rows: Int
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<(rows * 2), id: \.self) { row in
                let slot = WallGeometry.tileIndex(column: column, row: row % rows, perColumn: rows, count: covers.count)
                ZStack {
                    Color(red: 0.09, green: 0.085, blue: 0.11)
                    if covers.indices.contains(slot), let image = images[covers[slot].file] {
                        Image(nsImage: image).resizable().scaledToFit()
                    }
                }
                .frame(width: WallGeometry.tile, height: WallGeometry.tile)
                .padding(.bottom, WallGeometry.gap)
            }
        }
        .drawingGroup()
    }
}
