import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: MusicPlayer
    @State private var sections: [HomeSection] = []
    @State private var loading = true
    @State private var failure: String?
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                if loading && sections.isEmpty { MusicLoadingView() }
                if let first = sections.first {
                    BrowseTrackShelf(title: "Senin için", tracks: first.tracks, large: true)
                }
                if !library.recent.isEmpty { BrowseTrackShelf(title: "Son dinlenenler", tracks: Array(library.recent.prefix(12))) }
                ForEach(sections) { section in
                    BrowseTrackShelf(title: section.title, subtitle: section.subtitle, tracks: section.tracks)
                }
                if let failure, sections.isEmpty { ErrorState(message: failure) { Task { await load() } }.padding(.horizontal, 20) }
            }.padding(.top, 8).padding(.bottom, 24)
        }.background(Color.pageBackground).navigationTitle("Dinle").navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
            .task(id: ListeningLocale.current.cacheKey) { await load() }.refreshable { await load() }
    }
    private func load() async {
        loading = sections.isEmpty; failure = nil
        defer { loading = false }
        do { sections = try await API.shared.home().sections; player.warm(sections.first?.tracks ?? []) }
        catch is CancellationError { }
        catch { failure = error.localizedDescription }
    }
}

private struct BrowseShelfHeading: View {
    var title: String
    var caption: String? = nil
    var tracks: [Track]? = nil
    var body: some View {
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L(title)).font(.title2.bold()).tracking(-0.5)
                if let caption, !caption.isEmpty { Text(L(caption)).font(.subheadline).foregroundStyle(.secondary) }
            }
            if let tracks {
                NavigationLink { TrackListView(title: title, tracks: tracks) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(.tertiary).frame(width: 30, height: 40)
                }.accessibilityLabel("Tümünü göster")
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 20)
    }
}

private struct BrowseTrackShelf: View {
    var title: String
    var subtitle: String? = nil
    var tracks: [Track]
    var large = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrowseShelfHeading(title: title, caption: subtitle, tracks: tracks)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(tracks.prefix(14)) { TrackCard(track: $0, tracks: tracks, size: large ? 260 : 164) }
                }.scrollTargetLayout().padding(.horizontal, 20)
            }.scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct MusicMood: Identifiable {
    var id: String { query }
    var title: String
    var query: String
    var color: Color
    static let all: [MusicMood] = [
        .init(title: "Türkçe Pop", query: "Türkçe Pop", color: .orange),
        .init(title: "Türkçe Rap", query: "Türkçe Rap", color: .purple),
        .init(title: "Pop", query: "pop", color: .pink),
        .init(title: "Hip-Hop", query: "hip hop", color: .blue),
        .init(title: "Alternatif", query: "alternative", color: .green),
        .init(title: "Rock", query: "rock", color: .red),
        .init(title: "Akustik", query: "acoustic", color: .brown),
        .init(title: "Sakin", query: "chill", color: .indigo),
        .init(title: "Jazz", query: "jazz", color: .teal),
        .init(title: "Klasik", query: "classical", color: .purple),
        .init(title: "Dans", query: "dance", color: .pink),
        .init(title: "Odaklan", query: "lofi", color: .blue)
    ]
}

struct DiscoverView: View {
    @State private var sections: [HomeSection] = []
    @State private var failure: String?
    @EnvironmentObject private var player: MusicPlayer
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                if let first = sections.first {
                    BrowseTrackShelf(title: "Öne çıkanlar", tracks: first.tracks, large: true)
                }
                ForEach(sections) { section in
                    BrowseTrackShelf(title: section.title, tracks: section.tracks)
                }
                VStack(alignment: .leading, spacing: 12) {
                    BrowseShelfHeading(title: "Türler ve ruh halleri")
                    categoryGrid(tracks: sections.flatMap(\.tracks))
                }
                if let failure, sections.isEmpty { ErrorState(message: failure) { Task { await load() } }.padding(.horizontal, 20) }
            }.padding(.top, 8).padding(.bottom, 24)
        }.background(Color.pageBackground).navigationTitle("Keşfet").navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
            .task(id: ListeningLocale.current.cacheKey) { await load() }.refreshable { await load() }
    }
    private func load() async {
        failure = nil
        do { sections = try await API.shared.home().sections; player.warm(sections.first?.tracks ?? []) }
        catch is CancellationError { }
        catch { failure = error.localizedDescription }
    }
}

