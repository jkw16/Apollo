import SwiftUI
import ApolloCore

/// A fixed, centered stage. Each word retains one view as it moves from
/// the tape strip through the large center word and out above it.
struct WordFlowView: View {
    @ObservedObject var model: ApolloModel
    var compact = false
    @State private var stream: [TimedWord] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !model.clock.playing)) { timeline in
                let position = model.clock.elapsed(at: timeline.date) + model.lyricOffset
                let active = WordStream.activeIndex(in: stream, at: position)
                let anchor = active ?? (stream.lastIndex { $0.start <= position } ?? -1)
                let base = min(96, min(geometry.size.height * (compact ? 0.11 : 0.13), 64)
                    * model.lyricAppearance.textSize / 33)
                let progress = stream.indices.contains(anchor)
                    ? WordFlowMotion.progress(position: position, word: stream[anchor], reduceMotion: reduceMotion) : 1
                ZStack {
                    ForEach(visibleWords(anchor)) { word in
                        let pose = WordFlowMotion.pose(age: anchor - word.id, progress: progress, singing: active != nil)
                        FlowWord(word: word, pose: pose, baseSize: base,
                                 settings: model.lyricAppearance,
                                 reduceMotion: reduceMotion)
                            .frame(width: max(1, geometry.size.width / 1.4))
                            .scaleEffect(pose.scale)
                            .opacity(pose.opacity)
                            .offset(y: pose.y * base)
                            .transition(.identity)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                // Clock-driven geometry must never inherit a parent spring or
                // crossfade: that creates trailing copies on rapid word changes.
                .transaction { $0.animation = nil }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(active.map { stream[$0].text } ?? "Lyrics paused between words")
            }
        }
        .onAppear {
            refreshStream()
        }
        .onChange(of: model.lyrics) { _, _ in refreshStream() }
    }

    private func visibleWords(_ anchor: Int) -> [TimedWord] {
        guard stream.indices.contains(anchor) else { return [] }
        return Array(stream[max(0, anchor - 3)...anchor])
    }

    private func refreshStream() { stream = WordStream.words(in: model.lyrics) }
}

private struct FlowWord: View {
    let word: TimedWord
    let pose: WordFlowPose
    let baseSize: CGFloat
    let settings: LyricAppearance
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: baseSize * 0.16) {
            Text(word.text)
                .font(settings.typeface.font(size: baseSize))
                .lineLimit(1).minimumScaleFactor(0.2)
                .foregroundStyle(Color(white: 1 - pose.tape))
                .padding(.horizontal, baseSize * 0.16)
                .padding(.vertical, baseSize * 0.025)
                .background(.white.opacity(pose.tape), in: RoundedRectangle(cornerRadius: baseSize * 0.035))
            if settings.style.usesEmoji, let symbol = WordSymbol.resolve(word: word.text) {
                Image(systemName: symbol)
                    .font(.system(size: baseSize * 0.55))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
        .rotationEffect(.degrees(reduceMotion ? 0 : Double(((word.id * 11) % 5) - 2) * 0.6 * pose.tape))
    }

}
