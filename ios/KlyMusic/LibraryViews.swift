import SwiftUI

struct LibraryPin: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var kind: String // "playlist" | "album" | "artist"
    var targetID: String
    var title: String
    var subtitle: String
    var artwork: String?
}

enum LibraryPinsStore {
    static let storageKey = "libraryPins-v1"
    static func decode(_ storedValue: String) -> [LibraryPin] {
        guard let data = storedValue.data(using: .utf8),
              let pins = try? JSONDecoder().decode([LibraryPin].self, from: data) else { return [] }
        var seen = Set<String>()
        return pins.filter { seen.insert($0.id).inserted }
    }
    static func encode(_ pins: [LibraryPin]) -> String {
        String(data: (try? JSONEncoder().encode(Array(pins.prefix(9)))) ?? Data(), encoding: .utf8) ?? ""
    }
    static func contains(id: String, in storedValue: String) -> Bool {
        decode(storedValue).contains { $0.id == id }
    }
    static func toggle(_ pin: LibraryPin, in storedValue: String) -> String {
        var pins = decode(storedValue)
        if let index = pins.firstIndex(where: { $0.id == pin.id }) {
            pins.remove(at: index)
        } else {
            pins.insert(pin, at: 0)
        }
        return encode(pins)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var newList = false
    @State private var destination: LibraryDestination?
    @State private var editingCategories = false
    @AppStorage("libraryLayout-v1") private var layoutValue = ""
    @AppStorage("librarySort-v1") private var sortValue = LibraryCollectionSort.added.rawValue
    @AppStorage("followedArtists") private var followedArtists = ""
    @AppStorage(LibraryPinsStore.storageKey) private var pinsValue = ""
    private var layout: LibraryLayout { LibraryLayout(storedValue: layoutValue) }
    private var pins: [LibraryPin] { LibraryPinsStore.decode(pinsValue) }
    private var recent: [LibraryRecentEntry] {
        Array((LibraryCollectionSort(rawValue: sortValue) ?? .added).sorted(library.recentlyAddedCollections).prefix(16))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !pins.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L("Sabitlenenler"))
                            .font(.title2.weight(.bold))
                            .tracking(-0.5)
                            .foregroundStyle(.primary)
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 14, alignment: .top),
                                GridItem(.flexible(), spacing: 14, alignment: .top),
                                GridItem(.flexible(), spacing: 14, alignment: .top)
                            ],
                            spacing: 16
                        ) {
                            ForEach(pins) { pin in
                                pinTile(pin)
                            }
                        }
                    }
                }

                VStack(spacing: 0) {
                    ForEach(layout.visible) { category in
                        libraryRow(
                            category.title,
                            symbol: category.symbol,
                            destination: category.destination,
                            count: categoryCount(for: category),
                            identifier: "library." + category.rawValue
                        )
                    }
                }

                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(L(sortValue == LibraryCollectionSort.added.rawValue ? "Son Eklenenler" : "Albümler ve Listeler"))
                                .font(.title2.weight(.bold))
                                .tracking(-0.5)
                                .foregroundStyle(.primary)
                            Spacer()
                            Menu {
                                Picker(L("Sırala"), selection: $sortValue) {
                                    ForEach(LibraryCollectionSort.allCases) { sort in
                                        Text(L(sort.title)).tag(sort.rawValue)
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(.caption.weight(.semibold))
                                    Text(L("Sırala"))
                                        .font(.subheadline.weight(.medium))
                                }
                                .foregroundStyle(Color.musicAccent)
                                .frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("library.sort")
                        }
                        .padding(.top, 4)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 22) {
                            ForEach(recent) { entry in
                                recentCard(entry)
                            }
                        }
                    }
                } else if library.saved.isEmpty && library.playlists.isEmpty && categoryCount(for: .artists) == 0 {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(Color.coral)
                            .frame(width: 78, height: 78)
                            .background(Color.musicElevated, in: Circle())
                        Text(L("Kütüphanen seni bekliyor"))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(L("Dinlediğin müzikler ve oluşturduğun listeler burada görünür."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button {
                            newList = true
                        } label: {
                            Label(L("Yeni Çalma Listesi…"), systemImage: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Color.musicElevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("library.empty.createPlaylist")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .accessibilityIdentifier("library.empty")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .tint(Color.musicAccent)
        .navigationTitle(L("Kütüphane"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .playlists: PlaylistsView()
            case .songs: TrackListView(title: L("Şarkılar"), tracks: library.saved.compactMap(\.track).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }, style: .songs)
            case .favorites: TrackListView(title: L("Favoriler"), tracks: library.favorites, style: .songs)
            case .downloads: DownloadsView()
            case .recent: TrackListView(title: L("Son dinlenenler"), tracks: library.recent, style: .songs)
            case .albums: SavedAlbumsView()
            case .artists: FollowedArtistsView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newList = true } label: {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L("Yeni Çalma Listesi"))
                .accessibilityIdentifier("library.quickCreate")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { newList = true } label: { Label(L("Yeni Çalma Listesi…"), systemImage: "text.badge.plus") }.accessibilityIdentifier("playlist.create")
                    Button { editingCategories = true } label: { Label(L("Düzenle"), systemImage: "line.3.horizontal") }.accessibilityIdentifier("library.edit")
                    Divider()
                    Button { destination = .favorites } label: { Label(L("Favoriler"), systemImage: "star") }.accessibilityIdentifier("library.favorites")
                    Button { destination = .recent } label: { Label(L("Son dinlenenler"), systemImage: "clock") }.accessibilityIdentifier("library.recent")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L("Kütüphane Seçenekleri"))
                .accessibilityIdentifier("library.options")
            }
            ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
        }
        .sheet(isPresented: $newList) { CreatePlaylistView() }
        .sheet(isPresented: $editingCategories) { LibraryLayoutEditor(storedValue: $layoutValue) }
    }

    @ViewBuilder private func pinTile(_ pin: LibraryPin) -> some View {
        NavigationLink {
            pinDestination(for: pin)
        } label: {
            VStack(spacing: 6) {
                Group {
                    if pin.kind == "playlist", let list = library.playlists.first(where: { $0.id.uuidString == pin.targetID }) {
                        PlaylistArtwork(tracks: library.tracks(in: list), radius: 10)
                    } else if pin.kind == "artist" {
                        ArtistPortrait(url: pin.artwork, name: pin.title)
                    } else {
                        Artwork(url: pin.artwork, radius: 10)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(6)
                }

                VStack(spacing: 1) {
                    Text(pin.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !pin.subtitle.isEmpty {
                        Text(pin.subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(CardButtonStyle())
        .contextMenu {
            Button {
                pinsValue = LibraryPinsStore.toggle(pin, in: pinsValue)
            } label: {
                Label(L("Sabitlemeyi Kaldır"), systemImage: "pin.slash")
            }
        }
    }

    @ViewBuilder private func pinDestination(for pin: LibraryPin) -> some View {
        if pin.kind == "playlist", let list = library.playlists.first(where: { $0.id.uuidString == pin.targetID }) {
            PlaylistDetailView(playlist: list)
        } else if pin.kind == "artist" {
            ArtistDetailView(id: pin.targetID, name: pin.title)
        } else if let albumID = pin.targetID.isEmpty ? nil : pin.targetID, !albumID.hasPrefix("local:") {
            AlbumDetailView(collection: .init(id: albumID, title: pin.title, artist: pin.subtitle, artwork: pin.artwork))
        } else {
            TrackListView(title: pin.title, tracks: library.saved.compactMap(\.track).filter { $0.album == pin.title }, subtitle: pin.subtitle.isEmpty ? nil : pin.subtitle)
        }
    }

    private func pinModel(for entry: LibraryRecentEntry) -> LibraryPin {
        switch entry.content {
        case .playlist(let list):
            return LibraryPin(
                id: "playlist:" + list.id.uuidString,
                kind: "playlist",
                targetID: list.id.uuidString,
                title: list.name,
                subtitle: L("Çalma Listesi"),
                artwork: library.tracks(in: list).first?.artwork
            )
        case .album(let track):
            let albumID = track.albumID ?? ""
            return LibraryPin(
                id: "album:" + (albumID.isEmpty ? track.id : albumID),
                kind: "album",
                targetID: albumID,
                title: entry.title,
                subtitle: entry.artist,
                artwork: track.artwork
            )
        }
    }

    private func recentCard(_ entry: LibraryRecentEntry) -> some View {
        let pin = pinModel(for: entry)
        let isPinned = LibraryPinsStore.contains(id: pin.id, in: pinsValue)
        return NavigationLink {
            switch entry.content {
            case .playlist(let list): PlaylistDetailView(playlist: list)
            case .album(let track): TrackListView(title: entry.title, tracks: albumTracks(track), subtitle: entry.artist.isEmpty ? nil : entry.artist)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    switch entry.content {
                    case .playlist(let list):
                        PlaylistArtwork(tracks: library.tracks(in: list), radius: 10)
                    case .album(let track):
                        Artwork(url: track.artwork, radius: 10)
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.artist.isEmpty ? L("Çalma Listesi") : entry.artist)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(CardButtonStyle())
        .contextMenu {
            Button {
                pinsValue = LibraryPinsStore.toggle(pin, in: pinsValue)
            } label: {
                Label(L(isPinned ? "Sabitlemeyi Kaldır" : "Kütüphaneye Sabitle"), systemImage: isPinned ? "pin.slash" : "pin")
            }
        }
        .accessibilityIdentifier("library.recent." + entry.id)
    }

    private func albumTracks(_ track: Track) -> [Track] {
        guard let id = track.albumID else { return [track] }
        return library.saved.compactMap(\.track).filter { $0.albumID == id }
    }

    private func categoryCount(for category: LibraryCategory) -> Int {
        switch category {
        case .playlists:
            return library.playlists.count
        case .artists:
            let followedIDs = followedArtists.components(separatedBy: "\n").compactMap { value -> String? in
                let parts = value.split(separator: "|", maxSplits: 1)
                return parts.count == 2 ? String(parts[0]) : nil
            }
            let savedIDs = library.saved.compactMap(\.track).compactMap { track -> String? in
                guard let id = track.artistID, !id.isEmpty else { return nil }
                return id
            }
            return Set(followedIDs + savedIDs).count
        case .albums:
            return Set(library.saved.compactMap(\.track).compactMap { track -> String? in
                guard let id = track.albumID, !id.isEmpty else { return nil }
                return id
            }).count
        case .songs:
            return library.saved.compactMap(\.track).count
        case .downloads:
            return library.downloaded.count
        }
    }

    private func libraryRow(_ title: String, symbol: String, destination: LibraryDestination, count: Int, identifier: String) -> some View {
        VStack(spacing: 0) {
            Button { self.destination = destination } label: {
                LibraryLink(title: L(title), symbol: symbol, count: count)
            }
            .buttonStyle(TrackRowButtonStyle())
            .accessibilityIdentifier(identifier)

            Divider()
                .padding(.leading, 42)
        }
    }
}

enum LibraryCategory: String, CaseIterable, Codable, Identifiable {
    case playlists, artists, albums, songs, downloads
    var id: String { rawValue }
    var title: String {
        switch self {
        case .playlists: "Çalma Listeleri"
        case .artists: "Sanatçılar"
        case .albums: "Albümler"
        case .songs: "Şarkılar"
        case .downloads: "İndirilenler"
        }
    }
    var symbol: String {
        switch self {
        case .playlists: "music.note.list"
        case .artists: "music.mic"
        case .albums: "square.stack"
        case .songs: "music.note"
        case .downloads: "arrow.down.circle"
        }
    }
    fileprivate var destination: LibraryDestination {
        switch self {
        case .playlists: .playlists
        case .artists: .artists
        case .albums: .albums
        case .songs: .songs
        case .downloads: .downloads
        }
    }
}

struct LibraryLayout: Codable, Equatable {
    var order = LibraryCategory.allCases
    var hidden = Set<LibraryCategory>()
    var visible: [LibraryCategory] { order.filter { !hidden.contains($0) } }
    init(storedValue: String) {
        if let data = storedValue.data(using: .utf8), let saved = try? JSONDecoder().decode(Self.self, from: data) {
            var seen = Set<LibraryCategory>()
            order = (saved.order + LibraryCategory.allCases).filter { seen.insert($0).inserted }
            hidden = saved.hidden
            if visible.isEmpty { hidden.remove(order[0]) }
        }
    }
    var storedValue: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "" }
}

enum LibraryCollectionSort: String, CaseIterable, Identifiable {
    case added, title, artist
    var id: String { rawValue }
    var title: String {
        switch self {
        case .added: "Son Eklenenler"
        case .title: "Başlık"
        case .artist: "Sanatçı"
        }
    }
    func sorted(_ entries: [LibraryRecentEntry]) -> [LibraryRecentEntry] {
        entries.sorted { first, second in
            switch self {
            case .added: return first.addedAt == second.addedAt ? first.id < second.id : first.addedAt > second.addedAt
            case .title:
                let comparison = first.title.localizedStandardCompare(second.title)
                return comparison == .orderedSame ? first.id < second.id : comparison == .orderedAscending
            case .artist:
                let comparison = first.artist.localizedStandardCompare(second.artist)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                let title = first.title.localizedStandardCompare(second.title)
                return title == .orderedSame ? first.id < second.id : title == .orderedAscending
            }
        }
    }
}

private struct LibraryLayoutEditor: View {
    @Binding var storedValue: String
    @Environment(\.dismiss) private var dismiss
    private var layout: LibraryLayout { LibraryLayout(storedValue: storedValue) }
    var body: some View {
        NavigationStack {
            List {
                ForEach(layout.order) { category in
                    Button {
                        var updated = layout
                        if updated.hidden.contains(category) { updated.hidden.remove(category) }
                        else if updated.visible.count > 1 { updated.hidden.insert(category) }
                        storedValue = updated.storedValue
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: layout.hidden.contains(category) ? "circle" : "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(layout.hidden.contains(category) ? Color.secondary : Color.coral)
                            Label(L(category.title), systemImage: category.symbol)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .frame(minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.category." + category.rawValue)
                    .accessibilityAddTraits(layout.hidden.contains(category) ? [] : .isSelected)
                }
                .onMove { source, destination in
                    var updated = layout
                    updated.order.move(fromOffsets: source, toOffset: destination)
                    storedValue = updated.storedValue
                }
                .listRowBackground(Color.musicElevated)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .environment(\.editMode, .constant(.active))
            .navigationTitle(L("Kütüphaneyi Düzenle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Bitti")) { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.coral)
                }
            }
        }
        .presentationBackground(Color.pageBackground)
    }
}

private enum LibraryDestination: Hashable {
    case playlists, songs, favorites, downloads, recent, albums, artists
}

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var creating = false
    @State private var searchText = ""
    @AppStorage(LibraryPinsStore.storageKey) private var pinsValue = ""

    private var filteredPlaylists: [SavedPlaylist] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return library.playlists }
        let normalizedQuery = NativeCatalog.normalized(trimmed)
        return library.playlists.filter { NativeCatalog.normalized($0.name).contains(normalizedQuery) }
    }

    var body: some View {
        List {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { creating = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.coral)
                            .frame(width: 58, height: 58)
                            .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(L("Yeni Çalma Listesi…"))
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.coral)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("playlist.create")

                NavigationLink {
                    TrackListView(title: L("Favoriler"), tracks: library.favorites, style: .songs)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.coral)
                        Image(systemName: "star.fill")
                            .font(.system(size: 23))
                            .foregroundStyle(Color.coral)
                            .frame(width: 58, height: 58)
                            .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Favoriler"))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(String(format: L("%lld şarkı"), Int64(library.favorites.count)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("library.favorites")
            }

            ForEach(filteredPlaylists) { playlist in
                playlistRow(playlist)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.pageBackground)
        .navigationTitle(L("Çalma Listeleri"))
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(L("Kütüphanende ara")))
        .tint(.primary)
        .sheet(isPresented: $creating) { CreatePlaylistView() }
    }

    private func playlistRow(_ playlist: SavedPlaylist) -> some View {
        let pin = LibraryPin(
            id: "playlist:" + playlist.id.uuidString,
            kind: "playlist",
            targetID: playlist.id.uuidString,
            title: playlist.name,
            subtitle: L("Çalma Listesi"),
            artwork: library.tracks(in: playlist).first?.artwork
        )
        let isPinned = LibraryPinsStore.contains(id: pin.id, in: pinsValue)
        return NavigationLink { PlaylistDetailView(playlist: playlist) } label: {
            HStack(spacing: 14) {
                PlaylistArtwork(tracks: library.tracks(in: playlist), radius: 12)
                    .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(String(format: L("%lld şarkı"), Int64(playlist.trackIDs.count)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .contextMenu {
            Button {
                pinsValue = LibraryPinsStore.toggle(pin, in: pinsValue)
            } label: {
                Label(L(isPinned ? "Sabitlemeyi Kaldır" : "Kütüphaneye Sabitle"), systemImage: isPinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) { library.deletePlaylist(playlist) } label: {
                Label(L("Sil"), systemImage: "trash")
            }
        }
    }
}

struct CreatePlaylistView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var initialTrack: Track? = nil
    @State private var name = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(LinearGradient(colors: [Color.coral.opacity(0.22), Color.musicElevated], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Image(systemName: "music.note.list")
                                .font(.system(size: 52, weight: .light))
                                .foregroundStyle(Color.coral)
                        }
                        .frame(width: 164, height: 164)
                        .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 10)

                    TextField(L("Liste adı"), text: $name)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("playlist.name")
                }
                .listRowBackground(Color.musicElevated)
            }
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .navigationTitle(L("Yeni Çalma Listesi"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Vazgeç")) { dismiss() }
                        .foregroundStyle(Color.coral)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Oluştur")) {
                        let existing = Set(library.playlists.map(\.id))
                        library.createPlaylist(name)
                        if let initialTrack, let list = library.playlists.first(where: { !existing.contains($0.id) }) {
                            library.add(initialTrack, to: list)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.coral)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .tint(Color.coral)
        }
    }
}

struct LibraryLink: View {
    var title: String
    var symbol: String
    var count: Int?
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.musicAccent)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(count.map { String($0) } ?? "")
    }
}

struct PlaylistArtwork: View {
    var tracks: [Track]
    var radius: CGFloat = 12

    private var uniqueArtworks: [String] {
        var seen = Set<String>()
        var urls: [String] = []
        for track in tracks {
            if let art = track.artwork, !art.isEmpty, seen.insert(art).inserted {
                urls.append(art)
                if urls.count == 4 { break }
            }
        }
        return urls
    }

    var body: some View {
        GeometryReader { geometry in
            let mosaic = uniqueArtworks
            Group {
                if mosaic.count >= 4 {
                    VStack(spacing: 0) {
                        ForEach(0..<2) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<2) { column in
                                    Artwork(url: mosaic[row * 2 + column], radius: 0)
                                        .frame(width: geometry.size.width / 2, height: geometry.size.height / 2)
                                }
                            }
                        }
                    }
                } else if let first = tracks.first {
                    Artwork(url: first.artwork, radius: 0)
                } else {
                    ZStack {
                        Color.musicElevated
                        Image(systemName: "music.note.list")
                            .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.32, weight: .light))
                            .foregroundStyle(Color.coral)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}

struct PlaylistPicker: View {
    var track: Track
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    var body: some View {
        NavigationStack {
            List {
                Button { creating = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.coral)
                            .frame(width: 56, height: 56)
                            .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(L("Yeni Çalma Listesi…"))
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.coral)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(library.playlists) { list in
                    VStack(spacing: 0) {
                        Button { library.add(track, to: list); dismiss() } label: {
                            HStack(spacing: 14) {
                                PlaylistArtwork(tracks: library.tracks(in: list), radius: 10)
                                    .frame(width: 56, height: 56)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(list.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(String(format: L("%lld şarkı"), Int64(list.trackIDs.count)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if list.trackIDs.contains(track.id) {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.coral)
                                }
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(TrackRowButtonStyle())
                        Divider().padding(.leading, 70)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .navigationTitle(L("Listeye ekle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Vazgeç")) { dismiss() }
                        .foregroundStyle(Color.coral)
                }
            }
            .sheet(isPresented: $creating) { CreatePlaylistView(initialTrack: track) }
            .tint(Color.coral)
        }
    }
}

struct PlaylistDetailView: View {
    @Bindable var playlist: SavedPlaylist
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LibraryPinsStore.storageKey) private var pinsValue = ""
    @State private var editing: EditMode = .inactive
    @State private var deleting = false
    @State private var rename = false
    @State private var newName = ""
    @State private var searchText = ""

    var tracks: [Track] { library.tracks(in: playlist) }
    private var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !editing.isEditing }
    private var visibleTracks: [Track] {
        isFiltering ? TrackListSort.apply(.standard, query: searchText, to: tracks) : tracks
    }

    private var playlistPin: LibraryPin {
        LibraryPin(
            id: "playlist:" + playlist.id.uuidString,
            kind: "playlist",
            targetID: playlist.id.uuidString,
            title: playlist.name,
            subtitle: L("Çalma Listesi"),
            artwork: tracks.first?.artwork
        )
    }
    private var isPinned: Bool { LibraryPinsStore.contains(id: playlistPin.id, in: pinsValue) }

    private var durationText: String {
        let totalSeconds = tracks.reduce(0.0) { $0 + ($1.duration.isFinite && $1.duration > 0 ? $1.duration : 0.0) }
        let count = Int64(tracks.count)
        if totalSeconds > 0 {
            let minutes = Int64(totalSeconds / 60)
            return String(format: L("%lld şarkı, %lld dakika"), count, minutes)
        } else {
            return String(format: L("%lld şarkı"), count)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    PlaylistArtwork(tracks: tracks, radius: 14)
                        .frame(width: 236, height: 236)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 9)
                        .padding(.top, 10)

                    VStack(spacing: 5) {
                        Text(playlist.name)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                        Text(L("Çalma Listesi"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.coral)
                        Text(durationText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    CollectionPlayButtons(tracks: visibleTracks)
                        .padding(.top, 4)

                    Divider()
                        .overlay(Color.primary.opacity(0.08))
                        .padding(.leading, 64)
                        .padding(.top, 6)
                }
                .padding(.bottom, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if isFiltering && visibleTracks.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "Sonuç bulunamadı", message: "Farklı bir arama dene.")
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(visibleTracks) { track in
                    VStack(spacing: 0) {
                        TrackRow(track: track, tracks: visibleTracks, showFavoriteDot: true)
                        Divider()
                            .overlay(Color.primary.opacity(0.08))
                            .padding(.leading, 64)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            playlist.trackIDs.removeAll { $0 == track.id }
                            library.commit()
                        } label: {
                            Label(L("Sil"), systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: isFiltering ? nil : { source, destination in
                    playlist.trackIDs.move(fromOffsets: source, toOffset: destination)
                    library.commit()
                })
                .onDelete(perform: isFiltering ? nil : { offsets in
                    let ids = Set(offsets.map { tracks[$0].id })
                    playlist.trackIDs.removeAll { ids.contains($0) }
                    library.commit()
                })
            }

            if tracks.isEmpty {
                EmptyState(symbol: "text.badge.plus", title: "İlk şarkını ekle", message: "Bir şarkının seçeneklerinden bu listeye ekleyebilirsin.")
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if !visibleTracks.isEmpty {
                Text(durationText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 16, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.pageBackground)
        .navigationBarTitleDisplayMode(.inline)
        .optionalSearchable(!tracks.isEmpty && !editing.isEditing, text: $searchText, prompt: "Listede ara")
        .tint(Color.coral)
        .environment(\.editMode, $editing)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editing.isEditing {
                    Button(L("Bitti")) { editing = .inactive }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.coral)
                } else {
                    Menu {
                        Button { pinsValue = LibraryPinsStore.toggle(playlistPin, in: pinsValue) } label: {
                            Label(L(isPinned ? "Sabitlemeyi Kaldır" : "Kütüphaneye Sabitle"), systemImage: isPinned ? "pin.slash" : "pin")
                        }
                        Button { editing = .active } label: { Label(L("Çalma Listesini Düzenle"), systemImage: "pencil") }
                        Button { newName = playlist.name; rename = true } label: { Label(L("Yeniden Adlandır"), systemImage: "textformat") }
                        Section {
                            Button { tracks.forEach { downloads.enqueue($0) } } label: { Label(L("İndir"), systemImage: "arrow.down.circle") }
                            Button(role: .destructive) { deleting = true } label: { Label(L("Çalma Listesini Sil"), systemImage: "trash") }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L("Çalma Listesi Seçenekleri"))
                }
            }
        }
        .confirmationDialog(L("Çalma listesi silinsin mi?"), isPresented: $deleting, titleVisibility: .visible) {
            Button(L("Çalma Listesini Sil"), role: .destructive) { library.deletePlaylist(playlist); dismiss() }
        }
        .alert(L("Yeniden Adlandır"), isPresented: $rename) {
            TextField(L("Liste adı"), text: $newName)
            Button(L("Kaydet")) {
                let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { playlist.name = String(value.prefix(100)); library.commit() }
            }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(L("Vazgeç"), role: .cancel) { }
        }
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var player: MusicPlayer
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmDelete = false
    @State private var searchText = ""

    private var visibleDownloaded: [Track] {
        TrackListSort.apply(.standard, query: searchText, to: library.downloaded)
    }

    var body: some View {
        List {
            if !library.downloaded.isEmpty || !downloads.jobs.isEmpty {
                Section {
                    CollectionPlayButtons(tracks: visibleDownloaded)
                        .padding(.vertical, 8)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if !downloads.jobs.isEmpty {
                Section {
                    ForEach(Array(downloads.jobs.keys).sorted(), id: \.self) { id in
                        if let job = downloads.jobs[id], let track = library.saved.first(where: { $0.id == id })?.track {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Artwork(url: track.artwork, radius: 8).frame(width: 52, height: 52)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                        Text(job.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    if !typeSize.isAccessibilitySize { jobControls(id: id, track: track, canRetry: job.failed || job.paused) }
                                }
                                if typeSize.isAccessibilitySize {
                                    HStack { Spacer(); jobControls(id: id, track: track, canRetry: job.failed || job.paused) }
                                }
                                ProgressView(value: job.progress).tint(Color.coral)
                            }
                            .padding(.vertical, 10)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        }
                    }
                } header: {
                    Text(L("İndirme sırası"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                        .padding(.bottom, 6)
                }
                .listRowBackground(Color.clear)
            }

            if !library.downloaded.isEmpty {
                Section {
                    if visibleDownloaded.isEmpty {
                        EmptyState(symbol: "magnifyingglass", title: "Sonuç bulunamadı", message: "Farklı bir arama dene.")
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(visibleDownloaded) { track in
                            VStack(spacing: 0) {
                                TrackRow(track: track, tracks: visibleDownloaded, showFavoriteDot: true)
                                Divider().overlay(Color.primary.opacity(0.08)).padding(.leading, 64)
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .swipeActions { Button(L("Sil"), role: .destructive) { library.removeDownload(track) } }
                        }
                    }
                } header: {
                    HStack {
                        Text(L("Bu cihazda"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(String(format: L("%lld şarkı"), Int64(visibleDownloaded.count)))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.pageBackground)
        .navigationTitle(L("İndirilenler"))
        .optionalSearchable(library.downloaded.count > 3, text: $searchText, prompt: "İndirilenlerde ara")
        .overlay {
            if library.downloaded.isEmpty && downloads.jobs.isEmpty {
                EmptyState(symbol: "arrow.down.circle", title: "İndirilen Müzik Yok", message: "İndirdiğin müzikler burada görünür.")
            }
        }
        .toolbar {
            if !library.downloaded.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.coral)
                    }
                    .accessibilityLabel(L("İndirilenleri sil"))
                }
            }
        }
        .confirmationDialog(L("Tüm indirilen şarkılar silinsin mi?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("İndirilenleri sil"), role: .destructive) { library.downloaded.forEach { library.removeDownload($0) } }
        }
    }

    private func jobControls(id: String, track: Track, canRetry: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                if canRetry { downloads.enqueue(track) } else { downloads.pause(id) }
            } label: {
                Image(systemName: canRetry ? "arrow.clockwise" : "pause.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel(L(canRetry ? "Yeniden dene" : "Duraklat"))

            Button { downloads.cancel(id) } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel(L("İptal"))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.coral)
    }
}

struct SavedAlbumsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var searchText = ""

    var albums: [MusicCollection] {
        var seen = Set<String>()
        return library.saved.compactMap(\.track).compactMap { track in
            guard let id = track.albumID, !id.isEmpty, seen.insert(id).inserted else { return nil }
            return MusicCollection(id: id, title: track.album, artist: track.artist, artwork: track.artwork)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var visibleAlbums: [MusicCollection] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return albums }
        let needle = NativeCatalog.normalized(trimmed)
        return albums.filter {
            NativeCatalog.normalized($0.title).contains(needle) || NativeCatalog.normalized($0.artist).contains(needle)
        }
    }

    var body: some View {
        let columns = typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 14)]
            : [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if !visibleAlbums.isEmpty {
                    Text(String(format: L("%lld albüm"), Int64(visibleAlbums.count)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(visibleAlbums) { album in
                            NavigationLink {
                                TrackListView(
                                    title: album.title,
                                    tracks: library.saved.compactMap(\.track).filter { $0.albumID == album.id },
                                    subtitle: album.artist
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Artwork(url: album.artwork, radius: 10)
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .shadow(color: .black.opacity(0.18), radius: 7, x: 0, y: 4)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(album.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                        Text(album.artist)
                                            .font(.system(size: 13.5))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                } else if !albums.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "Sonuç bulunamadı", message: "Farklı bir arama dene.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .navigationTitle(L("Albümler"))
        .optionalSearchable(!albums.isEmpty, text: $searchText, prompt: "Albümlerde ara")
        .overlay {
            if albums.isEmpty {
                EmptyState(symbol: "square.stack", title: "Albümlerin burada", message: "Kaydettiğin şarkıların albümleri burada görünecek.")
            }
        }
    }
}

struct FollowedArtistsView: View {
    @AppStorage("followedArtists") private var followed = ""
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var searchText = ""
    @State private var portraits: [String: String] = [:]

    var artists: [(String, String)] {
        let followedRows = followed.components(separatedBy: "\n").compactMap { value -> (String, String)? in
            let parts = value.split(separator: "|", maxSplits: 1)
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        }
        let savedRows = library.saved.compactMap(\.track).compactMap { track -> (String, String)? in
            guard let id = track.artistID, !id.isEmpty else { return nil }
            return (id, track.artist)
        }
        var seen = Set<String>()
        return (followedRows + savedRows).filter { seen.insert($0.0).inserted }.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }

    private var savedArtworkByArtist: [String: String] {
        var map: [String: String] = [:]
        for track in library.saved.compactMap(\.track) {
            if let id = track.artistID, !id.isEmpty, map[id] == nil, let art = track.artwork, !art.isEmpty {
                map[id] = art
            }
        }
        return map
    }

    private var visibleArtists: [(String, String)] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return artists }
        let needle = NativeCatalog.normalized(trimmed)
        return artists.filter { NativeCatalog.normalized($0.1).contains(needle) }
    }

    var body: some View {
        let fallbackArt = savedArtworkByArtist
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !visibleArtists.isEmpty {
                    Text(String(format: L("%lld sanatçı takip ediliyor"), Int64(visibleArtists.count)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 16)
                    ForEach(visibleArtists, id: \.0) { artist in
                        NavigationLink { ArtistDetailView(id: artist.0, name: artist.1) } label: {
                            HStack(spacing: 16) {
                                ArtistPortrait(url: portraits[artist.0] ?? fallbackArt[artist.0], name: artist.1)
                                    .frame(width: 58, height: 58)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(artist.1)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                    Text(L("Sanatçı"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(TrackRowButtonStyle())
                        Divider()
                            .overlay(Color.primary.opacity(0.08))
                            .padding(.leading, 74)
                    }
                } else if !artists.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "Sonuç bulunamadı", message: "Farklı bir arama dene.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .navigationTitle(L("Sanatçılar"))
        .optionalSearchable(!artists.isEmpty, text: $searchText, prompt: "Sanatçılarda ara")
        .overlay {
            if artists.isEmpty {
                EmptyState(symbol: "person.2", title: "Sevdiğin sesleri takip et", message: "Sanatçı sayfalarından takip ettiğin isimler burada görünecek.")
            }
        }
        .task(id: artists.map(\.0).joined(separator: "|")) {
            let localArt = savedArtworkByArtist
            for artist in artists where portraits[artist.0] == nil && localArt[artist.0] == nil {
                guard !Task.isCancelled else { return }
                if let profile = try? await API.shared.artist(artist.0),
                   let url = profile.artist.artwork ?? profile.tracks.first?.artwork, !url.isEmpty {
                    portraits[artist.0] = url
                }
            }
        }
    }
}
