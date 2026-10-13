import Foundation

public struct LyricLine: Equatable, Identifiable, Codable {
    public let id: Int
    public let time: TimeInterval
    public let text: String
}

public enum LRC {
    /// Supports repeated timestamps, fractional seconds, metadata and millisecond offsets.
    public static func parse(_ input: String) -> [LyricLine] {
        let stamps = try! NSRegularExpression(pattern: #"\[(\d+):(\d{2})(?:\.(\d{1,3}))?\]"#)
        let offsets = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let nsInput = input as NSString
        let offset = offsets.matches(in: input, range: NSRange(location: 0, length: nsInput.length)).last
            .flatMap { Double(nsInput.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        var rows: [(Double, String, Int)] = []
        for line in input.components(separatedBy: .newlines) {
            let ns = line as NSString
            let matches = stamps.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
                guard seconds < 60 else { continue }
                let fraction = match.range(at: 3).location == NSNotFound ? 0 :
                    Double("0." + ns.substring(with: match.range(at: 3))) ?? 0
                rows.append((max(0, minutes * 60 + seconds + fraction + offset), text, rows.count))
            }
        }
        return rows.sorted { $0.0 == $1.0 ? $0.2 < $1.2 : $0.0 < $1.0 }
            .enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    public static func activeIndex(in lines: [LyricLine], at time: TimeInterval) -> Int? {
        // Upper-bound search: the last timestamp <= playback time wins, including blank interludes.
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }
}

public enum YouTubeURL {
    public static func videoID(from input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid: (String) -> Bool = { $0.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil }
        if valid(value) { return value }
        guard let components = URLComponents(string: value),
              components.scheme == "https" || components.scheme == "http",
              let host = components.host?.lowercased() else { return nil }
        let pieces = components.path.split(separator: "/").map(String.init)
        let id: String?
        switch host {
        case "youtu.be", "www.youtu.be": id = pieces.first
        case "youtube.com", "www.youtube.com", "m.youtube.com", "www.youtube-nocookie.com":
            if ["embed", "shorts", "live"].contains(pieces.first ?? ""), pieces.count == 2 { id = pieces[1] }
            else if components.path == "/watch" { id = components.queryItems?.first(where: { $0.name == "v" })?.value }
            else { id = nil }
        default: id = nil
        }
        return id.flatMap { valid($0) ? $0 : nil }
    }
}

public struct PlaybackClock {
    public var position: TimeInterval
    public var duration: TimeInterval
    public var playing: Bool
    public var sampledAt: Date

    public init(position: TimeInterval, duration: TimeInterval, playing: Bool, sampledAt: Date = Date()) {
        self.position = position; self.duration = duration; self.playing = playing; self.sampledAt = sampledAt
    }

    public func elapsed(at date: Date) -> TimeInterval {
        min(max(0, duration), max(0, position + (playing ? max(0, date.timeIntervalSince(sampledAt)) : 0)))
    }
}
