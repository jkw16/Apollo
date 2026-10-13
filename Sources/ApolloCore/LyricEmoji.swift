import Foundation

/// An offline, deterministic text matcher. It uses lyric imagery, not audio analysis.
public enum LyricEmoji {
    private struct Theme {
        let emoji: String
        let cues: [String]
    }

    // Specific phrases take precedence over individual words (e.g. heartbreak over love).
    private static let themes: [Theme] = [
        Theme(emoji: "💔", cues: ["broken heart", "broke my heart", "heartbreak", "heartbroken", "not in love", "don’t love", "don't love", "no love", "lost love", "corazon roto", "break up", "goodbye", "adios"]),
        Theme(emoji: "🌤️", cues: ["no more tears", "after the storm", "brighter days", "new beginning"]),
        Theme(emoji: "🕊️", cues: ["let you go", "set me free", "set you free", "fly away", "freedom", "peace", "libertad", "paz"]),
        Theme(emoji: "❤️", cues: ["in love", "te amo", "te quiero", "love", "loving", "lover", "heart", "hearts", "amor", "corazon"]),
        Theme(emoji: "💋", cues: ["kiss", "kisses", "kissing", "beso", "besos"]),
        Theme(emoji: "🌧️", cues: ["rain", "raining", "storm", "storms", "thunder", "lluvia", "tormenta"]),
        Theme(emoji: "😢", cues: ["cry", "crying", "cried", "tears", "sad", "sadness", "lonely", "alone", "llorar", "lagrimas", "triste"]),
        Theme(emoji: "🔥", cues: ["on fire", "fire", "flames", "flame", "burn", "burning", "fuego", "arder"]),
        Theme(emoji: "🌙", cues: ["moon", "moonlight", "midnight", "night", "tonight", "darkness", "luna", "noche"]),
        Theme(emoji: "☀️", cues: ["sun", "sunshine", "sunrise", "summer", "golden", "sol", "verano"]),
        Theme(emoji: "🌊", cues: ["ocean", "sea", "waves", "wave", "water", "river", "tide", "mar", "olas", "agua"]),
        Theme(emoji: "🌌", cues: ["universe", "galaxy", "space", "cosmos", "universo", "espacio"]),
        Theme(emoji: "✨", cues: ["stars", "star", "starlight", "sparkle", "shine", "shining", "light", "lights", "glow", "estrellas", "luz", "brillar"]),
        Theme(emoji: "🎨", cues: ["color", "colors", "colour", "colours", "rainbow", "paint", "colores", "arcoiris"]),
        Theme(emoji: "💃", cues: ["dance", "dancing", "dancer", "bailar", "baila", "bailando"]),
        Theme(emoji: "🎉", cues: ["party", "celebrate", "celebration", "fiesta", "celebrar"]),
        Theme(emoji: "🎶", cues: ["music", "song", "sing", "singing", "rhythm", "melody", "beat", "sound", "musica", "cancion", "ritmo"]),
        Theme(emoji: "💭", cues: ["dream", "dreaming", "dreams", "remember", "memories", "memory", "sueno", "suenos", "recuerdos"]),
        Theme(emoji: "🦋", cues: ["butterfly", "butterflies", "mariposa", "mariposas"]),
        Theme(emoji: "🌹", cues: ["rose", "roses", "flower", "flowers", "bloom", "rosas", "flores"]),
        Theme(emoji: "🚗", cues: ["drive", "driving", "road", "highway", "car", "cars", "carretera", "coche"]),
        Theme(emoji: "🪽", cues: ["wings", "flying", "fly", "angel", "angels", "alas", "volar"]),
        Theme(emoji: "🏠", cues: ["home", "house", "room", "hogar", "casa"]),
        Theme(emoji: "🚪", cues: ["door", "doors", "puerta"]),
        Theme(emoji: "🌍", cues: ["world", "earth", "mundo", "tierra"]),
        Theme(emoji: "⏳", cues: ["time", "moment", "moments", "forever", "waiting", "tiempo", "siempre"]),
        Theme(emoji: "💪", cues: ["strong", "stronger", "strength", "fight", "fighter", "fuerte", "fuerza"]),
        Theme(emoji: "❄️", cues: ["snow", "winter", "ice", "cold", "nieve", "invierno", "frio"])
    ]

    /// Blank interludes remain undecorated. Unknown text gets a neutral music accent.
    public static func resolve(line: String, title: String = "", artist: String = "") -> String? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return match(line) ?? match(title) ?? match(artist) ?? "🎵"
    }

    private static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static let indexedThemes: [(String, [(String, Int)])] = themes.map { theme in
        (theme.emoji, theme.cues.map { cue in
            let text = normalized(cue)
            return (" " + text + " ", text.split(separator: " ").count)
        })
    }

    private static func match(_ text: String) -> String? {
        let text = " " + normalized(text) + " "
        var result: String?
        var bestScore = 0
        for (emoji, cues) in indexedThemes {
            let score = cues.filter { text.contains($0.0) }.map(\.1).max() ?? 0
            if score > bestScore { bestScore = score; result = emoji }
        }
        return result
    }
}