@ViewBuilder private func categoryGrid(tracks: [Track]) -> some View {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
        ForEach(Array(MusicMood.all.enumerated()), id: \.element.id) { index, mood in
            NavigationLink { QueryView(query: mood.query, title: L(mood.title)) } label: {
                ZStack(alignment: .bottomLeading) {
                    mood.color
                    if !tracks.isEmpty {
                        Artwork(url: tracks[index % tracks.count].artwork, radius: 0)
                            .opacity(0.48).blendMode(.luminosity)
                    }
                    Text(L(mood.title)).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        .padding(12).shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                }.frame(height: 116).clipShape(RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).accessibilityIdentifier("search.category.\(mood.id)")
        }
    }.padding(.horizontal, 20)
}

struct QueryView: View {
    var query: String
    var title: String
    @State private var result = SearchResponse()
    @State private var loading = true
    @State private var failure: String?
    @EnvironmentObject private var player: MusicPlayer
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !result.tracks.isEmpty { CollectionPlayButtons(tracks: result.tracks).padding(.horizontal, 20) }
                if loading { ProgressView().padding(40) }
                else if let failure { ErrorState(message: failure) { Task { await load() } } }
                else if result.tracks.isEmpty { EmptyState(symbol: "music.note", title: "Sonuç bulunamadı", message: "Farklı bir arama dene.") }
                trackRows(result.tracks)
            }.padding(.top, 12).padding(.bottom, 24)
        }.background(Color.pageBackground).navigationTitle(title).task { await load() }
    }
    private func load() async {
        loading = true; failure = nil
        defer { loading = false }
        do { result = try await API.shared.search(query); player.warm(result.tracks) }
        catch is CancellationError { }
        catch { failure = error.localizedDescription }
    }
}

