import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playerBackdrop: MusicPlayer
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var newList = false
    @State private var listName = ""
    @State private var destination: LibraryDestination?
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                destinations
                playlists
            }
            .padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 32)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background { AlbumBackdrop(artwork: playerBackdrop.current?.artwork ?? library.recent.first?.artwork) }.navigationTitle("Kütüphane")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .favorites: TrackListView(title: L("Favoriler"), tracks: library.favorites)
            case .downloads: DownloadsView()
            case .recent: TrackListView(title: L("Son dinlenenler"), tracks: library.recent)
            case .albums: SavedAlbumsView()
            case .artists: FollowedArtistsView()
            }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
        .alert("Yeni çalma listesi", isPresented: $newList) {
            TextField("Liste adı", text: $listName)
            Button("Oluştur") { library.createPlaylist(listName) }
                .disabled(listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Vazgeç", role: .cancel) { }
        }
    }

    private var destinations: some View {
        VStack(spacing: 0) {
            Button { destination = .favorites } label: {
                LibraryLink(title: L("Favoriler"), symbol: "heart", count: library.favorites.count, color: .coral)
            }.accessibilityIdentifier("library.favorites")
            rowDivider
            Button { destination = .downloads } label: {
                LibraryLink(title: L("İndirilenler"), symbol: "arrow.down.circle", count: library.downloaded.count, color: .coral)
            }.accessibilityIdentifier("library.downloads")
            rowDivider
            Button { destination = .recent } label: {
                LibraryLink(title: L("Son dinlenenler"), symbol: "clock", count: library.recent.count, color: .coral)
            }.accessibilityIdentifier("library.recent")
            rowDivider
            Button { destination = .albums } label: {
                LibraryLink(title: L("Albümler"), symbol: "square.stack", count: nil, color: .coral)
            }.accessibilityIdentifier("library.albums")
            rowDivider
            Button { destination = .artists } label: {
                LibraryLink(title: L("Sanatçılar"), symbol: "person.2", count: nil, color: .coral)
            }.accessibilityIdentifier("library.artists")
        }.buttonStyle(.plain)
    }

    private var playlists: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Text("Çalma listelerin").font(.title2.bold()).tracking(-0.6)
                Spacer(minLength: 12)
                Button {
                    listName = ""; newList = true
                } label: {
                    Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.coral).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Yeni çalma listesi")
                .accessibilityIdentifier("playlist.create")
            }
            if library.playlists.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("İlk çalma listeni oluştur").font(.subheadline.weight(.medium))
                    Text("Sevdiğin şarkıları bir araya getir.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(library.playlists) { playlist in
                        NavigationLink { PlaylistDetailView(playlist: playlist) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                PlaylistArtwork(tracks: library.tracks(in: playlist)).aspectRatio(1, contentMode: .fit)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                    Text("\(playlist.trackIDs.count) şarkı").font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain)
                            .contextMenu { Button("Sil", role: .destructive) { library.deletePlaylist(playlist) } }
                    }
                }
            }
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(.primary.opacity(0.10)).frame(height: 0.5).padding(.leading, 42)
    }
}

private enum LibraryDestination: Hashable {
    case favorites, downloads, recent, albums, artists
}

struct LibraryLink: View {
    var title: String
    var symbol: String
    var count: Int?
    var color: Color
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                .foregroundStyle(color).frame(width: 30, height: 40).accessibilityHidden(true)
            Text(title).font(.system(size: 20)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let count, count > 0 {
                Text("\(count)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .frame(minHeight: 56).padding(.vertical, 2).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct PlaylistArtwork: View {
    var tracks: [Track]
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
                        Color.musicSurface
                        Image(systemName: "music.note.list")
                            .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.30, weight: .ultraLight))
                            .foregroundStyle(Color.coral)
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.accessibilityHidden(true)
    }
}

