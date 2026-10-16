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
    let playlistID: String
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
        let playlist = source == .apple ? "try\nset contextID to persistent ID of current playlist\nend try" : ""
        let divisor = source == .spotify ? " / 1000" : ""
        let result = try run("""
        tell application id "\(source.bundleID)"
            if player state is stopped then return {}
            set t to current track
            set contextID to ""
            \(playlist)
            return {\(id) of t, name of t, artist of t, album of t, duration of t\(divisor), player position, (player state is playing), \(artwork), contextID}
        end tell
        """)
        guard result.numberOfItems == 9 else { return nil }
        func string(_ i: Int) -> String { result.atIndex(i)?.stringValue ?? "" }
        // Sample transport separately, after slow metadata reads. The midpoint
        // estimates when Music/Spotify measured position, rather than dating it
        // after the Apple Event response has already arrived.
        let requestedAt = Date()
        let transport = try run("""
        tell application id "\(source.bundleID)"
            return {player position, (player state is playing), \(id) of current track}
        end tell
        """)
        let receivedAt = Date()
        guard transport.numberOfItems == 3, transport.atIndex(3)?.stringValue == string(1) else { return nil }
        return TrackSnapshot(id: source.rawValue + ":" + string(1), title: string(2), artist: string(3), album: string(4), playlistID: string(9), artworkURL: string(8),
            clock: PlaybackClock.sample(position: transport.atIndex(1)?.doubleValue ?? 0,
                duration: result.atIndex(5)?.doubleValue ?? 0, playing: transport.atIndex(2)?.booleanValue ?? false,
                requestedAt: requestedAt, receivedAt: receivedAt))
    }

    func artwork(expectedID: String) throws -> Data? {
        guard validID(expectedID) else { return nil }
        let result = try run("""
        tell application id "com.apple.Music"
            if persistent ID of current track is not "\(expectedID)" then return ""
            if (count of artworks of current track) is 0 then return ""
            set imageData to raw data of artwork 1 of current track
            if persistent ID of current track is not "\(expectedID)" then return ""
            return imageData
        end tell
        """)
        return result.data.isEmpty ? nil : result.data
    }

    /// Reads only the current playlist, in bounded metadata pages. No library-wide scan.
    func playlistHeader() throws -> (id: String, name: String, count: Int) {
        let result = try run("""
        tell application id "com.apple.Music"
            set p to current playlist
            return {persistent ID of p, name of p, count of tracks of p}
        end tell
        """, seconds: 3)
        guard result.numberOfItems == 3 else { throw BridgeError.scripting("Play a playlist in Music to fill the wall.") }
        return (result.atIndex(1)?.stringValue ?? "", result.atIndex(2)?.stringValue ?? "Playlist", Int(result.atIndex(3)?.int32Value ?? 0))
    }

    func playlistPage(id: String, start: Int, end: Int) throws -> [WallAlbum] {
        guard validID(id), start >= 1, end >= start, end - start < 100 else { return [] }
        let result = try run("""
        tell application id "com.apple.Music"
            set p to current playlist
            if persistent ID of p is not "\(id)" then return {}
            return {persistent ID of tracks \(start) thru \(end) of p, album artist of tracks \(start) thru \(end) of p, artist of tracks \(start) thru \(end) of p, album of tracks \(start) thru \(end) of p}
        end tell
        """, seconds: 3)
        guard result.numberOfItems == 4 else { throw BridgeError.scripting("Playlist changed; retrying shortly.") }
        let titles = result.atIndex(4)
        return (0..<(titles?.numberOfItems ?? 0)).compactMap { index in
            let i = index + 1
            let title = titles?.atIndex(i)?.stringValue ?? ""
            guard !title.isEmpty else { return nil }
            let aa = result.atIndex(2)?.atIndex(i)?.stringValue ?? ""
            return WallAlbum(artist: aa.isEmpty ? result.atIndex(3)?.atIndex(i)?.stringValue ?? "" : aa,
                             title: title, trackID: result.atIndex(1)?.atIndex(i)?.stringValue)
        }
    }

    func playlistArtwork(playlistID: String, trackID: String) throws -> Data? {
        guard validID(playlistID), validID(trackID) else { return nil }
        let result = try run("""
        tell application id "com.apple.Music"
            set p to current playlist
            if persistent ID of p is not "\(playlistID)" then return ""
            set t to first track of p whose persistent ID is "\(trackID)"
            if (count of artworks of t) is 0 then return ""
            return raw data of artwork 1 of t
        end tell
        """, seconds: 2)
        return result.data.isEmpty ? nil : result.data
    }

    private func validID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 32 && value.allSatisfy { $0.isHexDigit }
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
