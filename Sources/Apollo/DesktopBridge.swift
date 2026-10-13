import AppKit
import ApolloCore

enum MusicSource: String, CaseIterable, Identifiable {
    case demo = "Demo", apple = "Apple Music", spotify = "Spotify"
    var id: String { rawValue }
    var bundleID: String { self == .apple ? "com.apple.Music" : "com.spotify.client" }
    var symbol: String { self == .demo ? "sparkles" : self == .apple ? "music.note" : "dot.radiowaves.left.and.right" }
}

struct TrackSnapshot {
    let id: String
    let title: String
    let artist: String
    let album: String
    let artworkURL: String
    let clock: PlaybackClock
}

enum BridgeError: LocalizedError {
    case scripting(String)
    case automationDenied
    var errorDescription: String? {
        switch self {
        case .scripting(let message): return message
        case .automationDenied: return "Allow Music under Apollo in System Settings → Privacy & Security → Automation, then try again."
        }
    }
}

/// Serializes Apple Events off the UI thread. Scripts contain only fixed commands and numeric positions.
actor DesktopBridge {
    private func run(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: "with timeout of 5 seconds\n" + source + "\nend timeout") else {
            throw BridgeError.scripting("Could not prepare the music connection.")
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                throw BridgeError.automationDenied
            }
            throw BridgeError.scripting(error[NSAppleScript.errorMessage] as? String ?? "Music connection failed (\(code)).")
        }
        return result
    }

    func snapshot(_ source: MusicSource) throws -> TrackSnapshot? {
        let id = source == .apple ? "persistent ID" : "id"
        let artwork = source == .spotify ? "artwork url of t" : "\"\""
        let divisor = source == .spotify ? " / 1000" : ""
        let result = try run("""
        tell application id "\(source.bundleID)"
            if player state is stopped then return {}
            set t to current track
            return {\(id) of t, name of t, artist of t, album of t, duration of t\(divisor), player position, (player state is playing), \(artwork)}
        end tell
        """)
        guard result.numberOfItems == 8 else { return nil }
        func string(_ i: Int) -> String { result.atIndex(i)?.stringValue ?? "" }
        return TrackSnapshot(id: source.rawValue + ":" + string(1), title: string(2), artist: string(3), album: string(4), artworkURL: string(8),
            clock: PlaybackClock(position: result.atIndex(6)?.doubleValue ?? 0, duration: result.atIndex(5)?.doubleValue ?? 0, playing: result.atIndex(7)?.booleanValue ?? false))
    }

    func artwork() throws -> Data? {
        let result = try run("""
        tell application id "com.apple.Music"
            if (count of artworks of current track) is 0 then return ""
            return raw data of artwork 1 of current track
        end tell
        """)
        return result.data.isEmpty ? nil : result.data
    }

    enum Command { case toggle, next, previous, seek(Double) }
    func command(_ command: Command, source: MusicSource) throws {
        let statement: String
        switch command {
        case .toggle: statement = "playpause"
        case .next: statement = "next track"
        case .previous: statement = "previous track"
        case .seek(let position):
            guard position.isFinite else { return }
            statement = "set player position to \(max(0, position))"
        }
        _ = try run("tell application id \"\(source.bundleID)\"\n\(statement)\nend tell")
    }
}
