import Foundation

public struct LyricQuery: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double
    public init(title: String, artist: String, album: String, duration: Double) {
        self.title = title; self.artist = artist; self.album = album; self.duration = duration
    }
    public func request(search: Bool = false) -> URLRequest {
        var url = URLComponents(string: "https://lrclib.net/api/\(search ? "search" : "get")")!
        url.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if !search {
            url.queryItems?.append(URLQueryItem(name: "album_name", value: album))
            if duration.isFinite && (1...3600).contains(duration) {
                url.queryItems?.append(URLQueryItem(name: "duration", value: String(duration)))
            }
        }
        var request = URLRequest(url: url.url!); request.timeoutInterval = 30
        request.setValue("Apollo v0.3.1 (https://github.com/jkw16/Apollo)", forHTTPHeaderField: "User-Agent")
        return request
    }
}

public struct AutomaticLyrics: Codable, Sendable {
    public let id: Int
    public let trackName: String
    public let artistName: String
    public let albumName: String
    public let duration: Double
    public let instrumental: Bool
    public let plainLyrics: String?
    public let syncedLyrics: String?

    public func matches(_ query: LyricQuery) -> Bool {
        func normalized(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        return normalized(trackName) == normalized(query.title)
            && normalized(artistName) == normalized(query.artist)
            && query.duration.isFinite && query.duration > 0 && abs(duration - query.duration) <= 2
    }
}

public enum LyricLookupError: LocalizedError {
    case unavailable, busy, timedOut, offline
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Couldn’t load lyrics. Check your connection and try again."
        case .timedOut: return "The lyrics service took too long to respond. Try lyrics again in a moment."
        case .offline: return "You appear to be offline. Reconnect, then try lyrics again."
        case .busy: return "The lyrics service is busy. Please try again later."
        }
    }
}

/// Only one request at a time; cancellation and backoff also apply across song changes.
public actor AutomaticLyricClient {
    private let session: URLSession
    private var busy = false
    private var nextRequest = Date.distantPast
    public init(session: URLSession = .shared) { self.session = session }

    public func lookup(_ query: LyricQuery) async throws -> AutomaticLyrics? {
        guard !query.title.isEmpty, !query.artist.isEmpty, query.duration > 0 else { return nil }
        let data = try await fetch(query.request())
        if let data {
            let record = try JSONDecoder().decode(AutomaticLyrics.self, from: data)
            if record.matches(query) { return record }
        }
        // Album editions can differ. Never relax title, artist or duration matching.
        guard let data = try await fetch(query.request(search: true)) else { return nil }
        return try JSONDecoder().decode([AutomaticLyrics].self, from: data)
            .filter { $0.matches(query) }
            .sorted { (LRC.parse($0.syncedLyrics ?? "").isEmpty ? 1 : 0) < (LRC.parse($1.syncedLyrics ?? "").isEmpty ? 1 : 0) }.first
    }

    private func requestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        for attempt in 0...1 {
            try Task.checkCancellation()
            do { return try await session.data(for: request) }
            catch let error as URLError {
                try Task.checkCancellation()
                let transient = error.code == .timedOut || error.code == .networkConnectionLost
                if transient && attempt == 0 {
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                if error.code == .timedOut { throw LyricLookupError.timedOut }
                if error.code == .notConnectedToInternet { throw LyricLookupError.offline }
                throw error
            }
        }
        throw LyricLookupError.unavailable
    }

    private func fetch(_ request: URLRequest) async throws -> Data? {
        while busy { try await Task.sleep(for: .milliseconds(100)) }
        try Task.checkCancellation()
        busy = true
        defer { busy = false }
        let delay = nextRequest.timeIntervalSinceNow
        if delay > 1 { throw LyricLookupError.busy }
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        let (data, response) = try await requestWithRetry(request)
        nextRequest = Date().addingTimeInterval(0.3)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw LyricLookupError.unavailable }
        if response.statusCode == 429 || response.statusCode == 503 {
            let header = response.value(forHTTPHeaderField: "Retry-After") ?? "60"
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            let delay = Double(header) ?? formatter.date(from: header)?.timeIntervalSinceNow ?? 60
            nextRequest = Date().addingTimeInterval(max(1, delay))
            throw LyricLookupError.busy
        }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200, data.count < 2_000_000 else { throw LyricLookupError.unavailable }
        return data
    }
}