struct PlaylistPicker: View {
    var track: Track
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var name = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 14) {
                        Artwork(url: track.artwork, radius: 6).frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.title).font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.top, 12)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Yeni liste").font(.title3.weight(.bold))
                        TextField("Liste adı", text: $name).font(.body).padding(.vertical, 13)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.2)).frame(height: 1) }
                            .submitLabel(.done)
                        Button(action: createAndAdd) {
                            HStack {
                                Text("Oluştur ve ekle").font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "plus").font(.subheadline.weight(.semibold))
                            }.foregroundStyle(.white).padding(16).background(Color.coral, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    }
                    if !library.playlists.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Çalma listelerin").font(.title3.weight(.bold)).padding(.bottom, 8)
                            ForEach(library.playlists) { list in
                                Button { library.add(track, to: list); dismiss() } label: {
                                    HStack(spacing: 14) {
                                        PlaylistArtwork(tracks: library.tracks(in: list)).frame(width: 58, height: 58)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(list.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                            Text("\(list.trackIDs.count) şarkı").font(.caption).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: list.trackIDs.contains(track.id) ? "checkmark" : "plus")
                                            .font(.body.weight(.medium)).foregroundStyle(Color.coral).frame(width: 32, height: 44)
                                    }.padding(.vertical, 8).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Divider().padding(.leading, 72)
                            }
                        }
                    }
                }.padding(.horizontal, 22).padding(.bottom, 32)
            }.background(Color.canvas).navigationTitle("Listeye ekle").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } } }
        }.tint(.coral)
    }
    private func createAndAdd() {
        let existing = Set(library.playlists.map(\.id))
        library.createPlaylist(name)
        if let list = library.playlists.first(where: { !existing.contains($0.id) }) {
            library.add(track, to: list); dismiss()
        }
    }
}

