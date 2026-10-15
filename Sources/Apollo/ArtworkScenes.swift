import AppKit
import AVFoundation
import SwiftUI

/// Static artwork stays underneath the video until its first frame is ready.
struct FullscreenMotionCover: View {
    let artwork: NSImage?
    let player: AVPlayer?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AlbumSleeve(artwork: artwork)
                if let player { CoverVideoLayer(player: player) }
            }
            .frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }.accessibilityHidden(true)
    }
}

struct AlbumSleeve: View {
    let artwork: NSImage?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.12, green: 0.09, blue: 0.18)
                if let artwork {
                    Image(nsImage: artwork).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else {
                    Image(systemName: "opticaldisc").resizable().scaledToFit()
                        .padding(50).foregroundStyle(.white.opacity(0.3))
                }
            }
        }
    }
}

private struct CoverVideoLayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> VideoSurface { VideoSurface() }
    func updateNSView(_ view: VideoSurface, context: Context) { view.attach(player) }
    static func dismantleNSView(_ view: VideoSurface, coordinator: ()) { view.detach() }
}

private final class VideoSurface: NSView {
    private let video = AVPlayerLayer()
    private var readyObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        video.videoGravity = .resizeAspectFill
        video.opacity = 0
        layer?.addSublayer(video)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        video.frame = bounds
        CATransaction.commit()
    }
    func attach(_ player: AVPlayer) {
        guard video.player !== player else { return }
        detach(); video.player = player
        readyObservation = video.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateVisibility() }
        }
        currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.observeItem() }
        }
        statusObservation = player.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateVisibility() }
        }
    }
    private func observeItem() {
        itemStatusObservation = video.player?.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateVisibility() }
        }
        updateVisibility()
    }
    private func updateVisibility() {
        CATransaction.begin(); CATransaction.setAnimationDuration(0.25)
        video.opacity = video.isReadyForDisplay && video.player?.status != .failed && video.player?.currentItem?.status != .failed ? 1 : 0
        CATransaction.commit()
    }
    func detach() {
        readyObservation = nil; statusObservation = nil
        currentItemObservation = nil; itemStatusObservation = nil
        video.player = nil; video.opacity = 0
    }
}

/// Two artwork samples, computed only when the metadata pipeline changes its image.
struct ArtworkPalette {
    var top = Color(red: 0.16, green: 0.12, blue: 0.26)
    var bottom = Color(red: 0.06, green: 0.14, blue: 0.2)
    init(_ image: NSImage? = nil) {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        guard let context = CGContext(data: &pixels, width: 8, height: 8, bitsPerComponent: 8,
                                      bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        func color(_ rows: Range<Int>) -> Color {
            var rgb = [Double](repeating: 0, count: 3)
            for y in rows { for x in 0..<8 { for c in 0..<3 { rgb[c] += Double(pixels[(y * 8 + x) * 4 + c]) } } }
            let count = Double(rows.count * 8) * 255
            return Color(red: rgb[0] / count * 0.6, green: rgb[1] / count * 0.6, blue: rgb[2] / count * 0.6)
        }
        top = color(0..<4); bottom = color(4..<8)
    }
}
