// Word-level lyric stream interpolated from line-level LRC. Line-level
// sources carry no word timing, so each line's duration is distributed
// across its words by length — the same interpolation the reference app
// performs ("interpolated from line-level") — while real word timestamps
// would be passable straight through later.
import Foundation

public struct TimedWord: Identifiable, Equatable {
    public let id: Int
    public let lineID: Int
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public init(id: Int, lineID: Int, text: String, start: TimeInterval, end: TimeInterval) {
        self.id = id; self.lineID = lineID; self.text = text; self.start = start; self.end = end
    }
}

public enum WordStream {
    /// Flatten lyric lines into a timed word stream. Blank (instrumental)
    /// lines produce no words but still advance time; the stream's active
    /// index becomes nil during those gaps.
    public static func words(in lines: [LyricLine]) -> [TimedWord] {
        var result: [TimedWord] = []
        var id = 0
        for (index, line) in lines.enumerated() where !line.text.isEmpty {
            // End where the next line starts, blank or not: blank (instrumental)
            // lines must terminate song words and leave the gap idle.
            let next = lines[(index + 1)...].first
            let end = next?.time ?? line.time + 5
            let raw = line.text.split(separator: " ", omittingEmptySubsequences: true)
            guard !raw.isEmpty else { continue }
            let weights = raw.map { max(1, $0.count) }
            let total = max(1, weights.reduce(0, +))
            let duration = max(0.25, end - line.time)
            var at = line.time
            for (w, word) in zip(weights, raw) {
                let span = duration * Double(w) / Double(total)
                result.append(TimedWord(id: id, lineID: line.id, text: String(word), start: at, end: at + span))
                at += span
                id += 1
            }
        }
        return result
    }

    /// The word being sung at a position, or nil during instrumental gaps.
    public static func activeIndex(in words: [TimedWord], at position: TimeInterval) -> Int? {
        guard !words.isEmpty else { return nil }
        var low = 0, high = words.count
        while low < high {
            let mid = (low + high) / 2
            if position >= words[mid].start { low = mid + 1 } else { high = mid }
        }
        let candidate = low - 1
        guard candidate >= 0 else { return nil }
        // Past the final word's end the stream is idle, not singing.
        return position <= words[candidate].end ? candidate : nil
    }
}