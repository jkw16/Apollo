// Pure curve for the fisheye lyric lens — the view stays a renderer.
import Foundation

/// The strength breathes while the line is actively sung and decays to zero
/// as the line ages toward its end. No Metal, no SwiftUI: the view applies
/// this as a shader argument and Reduce Motion simply never asks for it.
public enum FisheyeStrength {
    /// Max shader strength (center magnification ≈ 2.2x at mid-band).
    public static let peak: Double = 0.55
    /// Breathing period, seconds.
    public static let period: Double = 2.4
    /// Fraction of the line used to ramp strength in.
    static let attack: Double = 0.12
    /// Envelope headroom from the breath term (1 + 0.12).
    public static let maxScale: Double = peak * 1.12

    /// Strength for the actively sung line. `progress` is the fractional
    /// position into the line's duration; `elapsed` is seconds since the
    /// line started (drives the breathing). Paused playback freezes both.
    public static func active(progress: Double, elapsed: Double) -> Double {
        guard progress.isFinite, elapsed.isFinite, progress > 0, progress < 1, elapsed >= 0 else { return 0 }
        let decay = 1 - progress
        let rampIn = min(1, progress / attack)
        let breath = 1 + 0.12 * sin(2 * .pi * elapsed / period)
        return peak * decay * rampIn * breath
    }
}