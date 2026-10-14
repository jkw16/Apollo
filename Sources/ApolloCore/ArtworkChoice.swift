// Artwork matching against the iTunes Search catalog: normalization,
// scoring, and the acceptance rule (artist must agree, title must overlap —
// a title-only match shows the wrong cover; an artist-only match resolves a
// DJ mix to an unrelated single's artwork).
import Foundation

public struct ItunesAlbum: Codable, Equatable {
    public var artistName: String?
    public var collectionName: String?
    public var artworkUrl100: String?
    public var artistId: Int?
    public init(artistName: String, collectionName: String, artworkUrl100: String) {
        self.artistName = artistName
        self.collectionName = collectionName
        self.artworkUrl100 = artworkUrl100
    }
}

/// Diacritic-insensitive, case-insensitive, punctuation-light comparison key.
public func wallNormalized(_ input: String) -> String {
    var folded = input.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    // Drop parenthetical qualifiers: (deluxe) [feat. …] (bonus track) …
    folded = folded.replacingOccurrences(of: #"\(.*?\)"#, with: " ", options: .regularExpression)
    folded = folded.replacingOccurrences(of: #"\[.*?\]"#, with: " ", options: .regularExpression)
    let keep = CharacterSet.letters.union(.decimalDigits)
    let cleaned = String(String.UnicodeScalarView(folded.unicodeScalars.filter { keep.contains($0) || $0 == " " }))
    return cleaned.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).joined(separator: " ")
}

public enum ArtworkChoice {
    /// Pick the best-search-result artwork, or nil when nothing agrees.
    /// Candidates without artwork never win, so bare artist rows in a
    /// lookup response are skipped automatically.
    public static func chooseArtwork(results: [ItunesAlbum], artist: String, title: String) -> ItunesAlbum? {
        let wantArtist = wallNormalized(artist)
        let wantWords = Set(wallNormalized(title).split(separator: " "))
        var best: ItunesAlbum?
        var bestScore = 0.0
        for result in results {
            guard let haveArtwork = result.artworkUrl100, !haveArtwork.isEmpty,
                  let albumName = result.collectionName else { continue }
            let haveArtist = wallNormalized(result.artistName ?? "")
            let haveTitle = wallNormalized(albumName)
            var score = 0.0
            if haveArtist == wantArtist { score += 0.5 }
            else if haveArtist.contains(wantArtist) || wantArtist.contains(haveArtist) { score += 0.3 }
            let haveWords = Set(haveTitle.split(separator: " "))
            score += Double(wantWords.intersection(haveWords).count) / Double(max(1, wantWords.count))
            if abs(title.count - albumName.count) > 12 { score -= 0.1 }
            if score > bestScore { best = result; bestScore = score }
        }
        guard let winner = best else { return nil }
        let haveArtist = wallNormalized(winner.artistName ?? "")
        let artistAgrees = haveArtist == wantArtist
            || haveArtist.contains(wantArtist) || wantArtist.contains(haveArtist)
        let titleOverlaps = !Set(wallNormalized(winner.collectionName ?? "").split(separator: " "))
            .isDisjoint(with: wantWords)
        return artistAgrees && titleOverlaps ? winner : nil
    }

    /// Swap an artworkUrl100's size suffix for a larger square.
    public static func scaled(_ url100: String, size: Int) -> String? {
        guard let range = url100.range(of: #"\d+x\d+bb\.(jpg|png)$"#, options: .regularExpression) else { return nil }
        return url100.replacingCharacters(in: range, with: "\(size)x\(size)bb.jpg")
    }
}