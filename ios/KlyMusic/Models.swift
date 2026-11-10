import Foundation
import SwiftData

struct Track: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var artist: String
    var album: String = ""
    var duration: Double = 0
    var artwork: String?
    var artistID: String?
    var albumID: String?
    var explicit: Bool = false
    var source: String = "apple"

    var artworkURL: URL? { artwork.flatMap(URL.init(string:)) }
    var durationLabel: String { Self.time(duration) }
    static func time(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? max(0, Int(seconds)) : 0
        return String(format: "%d:%02d", safe / 60, safe % 60)
    }
}

struct MusicCollection: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var artwork: String?
    var kind: String = "album"
    var releaseDate: String? = nil
    var releaseLabel: String {
        guard let releaseDate, let date = ISO8601DateFormatter().date(from: releaseDate) else { return "Öne Çıkan" }
        return date > Date() ? "Yakında" : "Son Çıkan"
    }
}

struct MusicArtist: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var artwork: String?
    var banner: String?
}

struct BrowseCategory: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var query: String
    var artwork: String?
}

/// Keep a song's catalogue reissues from occupying several shelves on one page.
enum HomeFeed {
    static func interleaved(_ sections: [HomeSection]) -> [Track] {
        (0..<(sections.map { $0.tracks.count }.max() ?? 0)).flatMap { index in
            sections.compactMap { index < $0.tracks.count ? $0.tracks[index] : nil }
        }
    }
    static func identity(_ track: Track) -> String { NativeCatalog.normalized(track.artist) + "|" + NativeCatalog.canonical(track.title) }
    static func distinct(_ sections: [HomeSection], excluding tracks: [Track] = []) -> [HomeSection] {
        var seen = Set(tracks.map(identity))
        return sections.compactMap { section in
            let unique = section.tracks.filter { seen.insert(identity($0)).inserted }
            return unique.isEmpty ? nil : HomeSection(id: section.id, title: section.title, subtitle: section.subtitle, tracks: unique)
        }
    }
}

struct HomeSection: Codable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var tracks: [Track]
}

struct HomeResponse: Codable { var sections: [HomeSection] }
struct SearchResponse: Codable {
    var tracks: [Track] = []
    var albums: [MusicCollection] = []
    var artists: [MusicArtist] = []
    var warnings: [String] = []
}
struct AlbumResponse: Codable { var tracks: [Track] }
struct ArtistResponse: Codable {
    var artist: MusicArtist
    var tracks: [Track]
    var albums: [MusicCollection]
    var featured: MusicCollection? = nil
}
struct PlaybackAsset: Codable, Sendable {
    var id: String
    var path: String
    var provider: String
    var codec: String
    var bitrate: Int
    var expiresAt: Double
    var duration: Double
}

struct LyricsResponse: Codable, Sendable {
    var plain: String?
    var synced: String?
    var instrumental: Bool
    var lines: [LyricLine] { LyricLine.parse(synced ?? "") }
    var hasContent: Bool {
        instrumental || !(plain ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !lines.isEmpty
    }
}

struct LyricLine: Identifiable, Equatable {
    var id: Int
    var time: Double
    var text: String

    static func parse(_ lrc: String) -> [LyricLine] {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+):(\d{2})(?:\.(\d{1,3}))?\]"#) else { return [] }
        var lines: [(Double, String)] = []
        for row in lrc.components(separatedBy: .newlines) {
            let ns = row as NSString
            let matches = regex.matches(in: row, range: NSRange(location: 0, length: ns.length))
            guard let end = matches.last?.range.upperBound else { continue }
            let text = ns.substring(from: end).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for match in matches {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
                let fractionRange = match.range(at: 3)
                let fractionText = fractionRange.location != NSNotFound ? ns.substring(with: fractionRange) : "0"
                let fraction = (Double(fractionText) ?? 0) / pow(10, Double(fractionText.count))
                lines.append((minutes * 60 + seconds + fraction, text))
            }
        }
        return lines.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}