struct SearchView: View {
    @State private var query = ""
    @State private var result = SearchResponse()
    @State private var loading = false
    @State private var failure: String?
    @State private var filter = "all"
    @State private var scope = "catalog"
    @State private var suggestions: [Track] = []
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    @AppStorage("searchHistory") private var historyData = ""
    private var history: [String] { historyData.components(separatedBy: "\n").filter { !$0.isEmpty } }
    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var songs: [Track] {
        scope == "library" ? library.saved.compactMap(\.track).filter { ($0.title + " " + $0.artist + " " + $0.album).localizedCaseInsensitiveContains(query) } : result.tracks
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if !hasQuery {
                    if !history.isEmpty { recentSearches.padding(.horizontal, 20) }
                    BrowseShelfHeading(title: "Kategorilere göz at")
                    categoryGrid(tracks: suggestions)
                } else {
                    Picker("Arama kapsamı", selection: $scope) {
                        Text("KlyMusic").tag("catalog"); Text("Kitaplığın").tag("library")
                    }.pickerStyle(.segmented).padding(.horizontal, 20).accessibilityIdentifier("search.scope")
                    if scope == "catalog" { filters }
                    if loading && scope == "catalog" { ProgressView().frame(maxWidth: .infinity).padding(30) }
                    else if let failure, scope == "catalog" { ErrorState(message: failure) { Task { await search() } } }
                    else { searchResults }
                }
            }.padding(.top, 8).padding(.bottom, 28)
        }.background(Color.pageBackground).navigationTitle("Ara").navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "Sanatçılar, Şarkılar, Sözler ve Daha Fazlası")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
            .scrollDismissesKeyboard(.interactively)
            .task(id: ListeningLocale.current.cacheKey) { suggestions = (try? await API.shared.home().sections.first?.tracks) ?? [] }
            .task(id: query) {
                guard hasQuery else { result = SearchResponse(); loading = false; failure = nil; return }
                loading = true; failure = nil
                do { try await Task.sleep(for: .milliseconds(200)); try Task.checkCancellation(); await search() } catch { }
            }.onSubmit(of: .search) { saveHistory() }
    }
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton("En iyi sonuçlar", value: "all")
                filterButton("Şarkılar", value: "songs")
                filterButton("Albümler", value: "albums")
                filterButton("Sanatçılar", value: "artists")
            }.padding(.horizontal, 20)
        }.accessibilityIdentifier("search.filters")
    }
    private func filterButton(_ title: String, value: String) -> some View {
        Button { filter = value } label: {
            Text(L(title)).font(.system(size: 14, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 9)
                .foregroundStyle(filter == value ? Color.pageBackground : Color.primary)
                .background(filter == value ? Color.primary : Color.musicElevated, in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("search.filter.\(value)")
            .accessibilityAddTraits(filter == value ? .isSelected : [])
    }
    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Son Aramalar").font(.title2.bold())
                Spacer()
                Button("Temizle") { historyData = "" }.font(.subheadline).foregroundStyle(.secondary)
            }.padding(.bottom, 8)
            ForEach(history.prefix(5), id: \.self) { term in
                Button { query = term } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        Text(term).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, 11).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider().padding(.leading, 34)
            }
        }
    }
    @ViewBuilder private var searchResults: some View {
        if scope == "library" || filter == "songs" || filter == "all" {
            if filter == "all", scope == "catalog", let first = songs.first {
                VStack(alignment: .leading, spacing: 12) {
                    Text("En İyi Sonuç").font(.title2.bold())
                    Button { player.play(first, in: songs) } label: {
                        VStack(spacing: 12) {
                            Artwork(url: first.artwork, radius: 7).frame(width: 112, height: 112)
                            Text(first.title).font(.headline).lineLimit(1)
                            Text(first.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity).padding(20).background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityIdentifier("search.topResult")
                }.padding(.horizontal, 20)
            }
            if songs.isEmpty { noResults }
            else {
                VStack(alignment: .leading, spacing: 10) {
                    if filter == "all" { Text("Şarkılar").font(.title2.bold()).padding(.horizontal, 20) }
                    trackRows(songs)
                }
            }
        }
        if scope == "catalog", filter == "albums" || (filter == "all" && !result.albums.isEmpty) {
            VStack(alignment: .leading, spacing: 12) {
                if filter == "all" { Text("Albümler").font(.title2.bold()) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 24) {
                    ForEach(result.albums) { album in
                        NavigationLink { AlbumDetailView(collection: album) } label: { AlbumCard(collection: album) }.buttonStyle(.plain).accessibilityIdentifier("album.open.\(album.id)")
                    }
                }
            }.padding(.horizontal, 20)
        }
        if scope == "catalog", filter == "artists" || (filter == "all" && !result.artists.isEmpty) {
            VStack(alignment: .leading, spacing: 0) {
                if filter == "all" { Text("Sanatçılar").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12) }
                ForEach(result.artists) { artist in
                    NavigationLink { ArtistDetailView(id: artist.id, name: artist.name) } label: {
                        HStack(spacing: 14) {
                            Artwork(url: artist.artwork, radius: 28).frame(width: 56, height: 56)
                            Text(artist.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }.padding(.vertical, 8)
                    }.buttonStyle(.plain).accessibilityIdentifier("artist.open.\(artist.id)")
                    Divider().padding(.leading, 70)
                }
            }.padding(.horizontal, 20)
        }
    }
    private var noResults: some View { EmptyState(symbol: "magnifyingglass", title: "Sonuç bulunamadı", message: "Farklı bir şarkı veya sanatçı adıyla tekrar dene.") }
    private func saveHistory() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        historyData = ([value] + history.filter { $0 != value }).prefix(8).joined(separator: "\n")
    }
    private func search() async {
        let requested = query
        loading = true; failure = nil
        do {
            let response = try await API.shared.search(requested)
            try Task.checkCancellation()
            guard requested == query else { return }
            result = response; player.warm(response.tracks); saveHistory()
        } catch is CancellationError { return }
        catch { guard requested == query, !Task.isCancelled else { return }; failure = error.localizedDescription }
        loading = false
    }
}

@ViewBuilder private func trackRows(_ tracks: [Track]) -> some View {
    LazyVStack(spacing: 0) {
        ForEach(tracks) { track in
            TrackRow(track: track, tracks: tracks)
            Divider().padding(.leading, 67)
        }
    }.padding(.horizontal, 20)
}

private struct AlbumCard: View {
    var collection: MusicCollection
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Artwork(url: collection.artwork, radius: 7).aspectRatio(1, contentMode: .fit)
            Text(collection.title).font(.system(size: 14, weight: .semibold)).lineLimit(2).foregroundStyle(.primary)
            Text(collection.artist).font(.system(size: 12)).lineLimit(1).foregroundStyle(.secondary)
        }
    }
}

