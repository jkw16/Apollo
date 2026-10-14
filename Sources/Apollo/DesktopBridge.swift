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
    private func run(_ source: String, seconds: Int = 5) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: "with timeout of \(seconds) seconds\n" + source + "\nend timeout") else {
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

    /// Every album in the Music library, deduplicated, as (artist, album).
    /// Read-only; same Apple Events trust as the current-track snapshot.
    func libraryAlbums() throws -> [(artist: String, album: String)] {
        // Sentinel \x02 keeps parallel arrays aligned: list-to-text coercion
        // drops missing values, and NSAppleScript returns the result before
        // any console scrubbing, so the sentinel survives to parsing.
        let result = try run("""
        tell application id "com.apple.Music"
            set tNames to name of every track of library playlist 1
            set tArtists to artist of every track of library playlist 1
            set tAA to album artist of every track of library playlist 1
            set tAlbums to album of every track of library playlist 1
        end tell
        repeat with lst in {tNames, tArtists, tAA, tAlbums}
            repeat with i from 1 to count of lst
                if item i of lst is missing value then set item i of lst to (character id 2)
            end repeat
        end repeat
        set AppleScript's text item delimiters to (character id 31)
        set sNames to tNames as text
        set sArtists to tArtists as text
        set sAA to tAA as text
        set sAlbums to tAlbums as text
        set AppleScript's text item delimiters to (character id 30)
        return sNames & (character id 30) & sArtists & (character id 30) & sAA & (character id 30) & sAlbums
        """, seconds: 120)
        let raw = result.stringValue ?? ""
        let parts = raw.split(separator: Character("\u{1E}"), omittingEmptySubsequences: false)
        guard parts.count == 4 else { return [] }
        let clean = Array(parts.map {
            $0.split(separator: Character("\u{1F}"), omittingEmptySubsequences: false)
              .map { $0.replacingOccurrences(of: "\u{02}", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
        })
        var seen = Set<String>()
        var albums: [(artist: String, album: String)] = []
        for i in 0..<clean[3].count where !clean[3][i].isEmpty {
            let artist = clean[2].indices.contains(i) && !clean[2][i].isEmpty ? clean[2][i] : (clean[1].indices.contains(i) ? clean[1][i] : "Unknown Artist")
            let key = (artist.lowercased(), clean[3][i].lowercased())
            if seen.insert("\(key.0)~\(key.1)").inserted {
                albums.append((artist, clean[3][i]))
            }
        }
        return albums
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
