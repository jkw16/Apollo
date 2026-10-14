import Foundation

/// Seek-safe word choreography. Values are in units of the base font size;
/// no animation state is accumulated between playback ticks.
public struct WordFlowPose: Equatable {
    public let y: Double
    public let scale: Double
    public let opacity: Double
    public let tape: Double
}

public enum WordFlowMotion {
    public static func progress(position: Double, word: TimedWord, reduceMotion: Bool = false) -> Double {
        if reduceMotion { return 1 }
        let duration = min(0.24, max(0.001, (word.end - word.start) * 0.45))
        let t = min(1, max(0, (position - word.start) / duration))
        return 1 - pow(1 - t, 3)
    }

    public static func pose(age: Int, progress: Double, singing: Bool) -> WordFlowPose {
        let t = min(1, max(0, progress))
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        switch age {
        case 0: return WordFlowPose(y: mix(2.4, 1.4), scale: mix(0.65, 0.85), opacity: t, tape: singing ? 1 : 0)
        case 1: return WordFlowPose(y: mix(1.4, 0), scale: mix(0.85, 1.3), opacity: mix(1, 0.78), tape: singing ? 1 - t : 0)
        case 2: return WordFlowPose(y: mix(0, -1.4), scale: mix(1.3, 0.7), opacity: mix(0.78, 0.56), tape: 0)
        case 3: return WordFlowPose(y: mix(-1.4, -2.4), scale: mix(0.7, 0.45), opacity: 0.56 * (1 - t), tape: 0)
        default: return WordFlowPose(y: 0, scale: 1, opacity: 0, tape: 0)
        }
    }
}
