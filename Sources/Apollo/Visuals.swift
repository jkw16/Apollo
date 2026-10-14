import SwiftUI
import AppKit
import AVKit
import WebKit

let apolloOrange = Color(red: 1, green: 0.43, blue: 0.24)

struct Aurora: View {
    var playing = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 / 12 : 1 / 24, paused: reduceMotion || !playing || scenePhase != .active)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate / 8
            GeometryReader { proxy in
                ZStack {
                    Color(red: 0.055, green: 0.035, blue: 0.07)
                    Ellipse().fill(Color(red: 0.65, green: 0.18, blue: 0.12)).frame(width: proxy.size.width * 0.8, height: proxy.size.height * 0.9)
                        .offset(x: sin(t) * 100 - 140, y: cos(t * 0.7) * 80 + 80)
                    Ellipse().fill(Color(red: 0.3, green: 0.12, blue: 0.5)).frame(width: proxy.size.width * 0.75, height: proxy.size.height * 0.7)
                        .offset(x: cos(t * 0.6) * 100 + 200, y: sin(t) * 100 - 60)
                    Circle().fill(Color(red: 0.95, green: 0.48, blue: 0.18).opacity(0.6)).frame(width: 280)
                        .offset(x: sin(t * 0.8) * 170, y: 190)
                }.blur(radius: 90).drawingGroup()
            }
        }.clipped().accessibilityHidden(true)
    }
}

struct EdgeGlow: View {
    var intensity: Double = 0.75
    var playing = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 / 12 : 1 / 24, paused: reduceMotion || !playing)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let gradient = AngularGradient(colors: [apolloOrange, .pink, .purple, .cyan, apolloOrange], center: .center, angle: .degrees(t * 14))
            ZStack {
                RoundedRectangle(cornerRadius: 22).stroke(gradient, lineWidth: 15).blur(radius: 14).opacity(intensity * 0.8)
                RoundedRectangle(cornerRadius: 22).stroke(gradient, lineWidth: 3).opacity(intensity)
            }.padding(5).drawingGroup()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

@MainActor final class EdgeWindows {
    private var windows: [NSPanel] = []
    private var observer: NSObjectProtocol?
    private var enabled = false
    private var intensity = 0.75
    private var allDisplays = true
    private var displayIDs = Set<String>()
    init() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
    }
    func update(enabled: Bool, intensity: Double, allDisplays: Bool, displayIDs: Set<String>) {
        self.enabled = enabled; self.intensity = intensity
        self.allDisplays = allDisplays; self.displayIDs = displayIDs
        rebuild()
    }
    private func rebuild() {
        windows.forEach { $0.orderOut(nil) }; windows.removeAll()
        guard enabled else { return }
        for screen in NSScreen.screens where allDisplays || displayIDs.contains(screen.edgeGlowID) {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
            panel.ignoresMouseEvents = true; panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: EdgeGlow(intensity: intensity))
            panel.orderFrontRegardless(); windows.append(panel)
        }
    }
}

struct MotionArtwork: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.controlsStyle = .none; view.videoGravity = .resizeAspectFill; view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player = nil }
}

struct YouTubePlayer: NSViewRepresentable {
    let videoID: String
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedID != videoID else { return }
        context.coordinator.loadedID = videoID
        let url = URL(string: "https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&controls=1")!
        var request = URLRequest(url: url)
        let bundle = Bundle.main.bundleIdentifier ?? "io.github.jkw16.apollo"
        request.setValue("https://\(bundle.lowercased())", forHTTPHeaderField: "Referer")
        view.load(request)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator { var loadedID: String? }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { view.loadHTMLString("", baseURL: nil) }
}
