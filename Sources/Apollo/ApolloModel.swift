import AppKit
import AVKit
import ApolloCore
import UniformTypeIdentifiers
import SwiftUI

struct TrackAssets: Codable {
    var lrc: String?
    var automaticLyrics: AutomaticLyrics?
    var movie: String?
    var offset: Double = 0
}

@MainActor final class ApolloModel: ObservableObject {
    @Published var source: MusicSource = .demo
    @Published var title = "A little closer to the music."
    @Published var artist = "Apollo · Original visual demo"
    @Published var album = "Welcome aboard"
    @Published var trackID = "demo"
    @Published var clock = PlaybackClock(position: 0, duration: 60, playing: true)
    @Published var artwork: NSImage? { didSet { updateLyricArtworkColor() } }
    @Published var lyricArtworkColor = apolloOrange
    @Published var lyricAppearance = LyricAppearance.load() { didSet { lyricAppearance.save() } }
    @Published var showLyricOptions = false
    @Published var lyrics = LRC.parse(demoLyrics)
    @Published var plainLyrics = ""
    @Published var lyricStatus = "Original demo lyrics"
    @Published var loadingLyrics = false
    @Published var automaticLyricsEnabled = UserDefaults.standard.object(forKey: "automaticLyrics") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(automaticLyricsEnabled, forKey: "automaticLyrics")
            if source != .demo { loadLyrics() }
        }
    }
    private let lyricClient = AutomaticLyricClient()
    private var lyricTask: Task<Void, Never>?
    private var lyricRequest = UUID()
    @Published var status = "Demo · no audio"
    @Published var error: String?
    @Published var connected = false
    @Published var isConnecting = false
    @Published var showMusicSetup = false
    @Published var automationDenied = false
    @Published var showLyrics = true
    @Published var showSettings = false
    @Published var ringEnabled = false
    @Published var ringAllDisplays = UserDefaults.standard.object(forKey: "ringAllDisplays") as? Bool ?? true {
        didSet { UserDefaults.standard.set(ringAllDisplays, forKey: "ringAllDisplays") }
    }
    @Published var ringDisplayIDs = Set(UserDefaults.standard.stringArray(forKey: "ringDisplayIDs") ?? []) {
        didSet { UserDefaults.standard.set(Array(ringDisplayIDs), forKey: "ringDisplayIDs") }
    }
    @Published var intensity = 0.75
    @Published var moviePlayer: AVPlayer?
    @Published var videoID: String?
    @Published var videoInput = ""
    @Published var lyricOffset: Double = 0
    @Published var ambientScene: AmbientScene = ((UserDefaults.standard.object(forKey: "ambientScene") as? String)
        .flatMap(AmbientScene.init(rawValue:))) ?? .aurora {
        didSet { UserDefaults.standard.set(ambientScene.rawValue, forKey: "ambientScene"); resetCoverSync() }
    }
    @Published var autoSyncCovers = UserDefaults.standard.object(forKey: "autoSyncCovers") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoSyncCovers, forKey: "autoSyncCovers"); resetCoverSync() }
    }
    @Published var coverCatalog = CoverManifest()
    @Published var coverStatus: String?
    @Published var syncInFlight = false
    @Published var activeCoverKeys = Set<String>()
    let spotifyConnection = SpotifyConnection()
    let spotifyPlaylists = SpotifyPlaylistClient()
    let coverBridge = DesktopBridge()
    lazy var coverStore = CoverStore(directory: directory)
    var coverSyncTask: Task<Void, Never>?
    var coverGeneration = UUID()
    var nextCoverSync = Date.distantPast
    var coverFailures: [String: Date] = [:]
    private var playlistContext = ""
    var wallCovers: [CoverRecord] { WallBudget.select(coverCatalog.covers, keys: activeCoverKeys) }
    let bridge = DesktopBridge()
    private var pollTask: Task<Void, Never>?
    private var movieObserver: NSObjectProtocol?
    private var assets: [String: TrackAssets] = [:]
    private let directory: URL
    var supportDirectory: URL { directory }
    var coverDirectory: URL { directory.appendingPathComponent("covers") }
    /// Toggling the sidebar "Motion artwork" action: the wall of sound is
    /// shown as the background (imported video still wins), lyrics unchanged.
    func toggleWall() {
        ambientScene = ambientScene == .wallOfSound ? .aurora : .wallOfSound
        requestCoverSync()
    }

    private var generation = UUID()

    static let demoLyrics = """
    [00:00.00]Let the room fall away
    [00:06.00]Find a little space to feel
    [00:12.00]Every color has a rhythm
    [00:18.00]Every moment turns a wheel
    [00:24.00]We are closer to the music
    [00:30.00]Than we ever were before
    [00:36.00]Let the light run round the edges
    [00:42.00]Leave the world outside the door
    [00:48.00]A whole universe of sound
    [00:54.00]And a little room for you
    """

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Apollo", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: file.path) {
                assets = try JSONDecoder().decode([String: TrackAssets].self, from: Data(contentsOf: file))
            }
            try FileManager.default.createDirectory(at: coverDirectory, withIntermediateDirectories: true)
        } catch { self.error = "Could not load Apollo’s local library: \(error.localizedDescription)" }
        loadCovers()
        startPolling()

    }

    func select(_ next: MusicSource) {
        if source == next {
            if next == .apple { showMusicSetup = true }
            return
        }
        resetCoverSync(); playlistContext = ""
        cancelLyricLookup()
        plainLyrics = ""; lyricStatus = "Play a song to see its lyrics."
        generation = UUID()
        pollTask?.cancel()
        source = next
        connected = false
        isConnecting = false
        automationDenied = false
        showMusicSetup = next == .apple
        artwork = nil
        videoID = nil
        clearMovie()
        error = nil
        lyrics = []
        lyricOffset = 0
        trackID = ""
        title = "Ready when you are"
        artist = "Open \(next.rawValue) and play a song"
        album = ""
        clock = PlaybackClock(position: 0, duration: 0, playing: false)
        if next == .demo {
            trackID = "demo"; title = "A little closer to the music."; artist = "Apollo · Original visual demo"
            album = "Welcome aboard"; lyrics = LRC.parse(Self.demoLyrics); lyricStatus = "Original demo lyrics"
            clock = PlaybackClock(position: 0, duration: 60, playing: true)
            status = "Demo · no audio"
        } else { status = "Click Connect to enable \(next.rawValue)" }
        startPolling()
    }

    func connect() {
        guard source != .demo, !isConnecting else { return }
        let selected = source, token = generation
        error = nil; automationDenied = false; isConnecting = true
        status = "Opening \(selected.rawValue)…"
        Task {
            do {
                try await openPlayer(selected)
                guard token == generation else { return }
                status = "Waiting for \(selected.rawValue) permission…"
                await refresh(token: token)
            } catch {
                guard token == generation else { return }
                isConnecting = false; connected = false
                status = "Could not open \(selected.rawValue)"
                self.error = error.localizedDescription
            }
        }
    }

    private func openPlayer(_ selected: MusicSource) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: selected.bundleID) else {
            throw BridgeError.scripting("\(selected.rawValue) isn’t installed on this Mac. Install the desktop app, then try again.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func openMusic() {
        Task {
            do { try await openPlayer(.apple) }
            catch { self.error = error.localizedDescription }
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            if !NSWorkspace.shared.open(url) {
                error = "Open System Settings → Privacy & Security → Automation and enable Music under Apollo."
            }
        }
    }

    private func startPolling() {
        let token = generation
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isConnecting { await self.refresh(token: token) }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh(token: UUID) async {
        guard token == generation else { return }
        if source == .demo {
            if clock.elapsed(at: Date()) >= 60 { clock = PlaybackClock(position: 0, duration: 60, playing: clock.playing) }
            return
        }
        guard connected || isConnecting else { return }
        let selected = source
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == selected.bundleID }) else {
            resetCoverSync()
            connected = false; isConnecting = false; freeze(); status = "\(selected.rawValue) closed"; return
        }
        do {
            let snapshot = try await bridge.snapshot(selected)
            guard token == generation else { return }
            if isConnecting { error = nil }
            connected = true; isConnecting = false; automationDenied = false
            guard let snapshot else {
                cancelLyricLookup(); plainLyrics = ""; lyricStatus = "Play a song to see its lyrics."
                resetCoverSync()
                freeze(); status = "Connected · Play a song in \(selected.rawValue)"; lyrics = []; artwork = nil; trackID = ""
                title = "Ready when you are"; artist = "Play a song in \(selected.rawValue)"; album = ""
                clearMovie(); return
            }
            let changed = snapshot.id != trackID
            if changed || snapshot.playlistID != playlistContext {
                resetCoverSync()
                playlistContext = snapshot.playlistID
            }
            trackID = snapshot.id; title = snapshot.title; artist = snapshot.artist; album = snapshot.album
            clock = snapshot.clock
            if activeCoverKeys.isEmpty { usePlayingAlbum() }
            requestCoverSync()
            status = snapshot.clock.playing ? "Connected · \(selected.rawValue)" : "Paused · \(selected.rawValue)"
            if changed {
                artwork = nil
                loadAssets()
                if selected == .apple, let data = try? await bridge.artwork(), token == generation, trackID == snapshot.id {
                    artwork = NSImage(data: data)
                    // The wall's catalog grows from what the user actually listens to.
                    captureCover(data, artist: snapshot.artist, album: snapshot.album)
                } else if selected == .spotify, let url = URL(string: snapshot.artworkURL), url.scheme == "https" {
                    var request = URLRequest(url: url); request.timeoutInterval = 8
                    if let (data, response) = try? await URLSession.shared.data(for: request),
                       (response as? HTTPURLResponse)?.statusCode == 200, data.count < 20_000_000,
                       token == generation, trackID == snapshot.id {
                        artwork = NSImage(data: data); captureCover(data, artist: snapshot.artist, album: snapshot.album)
                    }
                }
            }
            guard token == generation else { return }
            if clock.playing { moviePlayer?.play() } else { moviePlayer?.pause() }
        } catch {
            guard token == generation else { return }
            resetCoverSync()
            connected = false; isConnecting = false; freeze(); status = "Connection needs attention"
            if case BridgeError.automationDenied = error { automationDenied = true }
            self.error = automationDenied
                ? "Enable \(selected.rawValue == "Apple Music" ? "Music" : selected.rawValue) under Apollo in System Settings → Privacy & Security → Automation, then try again."
                : error.localizedDescription
        }
    }

    private func freeze() {
        clock = PlaybackClock(position: clock.elapsed(at: Date()), duration: clock.duration, playing: false)
        moviePlayer?.pause()
    }

    func control(_ command: DesktopBridge.Command) {
        if source == .demo {
            let now = clock.elapsed(at: Date())
            switch command {
            case .toggle: clock = PlaybackClock(position: now, duration: 60, playing: !clock.playing)
            case .seek(let time): clock = PlaybackClock(position: min(60, max(0, time)), duration: 60, playing: clock.playing)
            case .next, .previous: clock = PlaybackClock(position: 0, duration: 60, playing: clock.playing)
            }
            if clock.playing { moviePlayer?.play() } else { moviePlayer?.pause() }
            return
        }
        guard connected else { return }
        let selected = source, token = generation
        Task {
            do {
                try await bridge.command(command, source: selected)
                await refresh(token: token)
            } catch { if token == generation { self.error = error.localizedDescription } }
        }
    }

    func importLyrics() {
        guard !trackID.isEmpty else { error = "Connect and play a song first."; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText, .text, UTType(filenameExtension: "lrc") ?? .data]
        panel.message = "Choose a UTF-8 .lrc file for this track."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = LRC.parse(text)
            guard !parsed.isEmpty else { error = "No timed lyrics found. Use lines like [00:12.50]Your lyric."; return }
            cancelLyricLookup(); plainLyrics = ""; lyricStatus = "Imported lyrics"
            assets[trackID, default: TrackAssets()].lrc = text; lyrics = parsed; save()
        } catch { self.error = error.localizedDescription }
    }

    func importMovie() {
        guard !trackID.isEmpty else { error = "Connect and play a song first."; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Choose motion artwork you own or have permission to use. Apollo copies it into its local library."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let name = UUID().uuidString + "." + url.pathExtension
            let destination = directory.appendingPathComponent(name)
            try FileManager.default.copyItem(at: url, to: destination)
            removeStoredMovie()
            assets[trackID, default: TrackAssets()].movie = name; save(); loadMovie(destination)
            videoID = nil
        } catch { self.error = error.localizedDescription }
    }

    func removeMovie() { clearMovie(); removeStoredMovie(); save() }
    private func removeStoredMovie() {
        if let name = assets[trackID]?.movie {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            assets[trackID]?.movie = nil
        }
    }
    func updateOffset(_ value: Double) {
        lyricOffset = value; assets[trackID, default: TrackAssets()].offset = value; save()
    }
    private func loadAssets() {
        let item = assets[trackID]
        loadLyrics(); lyricOffset = item?.offset ?? 0
        clearMovie()
        if let name = item?.movie { loadMovie(directory.appendingPathComponent(name)) }
    }
    private func cancelLyricLookup() {
        lyricRequest = UUID(); lyricTask?.cancel(); lyricTask = nil; loadingLyrics = false
    }

    func retryLyrics() { loadLyrics() }

    private func loadLyrics() {
        cancelLyricLookup(); lyrics = []; plainLyrics = ""
        guard source != .demo, !trackID.isEmpty else { lyricStatus = "Play a song to see its lyrics."; return }
        if let imported = assets[trackID]?.lrc, !LRC.parse(imported).isEmpty {
            lyrics = LRC.parse(imported); lyricStatus = "Imported lyrics"; return
        }
        guard automaticLyricsEnabled else { lyricStatus = "Automatic lyrics are off."; return }
        if let cached = assets[trackID]?.automaticLyrics {
            applyLyrics(cached); return
        }
        loadingLyrics = true; lyricStatus = "Finding lyrics…"
        let id = trackID, token = lyricRequest
        let query = LyricQuery(title: title, artist: artist, album: album, duration: clock.duration)
        lyricTask = Task {
            do {
                let result = try await lyricClient.lookup(query)
                guard token == lyricRequest, id == trackID, !Task.isCancelled else { return }
                loadingLyrics = false
                if let result {
                    assets[id, default: TrackAssets()].automaticLyrics = result
                    applyLyrics(result); save()
                } else { lyricStatus = "No matching lyrics found for this song." }
            } catch {
                guard token == lyricRequest, !Task.isCancelled else { return }
                loadingLyrics = false
                lyricStatus = (error as? LyricLookupError)?.localizedDescription ?? "Couldn’t load lyrics. Check your connection and try again."
            }
        }
    }

    private func applyLyrics(_ record: AutomaticLyrics) {
        lyrics = LRC.parse(record.syncedLyrics ?? "")
        plainLyrics = lyrics.isEmpty ? (record.plainLyrics ?? "") : ""
        lyricStatus = record.instrumental ? "Instrumental · no lyrics" : !lyrics.isEmpty
            ? "Synced lyrics · LRCLIB" : !plainLyrics.isEmpty ? "Lyrics · LRCLIB · timing unavailable" : "No lyrics available for this song."
    }

    private func loadMovie(_ url: URL) {
        clearMovie()
        let player = AVPlayer(url: url); player.isMuted = true
        moviePlayer = player
        movieObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak player] _ in
            player?.seek(to: .zero); player?.play()
        }
        if clock.playing { player.play() }
    }
    private func clearMovie() {
        moviePlayer?.pause(); moviePlayer = nil
        if let observer = movieObserver { NotificationCenter.default.removeObserver(observer); movieObserver = nil }
    }
    private func save() {
        do { try JSONEncoder().encode(assets).write(to: directory.appendingPathComponent("library.json"), options: .atomic) }
        catch { self.error = "Could not save: \(error.localizedDescription)" }
    }
    func loadYouTube() {
        error = nil
        guard let id = YouTubeURL.videoID(from: videoInput) else { error = "Paste a valid YouTube watch, share, Shorts, or embed URL."; return }
        clearMovie(); videoID = id
    }

    private func updateLyricArtworkColor() {
        guard let artwork, let tiff = artwork.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let source = CIImage(bitmapImageRep: bitmap),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: source, kCIInputExtentKey: CIVector(cgRect: source.extent)]),
              let output = filter.outputImage else { lyricArtworkColor = apolloOrange; return }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let sample = NSColor(calibratedRed: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255, alpha: 1)
        // Keep artwork-derived text bright enough for the dark lyric scene.
        lyricArtworkColor = Color(nsColor: NSColor(calibratedHue: sample.hueComponent,
            saturation: min(0.65, sample.saturationComponent), brightness: max(0.8, sample.brightnessComponent), alpha: 1))
    }
}
