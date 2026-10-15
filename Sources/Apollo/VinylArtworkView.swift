import SwiftUI
import AppKit
import ApolloCore

struct VinylArtworkView: View {
    let artwork: NSImage?
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var rotation = RecordRotation()
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var rotating: Bool { playing && !reduceMotion && scenePhase == .active }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width / 1.8, proxy.size.height / 1.18)
            ZStack {
                TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 15 : 1.0 / 30, paused: !rotating)) { _ in
                    record(size: size)
                        .rotationEffect(.degrees(rotation.angle(at: now)))
                }
                .frame(width: size, height: size)
                .offset(x: size * (playing ? 0.28 : 0.17))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.75), value: playing)
                AlbumSleeve(artwork: artwork)
                    .frame(width: size, height: size)
                    .overlay(Rectangle().stroke(.white.opacity(0.16), lineWidth: 1))
                    .shadow(color: .black.opacity(0.65), radius: 22, x: 5, y: 20)
                    .offset(x: -size * 0.27)
                tonearm(size: size)
                    .frame(width: size * 0.15, height: size * 0.76)
                    .rotationEffect(.degrees(playing ? 24 : -14), anchor: .top)
                    .offset(x: size * 0.79, y: -size * 0.05)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: playing)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { rotation.setPlaying(rotating, at: now) }
        .onChange(of: rotating) { _, value in rotation.setPlaying(value, at: now) }
        .onDisappear { rotation.setPlaying(false, at: now) }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(playing ? "Vinyl record playing" : "Vinyl record paused")
    }

    private func record(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.035))
            ForEach(0..<28) { groove in
                Circle().stroke(.white.opacity(groove.isMultiple(of: 3) ? 0.10 : 0.045), lineWidth: 1)
                    .padding(CGFloat(groove) * size * 0.010 + size * 0.025)
            }
            Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.16), .clear, .white.opacity(0.09), .clear], center: .center))
            AlbumSleeve(artwork: artwork).frame(width: size * 0.32, height: size * 0.32).clipShape(Circle())
            Circle().fill(.black).frame(width: size * 0.025, height: size * 0.025)
            Circle().stroke(.white.opacity(0.4), lineWidth: 1).frame(width: size * 0.04, height: size * 0.04)
        }.drawingGroup().shadow(color: .black.opacity(0.5), radius: 12, y: 12)
    }

    private func tonearm(size: CGFloat) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [.gray, .white, .gray], startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.022, height: size * 0.65)
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.14))
                .frame(width: size * 0.065, height: size * 0.13).offset(y: size * 0.60)
            Circle().fill(.gray.gradient).frame(width: size * 0.10, height: size * 0.10).offset(y: -size * 0.05)
            Circle().fill(Color(white: 0.2)).frame(width: size * 0.035, height: size * 0.035).offset(y: -size * 0.0175)
        }.shadow(color: .black.opacity(0.65), radius: 5, x: 4, y: 5)
    }
}
