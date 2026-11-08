import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: MusicPlayer
    @State private var sections: [HomeSection] = []
    @State private var personal: [HomeSection] = []
    @State private var loading = true
    @State private var failure: String?
    private var seeds: [Track] {
        var seen = Set<String>()
        return Array((library.favorites + library.recent).filter { seen.insert($0.id).inserted }.prefix(24))
    }
    private var seedKey: String {
        var artists = Set<String>()
        return seeds.filter { artists.insert(NativeCatalog.normalized($0.artist)).inserted }.prefix(4).map(\.artist).joined(separator: "|")
    }
    private var recommendations: [Track] { HomeFeed.interleaved(HomeFeed.distinct(personal, excluding: seeds)) }
    private var featured: [Track] {
        if !recommendations.isEmpty { return recommendations }
        return Array(HomeFeed.distinct(sections, excluding: library.recent).first?.tracks.prefix(5) ?? [])
    }
    private var remaining: [HomeSection] { HomeFeed.distinct(sections, excluding: featured + library.recent) }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                if loading && sections.isEmpty { MusicLoadingView() }
                if !featured.isEmpty {
                    BrowseTrackShelf(title: recommendations.isEmpty ? "Öne çıkanlar" : "Senin için",
                                     subtitle: recommendations.isEmpty ? nil : "Dinlediklerinden yola çıkarak", tracks: featured, large: true)
                        .accessibilityIdentifier(recommendations.isEmpty ? "home.featured" : "home.personalized")
                }
                if !library.recent.isEmpty { CompactTrackShelf(title: "Son dinlenenler", tracks: Array(library.recent.prefix(9))) }
                ForEach(Array(remaining.enumerated()), id: \.element.id) { index, section in
                    if index == 0 { CompactTrackShelf(title: section.title, tracks: section.tracks) }
                    else { BrowseTrackShelf(title: section.title, subtitle: section.subtitle, tracks: section.tracks) }
                }
                if let failure, sections.isEmpty { ErrorState(message: failure) { Task { await load() } }.padding(.horizontal, 20) }
            }.padding(.top, 8).padding(.bottom, 24)
        }.background(Color.pageBackground).navigationTitle("Dinle").navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
            .task(id: ListeningLocale.current.cacheKey + "|" + seedKey) { await load() }.refreshable { await load() }
    }
    private func load() async {
        loading = sections.isEmpty; failure = nil
        defer { loading = false }
        do {
            sections = try await API.shared.home().sections
            if seeds.isEmpty { personal = [] }
            else { personal = (try? await API.shared.recommendations(for: seeds).sections) ?? [] }
            player.warm(featured)
        } catch is CancellationError { }
        catch { failure = error.localizedDescription }
    }
}

private struct CompactTrackShelf: View {
    var title: String
    var tracks: [Track]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BrowseShelfHeading(title: title, tracks: tracks)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 24) {
                    ForEach(0..<((min(tracks.count, 12) + 2) / 3), id: \.self) { column in
                        VStack(spacing: 0) {
                            ForEach(Array(tracks.dropFirst(column * 3).prefix(3))) { track in
                                TrackRow(track: track, tracks: tracks)
                                Divider().padding(.leading, 67)
                            }
                        }.frame(width: 302)
                    }
                }.padding(.horizontal, 20).scrollTargetLayout()
            }.scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct BrowseShelfHeading: View {
    var title: String
    var caption: String? = nil
    var tracks: [Track]? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(L(title)).font(.title2.bold()).tracking(-0.5)
                if let tracks {
                    NavigationLink { TrackListView(title: title, tracks: tracks) } label: {
                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.tertiary).padding(.trailing, 14).padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }.accessibilityLabel("Tümünü göster")
                }
                Spacer(minLength: 0)
            }
            if let caption, !caption.isEmpty { Text(L(caption)).font(.subheadline).foregroundStyle(.secondary) }
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