/// Recording identity is independent of catalogue/provider IDs and duration validation.
/// Only complete titles and complete credited-name sets match; this is not fuzzy search.
enum RecordingIdentity {
    private struct Key {
        let raw: String
        let folded: String
        let latin: String
        let cyrillic: Bool
        let nonLatin: Bool
        init(_ value: String) {
            raw = value
            folded = RecordingIdentity.fold(value)
            cyrillic = RecordingIdentity.contains(value, #"\p{Cyrillic}"#)
            nonLatin = RecordingIdentity.contains(value, #"[\p{L}&&[^\p{Latin}]]"#)
            let source = cyrillic ? RecordingIdentity.cyrillicLatin(value) : value
            latin = nonLatin ? RecordingIdentity.fold(source.applyingTransform(.toLatin, reverse: false) ?? source) : folded
        }
    }
    private struct Credits {
        var names: [Key]
        var ambiguous = false
        var explicit = false
    }
    private struct Description {
        let titles: [Key]
        let displayTitles: [String]
        let credits: [Credits]
        let video: Bool
        let cyrillicContext: Bool
    }

    static func same(_ requested: Track, _ candidate: Track) -> Bool {
        let first = describe(requested), second = describe(candidate)
        for a in first {
            for b in second where a.titles.contains(where: { left in b.titles.contains { equivalent(left, $0, artist: false) } }) {
                let romanizedContext = a.cyrillicContext || b.cyrillicContext
                for left in a.credits where !left.names.isEmpty {
                    for right in b.credits where !right.names.isEmpty {
                        // 'and' and 'x' are ambiguous in band names. A second, explicit
                        // credit representation must corroborate a split interpretation.
                        guard (!left.ambiguous && !right.ambiguous) || left.explicit || right.explicit else { continue }
                        if equalCredits(left.names, right.names, romanizedContext: romanizedContext) { return true }
                        // A producer-only catalogue entry can match an explicitly credited
                        // video, but an uploader must already have proved membership.
                        if b.video, left.names.count == 1, !right.ambiguous,
                           subset(left.names, right.names, romanizedContext: romanizedContext) { return true }
                    }
                }
            }
        }
        return false
    }

    static func lookupTitles(_ track: Track) -> [String] {
        var seen = Set<String>()
        return ([track.title] + describe(track).flatMap(\.displayTitles)).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0).inserted
        }
    }

    static func queries(_ track: Track) -> [String] {
        let descriptions = describe(track)
        let titles = descriptions.flatMap(\.displayTitles)
        var seen = Set<String>()
        var result = [String]()
        // Clean title/credit queries first, then an exact title-only fallback. Every
        // returned row still has to satisfy same() and the caller's duration check.
        for title in titles {
            for description in descriptions {
                if let names = description.credits.first(where: { $0.explicit && !$0.ambiguous })?.names ?? description.credits.first?.names {
                    result.append(names.map(\.raw).joined(separator: " & ") + " " + fold(title))
                }
            }
            result.append(fold(title))
        }
        result.append(track.artist + " " + fold(track.title))
        return result.filter { !fold($0).isEmpty && seen.insert(fold($0)).inserted }.prefix(6).map { $0 }
    }

