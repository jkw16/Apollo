import Foundation

public enum ArtworkStyle: String, CaseIterable, Identifiable {
    // Retain stored identifiers from the first artwork-style build.
    case albumWall = "standard", albumCover = "fullscreenMotion", turntable = "vinyl"
    public static var allCases: [Self] { [.albumWall, .turntable, .albumCover] }
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .albumWall: return "Album Wall"
        case .albumCover: return "Album Cover"
        case .turntable: return "Turntable"
        }
    }
}

/// Integrates only playing time, so pausing never resets the record angle.
public struct RecordRotation {
    private var degrees: Double = 0
    private var started: TimeInterval?
    public init() {}
    public func angle(at time: TimeInterval) -> Double {
        (degrees + (started.map { max(0, time - $0) * 200 } ?? 0)).truncatingRemainder(dividingBy: 360)
    }
    public mutating func setPlaying(_ playing: Bool, at time: TimeInterval) {
        if playing, started == nil { started = time }
        else if !playing, started != nil { degrees = angle(at: time); started = nil }
    }
}