struct DiscoverView: View {
    @State private var sections: [HomeSection] = []
    @State private var failure: String?
    @EnvironmentObject private var player: MusicPlayer
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                if let first = sections.first { BrowseTrackShelf(title: "Öne çıkanlar", tracks: Array(first.tracks.prefix(5)), large: true) }
                ForEach(HomeFeed.distinct(sections, excluding: Array(sections.first?.tracks.prefix(5) ?? []))) { section in
                    BrowseTrackShelf(title: section.title, tracks: section.tracks)
                }
                VStack(alignment: .leading, spacing: 12) {
                    BrowseShelfHeading(title: "Türler ve ruh halleri")
                    CategoryGrid()
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

private struct CategoryGrid: View {
    @State private var categories: [BrowseCategory] = []
    @State private var failed = false
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(categories) { category in
                NavigationLink { QueryView(query: category.query, title: category.title) } label: {
                    ZStack(alignment: .bottomLeading) {
                        Artwork(url: category.artwork, radius: 0)
                        LinearGradient(colors: [.clear, .black.opacity(0.36)], startPoint: .center, endPoint: .bottom)
                        Text(category.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).padding(12)
                    }.frame(height: 116).clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).accessibilityIdentifier("search.category.\(category.id)")
            }
        }.padding(.horizontal, 20)
            .overlay { if failed && categories.isEmpty { Text("Kategoriler yüklenemedi").font(.footnote).foregroundStyle(.secondary) } }
            .task(id: ListeningLocale.current.cacheKey) {
                do { categories = try await API.shared.categories(); failed = false }
                catch { if !Task.isCancelled { failed = true } }
            }
    }
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
    @State private var searchActive = false
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    @AppStorage("searchHistory") private var historyData = ""
    private var history: [String] { historyData.components(separatedBy: "\n").filter { !$0.isEmpty } }
    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var songs: [Track] {
        scope == "library" ? library.saved.compactMap(\.track).filter { NativeCatalog.normalized($0.title + " " + $0.artist + " " + $0.album).contains(NativeCatalog.normalized(query)) } : result.tracks
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if !hasQuery {
                    if searchActive && !history.isEmpty { recentSearches.padding(.horizontal, 20) }
                    else {
                        BrowseShelfHeading(title: "Kategorilere göz at")
                        CategoryGrid()
                    }
                } else {
                    if scope == "catalog" { filters }
                    if loading && scope == "catalog" { ProgressView().frame(maxWidth: .infinity).padding(30) }
                    else if let failure, scope == "catalog" { ErrorState(message: failure) { Task { await search() } } }
                    else {
                        if scope == "catalog", (filter == "albums" && result.albums.isEmpty) || (filter == "artists" && result.artists.isEmpty) { noResults }
                        else { searchResults }
                    }
                }
            }.padding(.top, 8).padding(.bottom, 28)
        }.background(Color.pageBackground).navigationTitle("Ara").navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, isPresented: $searchActive, prompt: "Sanatçılar, Şarkılar, Sözler ve Daha Fazlası")
            .searchScopes($scope, activation: .onTextEntry) {
                Text("KlyMusic").tag("catalog"); Text("Kitaplığın").tag("library")
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
            .scrollDismissesKeyboard(.interactively)
            .task(id: scope + "|" + query) {
                guard hasQuery else { result = SearchResponse(); loading = false; failure = nil; return }
                guard scope == "catalog" else { loading = false; failure = nil; return }
                loading = true; failure = nil
                do { try await Task.sleep(for: .milliseconds(200)); try Task.checkCancellation(); await search() } catch { }
            }.onSubmit(of: .search) { saveHistory() }
    }
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton("Tümü", value: "all")
                filterButton("Şarkılar", value: "songs")
                filterButton("Albümler", value: "albums")
                filterButton("Sanatçılar", value: "artists")
            }.padding(.horizontal, 20)
        }.accessibilityIdentifier("search.filters")
    }
    private func filterButton(_ title: String, value: String) -> some View {
        Button { filter = value } label: {
            Text(L(title)).font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 10)
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
        if scope == "library" || filter == "songs" { if songs.isEmpty { noResults } else { trackRows(songs) } }
        else if filter == "all" {
            if songs.isEmpty && result.artists.isEmpty && result.albums.isEmpty { noResults }
            else {
                VStack(spacing: 0) {
                    ForEach(Array(songs.prefix(3))) { track in
                        TrackRow(track: track, tracks: songs)
                        Divider().padding(.leading, 67)
                    }
                    ForEach(Array(result.artists.prefix(2))) { artistRow($0) }
                    ForEach(Array(result.albums.prefix(2))) { albumRow($0) }
                    ForEach(Array(songs.dropFirst(3))) { track in
                        TrackRow(track: track, tracks: songs)
                        Divider().padding(.leading, 67)
                    }
                }.padding(.horizontal, 20)
            }
        } else if filter == "albums" {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 24) {
                ForEach(result.albums) { album in
                    NavigationLink { AlbumDetailView(collection: album) } label: { AlbumCard(collection: album) }
                        .buttonStyle(.plain).accessibilityIdentifier("album.open.\(album.id)")
                }
            }.padding(.horizontal, 20)
        } else if filter == "artists" {
            VStack(spacing: 0) { ForEach(result.artists) { artistRow($0) } }.padding(.horizontal, 20)
        }
    }
    private func artistRow(_ artist: MusicArtist) -> some View {
        VStack(spacing: 0) {
            NavigationLink { ArtistDetailView(id: artist.id, name: artist.name) } label: {
                HStack(spacing: 14) {
                    ArtistPortrait(url: artist.artwork, name: artist.name).frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artist.name).font(.body).foregroundStyle(.primary)
                        Text("Sanatçı").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.vertical, 7)
            }.buttonStyle(.plain).accessibilityIdentifier("artist.open.\(artist.id)")
            Divider().padding(.leading, 67)
        }
    }
    private func albumRow(_ album: MusicCollection) -> some View {
        VStack(spacing: 0) {
            NavigationLink { AlbumDetailView(collection: album) } label: {
                HStack(spacing: 14) {
                    Artwork(url: album.artwork, radius: 5).frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(album.title).font(.body).foregroundStyle(.primary).lineLimit(1)
                        Text("Albüm · " + album.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }.padding(.vertical, 7)
            }.buttonStyle(.plain).accessibilityIdentifier("album.open.\(album.id)")
            Divider().padding(.leading, 67)
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
    @State private var compactTitle = false
    @EnvironmentObject private var player: MusicPlayer
    @AppStorage("followedArtists") private var followed = ""
    private var isFollowing: Bool { followed.split(separator: "\n").contains { $0.split(separator: "|", maxSplits: 1).first == Substring(id) } }
    private var artwork: String? { details?.artist.banner ?? details?.artist.artwork }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 27) {
                VStack(spacing: 16) {
                    if let artwork {
                        ZStack(alignment: .bottom) {
                            Artwork(url: artwork, radius: 0).frame(height: 320).clipped()
                            LinearGradient(colors: [.clear, Color.pageBackground], startPoint: .center, endPoint: .bottom)
                            artistName.padding(.bottom, 10)
                        }
                    } else {
                        VStack(spacing: 18) {
                            ArtistPortrait(url: nil, name: name).frame(width: 128, height: 128)
                            artistName
                        }.frame(maxWidth: .infinity).padding(.vertical, 26)
                    }
                    if let tracks = details?.tracks { CollectionPlayButtons(tracks: tracks).padding(.horizontal, 20) }
                }
                if let details { artistContent(details) }
                else if let failure { ErrorState(message: failure) { Task { await load() } }.padding(.horizontal, 22) }
                else { ProgressView().frame(maxWidth: .infinity).padding(40) }
            }.padding(.bottom, 32)
        }.coordinateSpace(name: "artistScroll")
            .background(Color.pageBackground).navigationTitle(compactTitle ? name : "").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: toggleFollow) { Image(systemName: isFollowing ? "star.fill" : "star") }
                        .foregroundStyle(.primary).accessibilityLabel(isFollowing ? "Takibi bırak" : "Takip et")
                }
            }.task { await load() }
    }
    private var artistName: some View {
        Text(details?.artist.name ?? name).font(.system(size: 34, weight: .bold))
            .multilineTextAlignment(.center).padding(.horizontal, 20).frame(maxWidth: .infinity)
            .onGeometryChange(for: Bool.self) { geometry in
                geometry.frame(in: .named("artistScroll")).maxY < 0
            } action: { compactTitle = $0 }
    }
    private func artistContent(_ details: ArtistResponse) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            if let release = details.featured ?? details.albums.first {
                NavigationLink { AlbumDetailView(collection: release) } label: {
                    HStack(spacing: 16) {
                        Artwork(url: release.artwork, radius: 7).frame(width: 112, height: 112)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(L(release.releaseLabel)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(release.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                            Text(release.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            if let date = release.releaseDate { Text(String(date.prefix(4))).font(.footnote).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }.padding(12).background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).padding(.horizontal, 20).accessibilityIdentifier("artist.latest")
            }

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
