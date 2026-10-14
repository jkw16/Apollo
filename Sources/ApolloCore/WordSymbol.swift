// Word-to-symbol resolver for the word-flow lyric presentation: lyric
// words matched to an SF Symbol shown beside the sung word. Kept separate
// from LyricEmoji (line-level matching) because words are matched by
// containment from a compact cue table, and fall back to nothing.
import Foundation

public enum WordSymbol {
    /// An SF Symbol name for the word, or nil when nothing matches.
    /// Longer cue wins so "airplane" beats "air".
    public static func resolve(word: String) -> String? {
        let key = word.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
        guard !key.isEmpty else { return nil }
        var best: (cue: String, symbol: String)?
        let cues = Self.all
        var index = 0
        while index < cues.count {
            let cue = cues[index].0
            if key.contains(cue), cue.count > (best?.cue.count ?? 0) {
                best = (cue, cues[index].1)
            }
            index += 1
        }
        return best?.symbol
    }

    // (cue, SF Symbol) — checked in order; longest containment wins.
    static let all: [(String, String)] = [
        ("airplane", "airplane"), ("flight", "airplane"), ("flew", "airplane"),
        ("fly", "airplane"), ("flying", "airplane"), ("wing", "airplane"),
        ("soar", "arrow.up.forward"), ("higher", "arrow.up"), ("rise", "arrow.up"),
        ("height", "arrow.up"), ("climb", "arrow.up"), ("up", "arrow.up"),
        ("down", "arrow.down"), ("fall", "arrow.down"), ("lower", "arrow.down"),
        ("cloud", "cloud.fill"), ("rain", "cloud.rain.fill"), ("storm", "cloud.bolt.rain.fill"),
        ("snow", "snowflake"), ("cold", "snowflake"), ("ice", "snowflake"),
        ("ship", "ferry.fill"), ("boat", "ferry.fill"), ("sail", "ferry.fill"),
        ("sea", "water.waves"), ("ocean", "water.waves"), ("wave", "water.waves"),
        ("water", "water.waves"), ("river", "water.waves"),
        ("flew", "airplane"), ("heart", "heart.fill"), ("love", "heart.fill"),
        ("hate", "heart.slash.fill"), ("lose", "heart.slash.fill"), ("lost", "heart.slash.fill"),
        ("eyes", "eye.fill"), ("eye", "eye"), ("see", "eye"), ("blind", "eye.slash"),
        ("saw", "eye"), ("watch", "eye"),
        ("brain", "brain.filled"), ("know", "brain.filled"), ("mean", "brain.filled"),
        ("think", "brain.filled"), ("thought", "brain.filled"), ("sure", "brain.filled"),
        ("fire", "flame.fill"), ("burn", "flame.fill"), ("blaze", "flame.fill"),
        ("hot", "flame.fill"), ("warm", "flame.fill"),
        ("moon", "moon.fill"), ("night", "moon.fill"), ("star", "sparkles"), ("shine", "sparkles"),
        ("sun", "sun.max.fill"), ("bright", "sun.max.fill"), ("light", "lightbulb.fill"),
        ("dark", "moon.haze"), ("shadow", "moon.haze"),
        ("cry", "drop.fill"), ("tears", "drop.fill"), ("tear", "drop.fill"), ("drop", "drop.fill"),
        ("bolt", "bolt.fill"), ("thunder", "bolt.fill"), ("electric", "bolt.fill"),
        ("sing", "music.note"), ("song", "music.note"), ("sound", "music.note"),
        ("music", "music.quarternote.3"), ("voice", "music.note"), ("melody", "music.note"),
        ("dance", "figure.dance"), ("dancing", "figure.dance"),
        ("road", "road.lanes"), ("drive", "car.side.fill"), ("crui", "car.side.fill"),
        ("car", "car.side.fill"), ("ride", "car.side.fill"),
        ("home", "house.fill"), ("house", "house.fill"), ("door", "door.left.hand.open"),
        ("crown", "crown.fill"), ("king", "crown.fill"), ("queen", "crown.fill"),
        ("flower", "leaf.fill"), ("rose", "rose.fill"), ("grow", "leaf.fill"), ("leaf", "leaf.fill"),
        ("money", "dollarsign.circle.fill"), ("gold", "banknote.fill"),
        ("hand", "hand.raised.fill"), ("clap", "hands.clap"), ("praise", "hand.raised.fill"),
        ("time", "clock.fill"), ("clock", "clock.fill"), ("clocks", "clock.fill"), ("wait", "clock.fill"),
        ("earth", "earth.americas.fill"), ("world", "earth.americas.fill"), ("planet", "earth.americas.fill"),
        ("globe", "earth.americas.fill"), ("land", "land"),
        ("wind", "wind"), ("blow", "wind"),
        ("bird", "bird"), ("wings", "bird"),
        ("talk", "message.fill"), ("say", "message.fill"), ("said", "message.fill"), ("tell", "message.fill"),
        ("phone", "phone.fill"), ("call", "phone.fill"),
        ("ghost", "ghost"), ("spook", "ghost"), ("haunt", "ghost"),
        ("rose", "rose.fill"), ("garden", "garden"),
        ("mountain", "mountain.2.fill"), ("hill", "mountain.2.fill"),
        ("city", "building.2.fill"), ("street", "building.2.fill"), ("town", "building.2.fill"),
        ("walk", "figure.walk.run"), ("run", "figure.run"), ("running", "figure.run"),
        ("smoke", "smoke.fill"), ("clouds", "cloud.fill"),
        ("game", "gamecontroller.fill"), ("play", "gamecontroller.fill"), ("playing", "gamecontroller.fill"),
        ("key", "key.horizontal.fill"), ("keys", "key.horizontal.fill"), ("open", "key.horizontal.fill"),
        ("map", "map.fill"), ("find", "map.fill"), ("lost", "map.fill"),
        ("angel", "figure.dress.ankle"),
        ("smile", "face.smiling"), ("happy", "face.smiling"), ("sad", "face.dashed"),
    ]
}