struct AlbumDetailView: View {
    var collection: MusicCollection
    @State private var tracks: [Track] = []
    @State private var failure: String?
    @State private var loading = true
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var downloads: DownloadManager
    private var totalDuration: String { String(format: L("%lld dakika"), Int64(tracks.reduce(0) { $0 + $1.duration } / 60)) }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                CollectionCoverHeader(artwork: collection.artwork, eyebrow: "ALBÜM", title: collection.title, subtitle: collection.artist)
                CollectionPlayButtons(tracks: tracks).padding(.horizontal, 20)
                if !tracks.isEmpty {
                    Text("\(tracks.count) şarkı · " + totalDuration).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
                }
                if loading { ProgressView().frame(maxWidth: .infinity).padding(30) }
                if let failure { ErrorState(message: failure) { Task { await load() } }.padding(.horizontal, 22) }
                LazyVStack(spacing: 2) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in TrackRow(track: track, tracks: tracks, number: index + 1) }
                }.padding(.horizontal, 22)
            }.padding(.bottom, 32)
        }.background(Color.pageBackground).navigationTitle(collection.title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar).task { await load() }
    }
    private func load() async {
        loading = true; failure = nil
        defer { loading = false }
        do { tracks = try await API.shared.album(collection.id).tracks }
        catch is CancellationError { }
        catch { failure = error.localizedDescription }
    }
}

private struct CollectionCoverHeader: View {
    var artwork: String?
    var eyebrow: String
    var title: String
    var subtitle: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 18) {
            Artwork(url: artwork, radius: 9)
                .frame(width: typeSize.isAccessibilitySize ? 190 : 248, height: typeSize.isAccessibilitySize ? 190 : 248)
                .padding(.bottom, 5)
            VStack(spacing: 7) {
                Text(title).font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center)
                if let subtitle { Text(subtitle).font(.system(size: 18)).foregroundStyle(.primary).multilineTextAlignment(.center) }
            }.frame(maxWidth: .infinity)
        }.padding(.horizontal, 22).padding(.top, 16)
    }
}

struct ArtistDetailView: View {
    var id: String
    var name: String
    @State private var details: ArtistResponse?
    @State private var failure: String?
    @EnvironmentObject private var player: MusicPlayer
    @AppStorage("followedArtists") private var followed = ""
    private var isFollowing: Bool { followed.split(separator: "\n").contains { $0.split(separator: "|", maxSplits: 1).first == Substring(id) } }
    private var artwork: String? { details?.artist.banner ?? details?.artist.artwork ?? details?.tracks.first?.artwork }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 27) {
                VStack(spacing: 16) {
                    ZStack(alignment: .bottom) {
                        Artwork(url: artwork, radius: 0).frame(height: 300).clipped()
                        LinearGradient(colors: [.clear, Color.pageBackground], startPoint: .center, endPoint: .bottom)
                        Text(details?.artist.name ?? name).font(.system(size: 34, weight: .bold))
                            .multilineTextAlignment(.center).padding(.horizontal, 20).padding(.bottom, 12)
                    }
                    HStack(spacing: 12) {
                        if let tracks = details?.tracks { CollectionPlayButtons(tracks: tracks) }
                        Button(action: toggleFollow) {
                            Image(systemName: isFollowing ? "star.fill" : "star").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
                                .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).foregroundStyle(.primary).accessibilityLabel(isFollowing ? "Takibi bırak" : "Takip et")
                    }.padding(.horizontal, 20)
                }
                if let details { artistContent(details) }
                else if let failure { ErrorState(message: failure) { Task { await load() } }.padding(.horizontal, 22) }
                else { ProgressView().frame(maxWidth: .infinity).padding(40) }
            }.padding(.bottom, 32)
        }.background(Color.pageBackground).navigationTitle(name).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar).task { await load() }
    }
    private func artistContent(_ details: ArtistResponse) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 14) {
                BrowseShelfHeading(title: "En çok dinlenenler")
                LazyVStack(spacing: 2) {
                    ForEach(Array(details.tracks.prefix(10).enumerated()), id: \.element.id) { index, track in TrackRow(track: track, tracks: details.tracks, number: index + 1) }
                }.padding(.horizontal, 22)
            }
            if !details.albums.isEmpty {
                VStack(alignment: .leading, spacing: 17) {
                    BrowseShelfHeading(title: "Albümler")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(details.albums) { album in
                                NavigationLink { AlbumDetailView(collection: album) } label: { AlbumCard(collection: album).frame(width: 154) }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 22)
                    }
                }
            }
        }
    }
    private func toggleFollow() {
        let value = id + "|" + name
        var values = followed.components(separatedBy: "\n").filter { !$0.isEmpty && $0.split(separator: "|", maxSplits: 1).first != Substring(id) }
        if !isFollowing { values.append(value) }
        followed = values.joined(separator: "\n")
    }
    private func load() async {
        failure = nil
        do { details = try await API.shared.artist(id) }
        catch is CancellationError { }
        catch { failure = error.localizedDescription }
    }
}