    private static func describe(_ track: Track) -> [Description] {
        let cleaned = cleanTitle(track.title)
        let normal = makeDescription(title: cleaned.title, artists: artistCredits(track.artist), features: cleaned.features, video: false)
        var result = [normal]
        guard track.source == "youtube" || track.id.hasPrefix("youtube:"),
              let delimiter = track.title.range(of: #"\s+[-–—]\s+"#, options: .regularExpression) else { return result }
        let prefix = String(track.title[..<delimiter.lowerBound])
        let suffix = cleanTitle(String(track.title[delimiter.upperBound...]))
        let uploaders = artistCredits(track.artist)
        let credits = artistCredits(prefix).filter { credit in
            uploaders.contains { uploader in
                // Do not invent a partial uploader match by splitting an ambiguous
                // band name. A whole uploader or explicit credit set must be present.
                (!uploader.ambiguous || credit.explicit) && subset(uploader.names, credit.names, romanizedContext: contains(track.title, #"\p{Cyrillic}"#))
            }
        }
        if !credits.isEmpty {
            result.insert(makeDescription(title: suffix.title, artists: credits, features: suffix.features, video: true), at: 0)
        }
        return result
    }

    private static func makeDescription(title: String, artists: [Credits], features: [String], video: Bool) -> Description {
        let variants = bilingualTitles(title)
        var credits = artists
        for feature in features {
            let additions = artistCredits(feature).filter { !$0.ambiguous }
            credits = credits.flatMap { original in
                additions.map { extra in
                    var copy = original
                    for name in extra.names where !copy.names.contains(where: { equivalent($0, name, artist: true) }) { copy.names.append(name) }
                    copy.explicit = copy.explicit || extra.explicit || copy.names.count > original.names.count
                    return copy
                }
            }
        }
        return Description(titles: variants.map(Key.init), displayTitles: variants, credits: credits,
                           video: video, cyrillicContext: contains(title, #"\p{Cyrillic}"#))
    }

    private static func cleanTitle(_ value: String) -> (title: String, features: [String]) {
        var text = stripPresentation(value)
        var features = [String]()
        let patterns = [#"[\(\[]\s*(?:feat(?:uring)?|ft)\.?\s+([^\)\]]+)[\)\]]"#,
                        #"\s+(?:feat(?:uring)?|ft)\.?\s+([^\(\)\[\]]+)"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let source = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            for match in matches {
                features.append(source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) { text.replaceSubrange(range, with: " ") }
            }
        }
        text = stripPresentation(text).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—")))
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return (text, features)
    }

    private static func stripPresentation(_ value: String) -> String {
        // Catalogue soundtrack attribution is release context, not a recording
        // version. Only a bounded, balanced From clause is removed; Remix/Live
        // brackets before or after it remain part of the complete title.
        var text = value.replacingOccurrences(of: #"[\(\[]\s*from\s+[^\(\)\[\]\r\n]{1,200}[\)\]]"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let labels: Set<String> = ["official", "audio", "music", "video", "lyric", "lyrics", "visualizer", "visualiser", "hd", "hq", "4k", "1080p", "2160p"]
        for _ in 0..<8 {
            if let range = text.range(of: #"\s*[\(\[【][^\)\]】]+[\)\]】]\s*$"#, options: .regularExpression) {
                let label = fold(String(text[range])).split(separator: " ").map(String.init)
                let originalVersion = label == ["original", "version"] || label == ["orijinal", "versiyon"]
                if originalVersion || (!label.isEmpty && label.allSatisfy({ labels.contains($0) }) && label != ["music"]) {
                    text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    continue
                }
            }
            let suffix = #"\s+(?:[-–—]\s*)?(?:official(?:\s+music)?(?:\s+(?:audio|video|lyrics?|lyric\s+video))?|lyrics?(?:\s+video)?|visuali[sz]er|original\s+version|orijinal\s+versiyon)(?:\s+(?:4k|hd|hq|1080p|2160p))*\s*$"#
            guard let range = text.range(of: suffix, options: [.regularExpression, .caseInsensitive]) else { break }
            text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func bilingualTitles(_ value: String) -> [String] {
        guard let range = value.range(of: #"\s*[\(\[][^\)\]]+[\)\]]\s*$"#, options: .regularExpression) else { return [value] }
        let base = String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = String(value[range]).trimmingCharacters(in: CharacterSet(charactersIn: " ()[]\n\t"))
        let first = Key(base), second = Key(alias)
        guard !first.folded.isEmpty, first.nonLatin != second.nonLatin,
              equivalent(first, second, artist: false) else { return [value] }
        return [base, alias]
    }

    private static func artistCredits(_ value: String) -> [Credits] {
        var name = value.replacingOccurrences(of: "&amp;", with: "&")
        name = name.replacingOccurrences(of: #"(?:\s*[-–—]\s*|\s+)(?:topic|vevo|official)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fold(name).isEmpty else { return [] }
        var result = [Credits(names: [Key(name)])]
        let explicit = name.replacingOccurrences(of: #"\s*(?:,|&|\bfeat(?:uring)?\b\.?|\bft\b\.?)\s*"#, with: "|", options: [.regularExpression, .caseInsensitive])
        let names = explicit.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !fold($0).isEmpty }
        if names.count > 1 { result.append(Credits(names: unique(names.map(Key.init)), explicit: true)) }
        // Weak separators are never treated as enough evidence on their own.
        let weak = explicit.replacingOccurrences(of: #"\s+(?:x|and)\s+"#, with: "|", options: [.regularExpression, .caseInsensitive])
        let weakNames = weak.split(separator: "|").map(String.init).filter { !fold($0).isEmpty }
        if weakNames.count > names.count { result.append(Credits(names: unique(weakNames.map(Key.init)), ambiguous: true)) }
        return result
    }

    private static func unique(_ names: [Key]) -> [Key] {
        var seen = Set<String>()
        return names.filter { seen.insert($0.folded).inserted }
    }
    private static func equalCredits(_ lhs: [Key], _ rhs: [Key], romanizedContext: Bool) -> Bool {
        lhs.count == rhs.count && subset(lhs, rhs, romanizedContext: romanizedContext)
    }
    private static func subset(_ lhs: [Key], _ rhs: [Key], romanizedContext: Bool) -> Bool {
        var remaining = rhs
        for name in lhs {
            guard let index = remaining.firstIndex(where: { equivalent(name, $0, artist: true, romanizedContext: romanizedContext) }) else { return false }
            remaining.remove(at: index)
        }
        return !lhs.isEmpty
    }
    private static func equivalent(_ lhs: Key, _ rhs: Key, artist: Bool, romanizedContext: Bool = false) -> Bool {
        guard !lhs.folded.isEmpty, !rhs.folded.isEmpty else { return false }
        if lhs.folded == rhs.folded { return true }
        // Cross-script equivalence compares the entire transliteration, never a
        // title substring, edit-distance threshold or a partly matching artist.
        if lhs.nonLatin != rhs.nonLatin, lhs.latin == rhs.latin { return true }
        if lhs.cyrillic || rhs.cyrillic || (artist && romanizedContext) {
            var a = romanization(lhs.latin), b = romanization(rhs.latin)
            if artist, lhs.cyrillic != rhs.cyrillic {
                // Cyrillic final и is often conventionally written y in stage names.
                if a.hasSuffix("y") { a = String(a.dropLast()) + "i" }
                if b.hasSuffix("y") { b = String(b.dropLast()) + "i" }
            }
            return a == b
        }
        return false
    }
    private static func romanization(_ value: String) -> String {
        value.replacingOccurrences(of: "iya", with: "ya").replacingOccurrences(of: "ia", with: "ya")
    }
    private static func fold(_ value: String) -> String {
        value.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "ə", with: "e").replacingOccurrences(of: "Ə", with: "E")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }
    private static func contains(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    private static func cyrillicLatin(_ value: String) -> String {
        // Standard letter transliteration is shared by every recording/artist.
        let map: [Character: String] = ["а":"a", "б":"b", "в":"v", "г":"g", "д":"d", "е":"e", "ё":"yo", "ж":"zh", "з":"z", "и":"i", "й":"y", "к":"k", "л":"l", "м":"m", "н":"n", "о":"o", "п":"p", "р":"r", "с":"s", "т":"t", "у":"u", "ф":"f", "х":"kh", "ц":"ts", "ч":"ch", "ш":"sh", "щ":"shch", "ъ":"", "ы":"y", "ь":"", "э":"e", "ю":"yu", "я":"ya", "ґ":"g", "є":"ye", "і":"i", "ї":"yi"]
        return value.lowercased().map { map[$0] ?? String($0) }.joined()
    }
}

@Model final class SavedTrack {
    @Attribute(.unique) var id: String
    var metadata: Data
    var favorite: Bool
    var lastPlayed: Date?
    var playCount: Int
    var downloadFile: String?
    init(_ track: Track) {
        id = track.id
        metadata = (try? JSONEncoder().encode(track)) ?? Data()
        favorite = false
        playCount = 0
    }
    var track: Track? { try? JSONDecoder().decode(Track.self, from: metadata) }
}

@Model final class SavedPlaylist {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var trackIDs: [String]
    init(name: String, trackIDs: [String] = []) {
        id = UUID(); self.name = name; createdAt = .now; self.trackIDs = trackIDs
    }
}

struct LibraryBackup: Codable {
    var version = 1
    var tracks: [BackupTrack]
    var playlists: [BackupPlaylist]
    var settings: [String: String]
    struct BackupTrack: Codable { var track: Track; var favorite: Bool; var lastPlayed: Date?; var playCount: Int; var addedAt: Date? = nil }
    struct BackupPlaylist: Codable { var id: UUID; var name: String; var trackIDs: [String]; var createdAt: Date? = nil }
}