struct PlaylistDetailView: View {
    @Bindable var playlist: SavedPlaylist
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var downloads: DownloadManager
    @State private var rename = false
    @State private var newName = ""
    var tracks: [Track] { library.tracks(in: playlist) }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 22) {
                    PlaylistArtwork(tracks: tracks).frame(width: 238, height: 238).shadow(color: .black.opacity(0.2), radius: 25, y: 15).frame(maxWidth: .infinity).padding(.vertical, 10)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Çalma listesi").font(.subheadline).foregroundStyle(.secondary)
                        Text(playlist.name).font(.title.bold()).tracking(-0.8).fixedSize(horizontal: false, vertical: true)
                        Text("\(tracks.count) şarkı · \(Track.time(tracks.reduce(0) { $0 + $1.duration }))").font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 16) {
                        Button { if let first = tracks.first { player.play(first, in: tracks) } } label: {
                            Label("Çal", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                                .foregroundStyle(.white).background(Color.coral, in: Capsule())
                        }.buttonStyle(.plain)
                        Button { tracks.forEach { downloads.enqueue($0) } } label: {
                            Image(systemName: "arrow.down").font(.system(size: 21, weight: .medium)).frame(width: 54, height: 54)
                                .foregroundStyle(.primary).overlay { Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1) }
                        }.buttonStyle(.plain).accessibilityLabel("Tümünü indir")
                    }.disabled(tracks.isEmpty).opacity(tracks.isEmpty ? 0.4 : 1)
                    Divider().padding(.top, 3)
                }.padding(.bottom, 10)
            }.listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20)).listRowSeparator(.hidden).listRowBackground(Color.clear)
            ForEach(tracks) { track in
                TrackRow(track: track, tracks: tracks).listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }.onMove { source, destination in playlist.trackIDs.move(fromOffsets: source, toOffset: destination); library.commit() }
                .onDelete { offsets in
                    let ids = Set(offsets.map { tracks[$0].id })
                    playlist.trackIDs.removeAll { ids.contains($0) }; library.commit()
                }
            if tracks.isEmpty {
                EmptyState(symbol: "text.badge.plus", title: "İlk şarkını ekle", message: "Bir şarkının seçeneklerinden bu listeye ekleyebilirsin.")
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(Color.canvas).navigationBarTitleDisplayMode(.inline).tint(.coral)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(tracks.isEmpty) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = playlist.name; rename = true } label: { Image(systemName: "pencil") }.accessibilityLabel("Yeniden adlandır")
                }
            }
            .alert("Yeniden adlandır", isPresented: $rename) {
                TextField("Liste adı", text: $newName)
                Button("Kaydet") {
                    let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { playlist.name = String(value.prefix(100)); library.commit() }
                }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Vazgeç", role: .cancel) { }
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
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(library.downloaded.count) şarkı").font(.title2.bold()).tracking(-0.5)
                            Text("Bağlantın olmasa da yanında.").font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if !library.downloaded.isEmpty {
                            Button { if let track = library.downloaded.first { player.play(track, in: library.downloaded) } } label: {
                                Image(systemName: "play.fill").font(.system(size: 22, weight: .semibold)).offset(x: 2)
                                    .foregroundStyle(.white).frame(width: 58, height: 58).background(Color.coral, in: Circle())
                            }.buttonStyle(.plain).accessibilityLabel("Çevrimdışı çal")
                        }
                    }.padding(.top, 12).padding(.bottom, 18)
                }.listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)).listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            if !downloads.jobs.isEmpty {
                Section {
                    ForEach(Array(downloads.jobs.keys).sorted(), id: \.self) { id in
                        if let job = downloads.jobs[id], let track = library.saved.first(where: { $0.id == id })?.track {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Artwork(url: track.artwork, radius: 5).frame(width: 52, height: 52)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                        Text(job.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    if !typeSize.isAccessibilitySize { jobControls(id: id, track: track, canRetry: job.failed || job.paused) }
                                }
                                if typeSize.isAccessibilitySize {
                                    HStack { Spacer(); jobControls(id: id, track: track, canRetry: job.failed || job.paused) }
                                }
                                ProgressView(value: job.progress).tint(.coral)
                            }.padding(.vertical, 12).listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        }
                    }
                } header: { Text("İndirme sırası").font(.headline).foregroundStyle(.primary).textCase(nil).padding(.bottom, 8) }
                    .listRowBackground(Color.clear)
            }
            if !library.downloaded.isEmpty {
                Section {
                    ForEach(library.downloaded) { track in
                        TrackRow(track: track, tracks: library.downloaded).listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .swipeActions { Button("Sil", role: .destructive) { library.removeDownload(track) } }
                    }
                } header: { Text("Bu cihazda").font(.headline).foregroundStyle(.primary).textCase(nil).padding(.vertical, 8) }
                    .listRowBackground(Color.clear)
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("İndirilenler")
            .overlay {
                if library.downloaded.isEmpty && downloads.jobs.isEmpty {
                    EmptyState(symbol: "arrow.down.circle", title: "Müziğin yanında olsun", message: "Şarkıları indir, internet olmadan dinle.")
                }
            }
            .toolbar {
                if !library.downloaded.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }.accessibilityLabel("İndirilenleri sil")
                    }
                }
            }
            .confirmationDialog("Tüm indirilen şarkılar silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("İndirilenleri sil", role: .destructive) { library.downloaded.forEach { library.removeDownload($0) } }
            }
    }
    private func jobControls(id: String, track: Track, canRetry: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                if canRetry { downloads.enqueue(track) } else { downloads.pause(id) }
            } label: {
                Image(systemName: canRetry ? "arrow.clockwise" : "pause.fill").font(.subheadline).frame(width: 40, height: 44)
            }.accessibilityLabel(canRetry ? "Yeniden dene" : "Duraklat")
            Button { downloads.cancel(id) } label: {
                Image(systemName: "xmark").font(.subheadline).frame(width: 40, height: 44)
            }.accessibilityLabel("İptal")
        }.buttonStyle(.borderless).foregroundStyle(Color.coral)
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
            VStack(alignment: .leading, spacing: 22) {
                if !albums.isEmpty { Text("\(albums.count) albüm").font(.subheadline).foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 140), spacing: 16, alignment: .top)], alignment: .leading, spacing: 26) {
                    ForEach(albums) { album in
                        NavigationLink {
                            TrackListView(title: album.title, tracks: library.saved.compactMap(\.track).filter { $0.albumID == album.id })
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Artwork(url: album.artwork, radius: 18).aspectRatio(1, contentMode: .fit)
                                Text(album.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
        }.background(Color.canvas).navigationTitle("Albümler")
            .overlay { if albums.isEmpty { EmptyState(symbol: "square.stack", title: "Albümlerin burada", message: "Kaydettiğin şarkıların albümleri burada görünecek.") } }
    }
}

struct FollowedArtistsView: View {
    @AppStorage("followedArtists") private var followed = ""
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    var artists: [(String, String)] {
        followed.components(separatedBy: "\n").compactMap { value in
            let parts = value.split(separator: "|", maxSplits: 1)
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !artists.isEmpty { Text("\(artists.count) sanatçı takip ediliyor").font(.subheadline).foregroundStyle(.secondary).padding(.bottom, 20) }
                ForEach(artists, id: \.0) { artist in
                    NavigationLink { ArtistDetailView(id: artist.0, name: artist.1) } label: {
                        HStack(spacing: 16) {
                            if let art = library.saved.compactMap(\.track).first(where: { $0.artistID == artist.0 })?.artwork {
                                Artwork(url: art, radius: 32).frame(width: 64, height: 64)
                            } else {
                                Text(String(artist.1.prefix(1))).font(.system(size: 27, weight: .medium)).frame(width: 64, height: 64)
                                    .foregroundStyle(Color.coral).overlay { Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1) }
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(artist.1).font(.headline).foregroundStyle(.primary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                Text("Takip ediliyor").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.right").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 14).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider().padding(.leading, 80)
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
        }.background(Color.canvas).navigationTitle("Sanatçılar")
            .overlay { if artists.isEmpty { EmptyState(symbol: "person.2", title: "Sevdiğin sesleri takip et", message: "Sanatçı sayfalarından takip ettiğin isimler burada görünecek.") } }
    }
}
