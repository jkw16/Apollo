import SwiftUI
import ApolloCore

/// Shared by the listening room, YouTube companion, and floating desktop panel.
struct TimedLyricsView: View {
    @ObservedObject var model: ApolloModel
    var compact = false
    var immersive = false
    var floating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settings: LyricAppearance { model.lyricAppearance }
    private var size: CGFloat { settings.textSize * (compact ? 0.7 : immersive ? 1.3 : 1) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let position = model.clock.elapsed(at: timeline.date) + model.lyricOffset
            let active = LRC.activeIndex(in: model.lyrics, at: position)
            Group {
                if model.lyrics.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "quote.opening").font(.system(size: 30)).foregroundStyle(apolloOrange)
                        Text("Every word,\na little closer.").font(settings.typeface.font(size: size))
                        Text("Import timed lyrics for this song to follow along.").font(.system(size: 12)).foregroundStyle(.secondary)
                        if !floating { Button("Import .lrc", action: model.importLyrics).buttonStyle(.bordered) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    GeometryReader { geometry in
                        ScrollViewReader { proxy in
                            ScrollView(.vertical) {
                                VStack(alignment: .leading, spacing: compact ? 20 : 24) {
                                    ForEach(model.lyrics) { line in
                                        let distance = abs(line.id - (active ?? 0))
                                        Button { model.control(.seek(max(0, line.time - model.lyricOffset))) } label: {
                                            Text(line.text.isEmpty ? "• • •" : line.text)
                                                .font(settings.typeface.font(size: size)).tracking(-0.4)
                                                .multilineTextAlignment(.leading)
                                                .foregroundStyle(color(for: line.id, active: active))
                                                .opacity(active == line.id ? 1 : settings.style == .ship ? 0.85 : max(0.25, 0.8 - Double(distance) * 0.12))
                                                .scaleEffect(settings.style.usesFisheye ? max(0.68, 1 - CGFloat(distance) * 0.1) : 1, anchor: .leading)
                                                .blur(radius: settings.style.usesBlur && !reduceMotion ? min(2, Double(distance) * 0.55) : 0)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }.buttonStyle(.plain).id(line.id).accessibilityLabel("Seek to \(line.text)")
                                    }
                                }.padding(.vertical, max(50, geometry.size.height / 2 - size))
                            }.scrollIndicators(.hidden)
                            .onChange(of: active, initial: true) { _, value in center(value, proxy: proxy) }
                            .onChange(of: settings) { _, _ in center(active, proxy: proxy) }
                            .onChange(of: model.trackID) { _, _ in center(active, proxy: proxy) }
                            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.15), .init(color: .black, location: 0.85), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                        }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func center(_ active: Int?, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.6)) { proxy.scrollTo(active ?? model.lyrics.first?.id ?? 0, anchor: .center) }
    }
    private func color(for index: Int, active: Int?) -> Color {
        if settings.autoSync {
            if index == active { return .white }
            return index < (active ?? -1) ? model.lyricArtworkColor : .white.opacity(0.75)
        }
        if index == active { return settings.highlight.color }
        return index < (active ?? -1) ? settings.lyricText.color : settings.secondaryText.color
    }
}
