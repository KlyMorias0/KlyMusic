import Foundation
import SwiftData
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

enum MusicFiles {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("KlyMusic", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    static var downloads: URL {
        var directory = root.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory
    }
    static func filename(_ id: String) -> String { SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func lyrics(_ id: String) -> URL { root.appendingPathComponent(filename(id) + ".lyrics.json") }
}

struct LibraryRecentEntry: Identifiable {
    enum Content { case album(Track), playlist(SavedPlaylist) }
    let content: Content
    let addedAt: Date
    var id: String {
        switch content {
        case .album(let track): "album:" + (track.albumID ?? track.id)
        case .playlist(let list): "playlist:" + list.id.uuidString
        }
    }
    var title: String {
        switch content {
        case .album(let track): track.album.isEmpty ? track.title : track.album
        case .playlist(let list): list.name
        }
    }
    var artist: String {
        switch content {
        case .album(let track): track.artist
        case .playlist: ""
        }
    }
}

@MainActor final class LibraryStore: ObservableObject {
    let context: ModelContext
    @Published var saved: [SavedTrack] = []
    @Published var playlists: [SavedPlaylist] = []
    @Published var error: String?

    private let insertionDefaults: UserDefaults
    private let insertionKey = "savedTrackInsertionOrder-v1"
    private let addedDatesKey = "savedTrackAddedDates-v1"
    private let now: () -> Date
    init(context: ModelContext, insertionDefaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.context = context; self.insertionDefaults = insertionDefaults; self.now = now; refresh()
        // Existing databases have no added-at field. Seed once; replays never reorder it.
        if insertionDefaults.stringArray(forKey: insertionKey) == nil {
            insertionDefaults.set(saved.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }.map(\.id), forKey: insertionKey)
        }
        // Legacy records lack insertion dates. Keep their existing relative order once;
        // later playback never changes the estimated dates or newly recorded dates.
        var dates = addedDates
        let anchor = saved.compactMap(\.lastPlayed).max() ?? .distantPast
        for (index, track) in recentlyAdded.enumerated() where dates[track.id] == nil {
            dates[track.id] = anchor.timeIntervalSince1970 - Double(index) * 0.001
        }
        insertionDefaults.set(dates, forKey: addedDatesKey)
    }
    private var addedDates: [String: Double] { insertionDefaults.dictionary(forKey: addedDatesKey) as? [String: Double] ?? [:] }
    private func addedAt(_ id: String) -> Date { Date(timeIntervalSince1970: addedDates[id] ?? Date.distantPast.timeIntervalSince1970) }
    var recentlyAdded: [Track] {
        let records = Dictionary(saved.compactMap { item in item.track.map { (item.id, $0) } }, uniquingKeysWith: { first, _ in first })
        let order = insertionDefaults.stringArray(forKey: insertionKey) ?? []
        let known = Set(order)
        return order.compactMap { records[$0] } + saved.filter { !known.contains($0.id) }.compactMap(\.track)
    }
    var recentlyAddedCollections: [LibraryRecentEntry] {
        var albums = Set<String>()
        let dates = addedDates
        let tracks = saved.compactMap(\.track).sorted {
            let first = dates[$0.id] ?? Date.distantPast.timeIntervalSince1970
            let second = dates[$1.id] ?? Date.distantPast.timeIntervalSince1970
            return first == second ? $0.id < $1.id : first > second
        }
        let entries = tracks.compactMap { track -> LibraryRecentEntry? in
            guard albums.insert(track.albumID ?? track.id).inserted else { return nil }
            return LibraryRecentEntry(content: .album(track), addedAt: Date(timeIntervalSince1970: dates[track.id] ?? Date.distantPast.timeIntervalSince1970))
        } + playlists.map { LibraryRecentEntry(content: .playlist($0), addedAt: $0.createdAt) }
        return entries.sorted { $0.addedAt == $1.addedAt ? $0.id < $1.id : $0.addedAt > $1.addedAt }
    }
    func refresh() {
        do {
            saved = try context.fetch(FetchDescriptor<SavedTrack>())
            playlists = try context.fetch(FetchDescriptor<SavedPlaylist>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        } catch { self.error = error.localizedDescription }
    }
    func commit() {
        do { try context.save(); refresh() } catch { self.error = error.localizedDescription }
    }
    func record(_ track: Track) -> SavedTrack {
        if let record = saved.first(where: { $0.id == track.id }) {
            // Chart rows may initially omit duration. Enrich only that missing field;
            // retain the saved Apple metadata and all library/download state.
            if track.duration.isFinite, track.duration > 0, var existing = record.track,
               !existing.duration.isFinite || existing.duration <= 0 {
                existing.duration = track.duration
                if let metadata = try? JSONEncoder().encode(existing) { record.metadata = metadata }
            }
            return record
        }
        let record = SavedTrack(track); context.insert(record); saved.append(record)
        var order = insertionDefaults.stringArray(forKey: insertionKey) ?? []
        order.removeAll { $0 == track.id }; order.insert(track.id, at: 0)
        insertionDefaults.set(order, forKey: insertionKey)
        var dates = addedDates; dates[track.id] = now().timeIntervalSince1970
        insertionDefaults.set(dates, forKey: addedDatesKey)
        return record
    }
    func isFavorite(_ track: Track) -> Bool { saved.first { $0.id == track.id }?.favorite == true }
    func toggleFavorite(_ track: Track) { let item = record(track); item.favorite.toggle(); commit() }
    func played(_ track: Track) {
        let item = record(track); item.lastPlayed = .now; item.playCount += 1; commit()
    }
    var favorites: [Track] { saved.filter(\.favorite).compactMap(\.track).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    var recent: [Track] { saved.filter { $0.lastPlayed != nil }.sorted { $0.lastPlayed! > $1.lastPlayed! }.compactMap(\.track) }
    var downloaded: [Track] { saved.filter { localURL($0.id) != nil }.compactMap(\.track) }
    func localURL(_ id: String) -> URL? {
        guard let file = saved.first(where: { $0.id == id })?.downloadFile else { return nil }
        let url = MusicFiles.downloads.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func markDownloaded(_ track: Track, filename: String) { record(track).downloadFile = filename; commit() }
    func removeDownload(_ track: Track) {
        if let url = localURL(track.id) {
            do { try FileManager.default.removeItem(at: url) } catch { self.error = error.localizedDescription; return }
        }
        saved.first { $0.id == track.id }?.downloadFile = nil; commit()
    }
    func createPlaylist(_ name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !clean.isEmpty else { return }
        let list = SavedPlaylist(name: clean); list.createdAt = now()
        context.insert(list); commit()
    }
    func deletePlaylist(_ list: SavedPlaylist) { context.delete(list); commit() }
    func add(_ track: Track, to list: SavedPlaylist) {
        _ = record(track)
        if !list.trackIDs.contains(track.id) { list.trackIDs.append(track.id) }
        commit()
    }
    func tracks(in playlist: SavedPlaylist) -> [Track] {
        playlist.trackIDs.compactMap { id in saved.first { $0.id == id }?.track }
    }
    func removeHistory() { for item in saved { item.lastPlayed = nil; item.playCount = 0 }; commit() }
    func backup() throws -> Data {
        let dates = addedDates
        let tracks = saved.compactMap { item -> LibraryBackup.BackupTrack? in
            guard let track = item.track else { return nil }
            return .init(track: track, favorite: item.favorite, lastPlayed: item.lastPlayed, playCount: item.playCount, addedAt: Date(timeIntervalSince1970: dates[item.id] ?? Date.distantPast.timeIntervalSince1970))
        }
        var settings = ["quality", "theme", "language", "wifiOnly", "followedArtists"].reduce(into: [String:String]()) { result, key in
            if let value = UserDefaults.standard.object(forKey: key) { result[key] = String(describing: value) }
        }
        settings["lowDataMode"] = String(PlaybackPreferences.savesData())
        let payload = LibraryBackup(tracks: tracks, playlists: playlists.map { .init(id: $0.id, name: $0.name, trackIDs: $0.trackIDs, createdAt: $0.createdAt) }, settings: settings)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }
    func restore(_ data: Data) throws {
        guard data.count <= 20_000_000 else { throw APIError.server(L("Yedek dosyası çok büyük.")) }
        let backup = try JSONDecoder().decode(LibraryBackup.self, from: data)
        guard backup.version == 1, backup.tracks.count <= 50000 else { throw APIError.invalidResponse }
        for entry in backup.tracks {
            let item = record(entry.track)
            if let date = entry.addedAt, date < addedAt(item.id) {
                var dates = addedDates; dates[item.id] = date.timeIntervalSince1970
                insertionDefaults.set(dates, forKey: addedDatesKey)
            }
            item.favorite = item.favorite || entry.favorite
            item.playCount = max(item.playCount, entry.playCount)
            if let last = entry.lastPlayed, last > (item.lastPlayed ?? .distantPast) { item.lastPlayed = last }
        }
        let known = Set(saved.map(\.id))
        for entry in backup.playlists where !playlists.contains(where: { $0.id == entry.id }) {
            let list = SavedPlaylist(name: String(entry.name.prefix(100)), trackIDs: entry.trackIDs.filter { known.contains($0) })
            list.id = entry.id; context.insert(list)
            if let date = entry.createdAt { list.createdAt = date }
        }
        for key in ["quality", "theme", "language", "followedArtists"] {
            if let value = backup.settings[key] { UserDefaults.standard.set(value, forKey: key) }
        }
        if let value = backup.settings["wifiOnly"] { UserDefaults.standard.set(value == "true" || value == "1", forKey: "wifiOnly") }
        if let value = backup.settings["lowDataMode"] { UserDefaults.standard.set(value == "true" || value == "1", forKey: "lowDataMode") }
        else if let quality = backup.settings["quality"] { UserDefaults.standard.set(quality == "data", forKey: "lowDataMode") }
        commit()
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
