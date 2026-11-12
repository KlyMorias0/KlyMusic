import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var newList = false
    @State private var destination: LibraryDestination?
    @State private var editingCategories = false
    @AppStorage("libraryLayout-v1") private var layoutValue = ""
    @AppStorage("librarySort-v1") private var sortValue = LibraryCollectionSort.added.rawValue
    private var layout: LibraryLayout { LibraryLayout(storedValue: layoutValue) }
    private var recent: [LibraryRecentEntry] {
        Array((LibraryCollectionSort(rawValue: sortValue) ?? .added).sorted(library.recentlyAddedCollections).prefix(16))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 0) {
                    ForEach(layout.visible) { category in
                        libraryRow(category.title, symbol: category.symbol, destination: category.destination, identifier: "library." + category.rawValue)
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
                                .foregroundStyle(Color.coral)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.musicElevated, in: Capsule())
                            }
                            .accessibilityIdentifier("library.sort")
                        }
                        .padding(.top, 4)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], alignment: .leading, spacing: 22) {
                            ForEach(recent) { entry in
                                recentCard(entry)
                            }
                        }
                    }
                } else if library.saved.isEmpty && library.playlists.isEmpty && library.favorites.isEmpty {
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
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .navigationTitle(L("Kütüphane"))
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .playlists: PlaylistsView()
            case .songs: TrackListView(title: L("Şarkılar"), tracks: library.saved.compactMap(\.track).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            case .favorites: TrackListView(title: L("Favoriler"), tracks: library.favorites)
            case .downloads: DownloadsView()
            case .recent: TrackListView(title: L("Son dinlenenler"), tracks: library.recent)
            case .albums: SavedAlbumsView()
            case .artists: FollowedArtistsView()
            }
        }
        .toolbar {
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

    private func recentCard(_ entry: LibraryRecentEntry) -> some View {
        NavigationLink {
            switch entry.content {
            case .playlist(let list): PlaylistDetailView(playlist: list)
            case .album(let track): TrackListView(title: entry.title, tracks: albumTracks(track))
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    switch entry.content {
                    case .playlist(let list):
                        PlaylistArtwork(tracks: library.tracks(in: list), radius: 12)
                    case .album(let track):
                        Artwork(url: track.artwork, radius: 12)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.artist.isEmpty ? L("Çalma Listesi") : entry.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityIdentifier("library.recent." + entry.id)
    }

    private func albumTracks(_ track: Track) -> [Track] {
        guard let id = track.albumID else { return [track] }
        return library.saved.compactMap(\.track).filter { $0.albumID == id }
    }

    private func libraryRow(_ title: String, symbol: String, destination: LibraryDestination, identifier: String) -> some View {
        VStack(spacing: 0) {
            Button { self.destination = destination } label: {
                LibraryLink(title: L(title), symbol: symbol, count: nil, color: Color.coral)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)

            Divider()
                .overlay(Color.primary.opacity(0.08))
                .padding(.leading, 44)
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
        case .artists: "person.crop.circle"
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
    var body: some View {
        List {
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
                TrackListView(title: L("Favoriler"), tracks: library.favorites)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 22))
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

            ForEach(library.playlists) { playlist in
                NavigationLink { PlaylistDetailView(playlist: playlist) } label: {
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
                    Button(role: .destructive) { library.deletePlaylist(playlist) } label: {
                        Label(L("Sil"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.pageBackground)
        .navigationTitle(L("Çalma Listeleri"))
        .tint(.primary)
        .sheet(isPresented: $creating) { CreatePlaylistView() }
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
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(Color.coral)
                            .frame(width: 140, height: 140)
                            .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 12)

                    TextField(L("Liste adı"), text: $name)
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
    var color: Color = Color.coral
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct PlaylistArtwork: View {
    var tracks: [Track]
    var radius: CGFloat = 12
    var body: some View {
        GeometryReader { geometry in
            Group {
                if tracks.count >= 4 {
                    VStack(spacing: 0) {
                        ForEach(0..<2) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<2) { column in
                                    Artwork(url: tracks[row * 2 + column].artwork, radius: 0)
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
                ForEach(library.playlists) { list in
                    Button { library.add(track, to: list); dismiss() } label: {
                        HStack(spacing: 14) {
                            PlaylistArtwork(tracks: library.tracks(in: list), radius: 12)
                                .frame(width: 56, height: 56)
                            Text(list.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            if list.trackIDs.contains(track.id) {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.coral)
                            }
                        }
                        .padding(.vertical, 4)
                    }
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
    @State private var editing: EditMode = .inactive
    @State private var deleting = false
    @State private var rename = false
    @State private var newName = ""

    var tracks: [Track] { library.tracks(in: playlist) }

    private var durationText: String {
        let totalSeconds = tracks.reduce(0.0) { $0 + ($1.duration.isFinite && $1.duration > 0 ? $1.duration : 0.0) }
        let count = Int64(tracks.count)
        if totalSeconds > 0 {
            let minutes = Int64(totalSeconds / 60)
            return String(format: L("%lld şarkı · %@"), count, String(format: L("%lld dakika"), minutes))
        } else {
            return String(format: L("%lld şarkı"), count)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    PlaylistArtwork(tracks: tracks, radius: 14)
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
                        .padding(.top, 12)

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

                    CollectionPlayButtons(tracks: tracks)
                        .padding(.top, 4)

                    Divider()
                        .overlay(Color.primary.opacity(0.08))
                        .padding(.top, 8)
                }
                .padding(.bottom, 6)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, tracks: tracks, number: index + 1)
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
            .onMove { source, destination in
                playlist.trackIDs.move(fromOffsets: source, toOffset: destination)
                library.commit()
            }
            .onDelete { offsets in
                let ids = Set(offsets.map { tracks[$0].id })
                playlist.trackIDs.removeAll { ids.contains($0) }
                library.commit()
            }

            if tracks.isEmpty {
                EmptyState(symbol: "text.badge.plus", title: "İlk şarkını ekle", message: "Bir şarkının seçeneklerinden bu listeye ekleyebilirsin.")
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.pageBackground)
        .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        List {
            if !library.downloaded.isEmpty || !downloads.jobs.isEmpty {
                Section {
                    CollectionPlayButtons(tracks: library.downloaded)
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
                    ForEach(library.downloaded) { track in
                        TrackRow(track: track, tracks: library.downloaded)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .swipeActions { Button(L("Sil"), role: .destructive) { library.removeDownload(track) } }
                    }
                } header: {
                    Text(L("Bu cihazda"))
                        .font(.headline)
                        .foregroundStyle(.primary)
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
    var albums: [MusicCollection] {
        var seen = Set<String>()
        return library.saved.compactMap(\.track).compactMap { track in
            guard let id = track.albumID, !id.isEmpty, seen.insert(id).inserted else { return nil }
            return MusicCollection(id: id, title: track.album, artist: track.artist, artwork: track.artwork)
        }.sorted { $0.title < $1.title }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !albums.isEmpty {
                    Text(String(format: L("%lld albüm"), Int64(albums.count)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 150), spacing: 16, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(albums) { album in
                        NavigationLink {
                            TrackListView(title: album.title, tracks: library.saved.compactMap(\.track).filter { $0.albumID == album.id })
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Artwork(url: album.artwork, radius: 12)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                    Text(album.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .navigationTitle(L("Albümler"))
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
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !artists.isEmpty {
                    Text(String(format: L("%lld sanatçı takip ediliyor"), Int64(artists.count)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 16)
                }
                ForEach(artists, id: \.0) { artist in
                    NavigationLink { ArtistDetailView(id: artist.0, name: artist.1) } label: {
                        HStack(spacing: 16) {
                            ArtistPortrait(url: nil, name: artist.1)
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
                    .buttonStyle(.plain)
                    Divider()
                        .overlay(Color.primary.opacity(0.08))
                        .padding(.leading, 74)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .navigationTitle(L("Sanatçılar"))
        .overlay {
            if artists.isEmpty {
                EmptyState(symbol: "person.2", title: "Sevdiğin sesleri takip et", message: "Sanatçı sayfalarından takip ettiğin isimler burada görünecek.")
            }
        }
    }
}
