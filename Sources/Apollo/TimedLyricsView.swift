import SwiftUI
import ApolloCore

/// Shared by the listening room, YouTube companion, and floating desktop panel.
struct TimedLyricsView: View {
    @ObservedObject var model: ApolloModel
    var compact = false
    var immersive = false
    var floating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var emojis: [Int: String] = [:]

    private var settings: LyricAppearance { model.lyricAppearance }
    private var size: CGFloat { settings.textSize * (compact ? 0.7 : immersive ? 1.3 : 1) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let position = model.clock.elapsed(at: timeline.date) + model.lyricOffset
            let active = LRC.activeIndex(in: model.lyrics, at: position)
            Group {
                if model.lyrics.isEmpty && !model.plainLyrics.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(model.lyricStatus).font(.caption).foregroundStyle(.secondary)
                            Text(model.plainLyrics).font(settings.typeface.font(size: size * 0.8))
                                .textSelection(.enabled)
                        }
                    }
                } else if model.lyrics.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "quote.opening").font(.system(size: 30)).foregroundStyle(apolloOrange)
                        Text("Every word,\na little closer.").font(settings.typeface.font(size: size))
                        Text(model.lyricStatus).font(.system(size: 12)).foregroundStyle(.secondary)
                        if model.loadingLyrics { ProgressView().controlSize(.small) }
                        if !floating && !model.trackID.isEmpty {
                            if model.automaticLyricsEnabled && !model.loadingLyrics {
                                Button("Try lyrics again", action: model.retryLyrics).buttonStyle(.bordered)
                            }
                            Button("Import lyrics…", action: model.importLyrics).buttonStyle(.borderless)
                        }
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
                .overlay(alignment: .topTrailing) {
                    if settings.style.usesEmoji, let active, let emoji = emojis[active] {
                        LyricEmojiBurst(emoji: emoji, size: min(76, size * 1.65))
                            .id("\(model.trackID):\(active):\(emoji)")
                            .padding(.top, 8).padding(.trailing, 8)
                    }
                }
        }
        .onChange(of: model.lyrics, initial: true) { _, _ in refreshEmojis() }
        .onChange(of: model.title) { _, _ in refreshEmojis() }
        .onChange(of: model.artist) { _, _ in refreshEmojis() }
    }

    private func refreshEmojis() {
        // Cache per line rather than rescanning lyric text on every playback tick.
        emojis = Dictionary(uniqueKeysWithValues: model.lyrics.compactMap { line in
            LyricEmoji.resolve(line: line.text, title: model.title, artist: model.artist).map { (line.id, $0) }
        })
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

/// A transient effect anchored to the lyric viewport, never to a scrolling lyric row.
private struct LyricEmojiBurst: View {
    let emoji: String
    let size: CGFloat
    @State private var appearedAt = Date()
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: finished)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(appearedAt))
            let enter = min(1, elapsed / 0.3)
            let fade = min(1, max(0, (2.7 - elapsed) / 0.65))
            // Ease-out-back produces one small pop, followed by a gentle upward drift.
            let pop = 1 + 2.70158 * pow(enter - 1, 3) + 1.70158 * pow(enter - 1, 2)
            Text(emoji)
                .font(.system(size: size))
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
                .scaleEffect(reduceMotion ? 1 : 0.45 + pop * 0.55)
                .offset(y: reduceMotion ? 0 : 14 - min(elapsed / 2.7, 1) * 34)
                .opacity(finished ? 0 : reduceMotion ? 1 : min(1, elapsed / 0.12) * fade)
                .frame(width: size * 1.5, height: size * 1.6)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .task {
            do {
                try await Task.sleep(for: .seconds(2.7))
                finished = true
            } catch { /* A new lyric or style replaces and cancels this burst. */ }
        }
    }
}
