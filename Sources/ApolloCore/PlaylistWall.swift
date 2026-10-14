import Foundation

public struct WallAlbum: Equatable, Sendable {
    public let artist: String
    public let title: String
    public let artworkURL: URL?
    public let trackID: String?
    public var key: String { Self.key(artist: artist, title: title) }
    public init(artist: String, title: String, artworkURL: URL? = nil, trackID: String? = nil) {
        self.artist = artist; self.title = title; self.artworkURL = artworkURL; self.trackID = trackID
    }
    public static func key(artist: String, title: String) -> String {
        func normalize(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalize(artist) + "\u{1F}" + normalize(title)
    }
}

public struct WallSnapshot: Sendable {
    public let id: String
    public let name: String
    public let albums: [WallAlbum]
    public let limited: Bool
    public init(id: String, name: String, albums: [WallAlbum], limited: Bool = false) {
        self.id = id; self.name = name; self.albums = albums; self.limited = limited
    }
}

public enum WallBudget {
    public static let albums = 120
    public static let tracks = 1000
    public static let downloadsPerPass = 8
    public static let interval: TimeInterval = 30
    public static func unique(_ albums: [WallAlbum]) -> [WallAlbum] {
        var seen = Set<String>()
        return Array(albums.filter { !$0.title.isEmpty && seen.insert($0.key).inserted }.prefix(self.albums))
    }
    public static func select(_ covers: [CoverRecord], keys: Set<String>) -> [CoverRecord] {
        var seen = Set<String>()
        return Array(covers.filter {
            keys.contains(WallAlbum.key(artist: $0.artist, title: $0.title)) && seen.insert($0.file).inserted
        }.prefix(albums))
    }
}
