// The persisted cover catalog behind the wall of sound, plus the ambient
// scene selection. Images live in Application Support/Apollo/covers/ as
// content-addressed JPEGs; covers.json holds artist/title/file only.
import Foundation

public struct CoverManifest: Codable, Equatable {
    public var version: Int = 1
    public var covers: [CoverRecord] = []
    public init() {}
}

public struct CoverRecord: Codable, Identifiable, Equatable {
    public var artist: String
    public var title: String
    public var file: String
    public var id: String { file }
    public init(artist: String, title: String, file: String) {
        self.artist = artist; self.title = title; self.file = file
    }
}

/// The collector's albums.json shape (artist/title optional, cover300 required).
public struct CollectorAlbum: Codable {
    public let artist: String?
    public let title: String?
    public let cover300: String?
    public init(artist: String?, title: String?, cover300: String?) {
        self.artist = artist; self.title = title; self.cover300 = cover300
    }
}

public enum AmbientScene: String, CaseIterable, Codable, Identifiable {
    case aurora
    case wallOfSound
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .aurora: return "Aurora"
        case .wallOfSound: return "Wall of Sound"
        }
    }
}