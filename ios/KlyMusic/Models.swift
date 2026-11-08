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

struct LyricsResponse: Codable {
    var plain: String?
    var synced: String?
    var instrumental: Bool
    var lines: [LyricLine] { LyricLine.parse(synced ?? "") }
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
