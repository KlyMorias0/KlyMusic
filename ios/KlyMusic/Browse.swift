import SwiftUI

struct DynamicStyle: Codable {
    var heroHeight: CGFloat = 180
    var heroCornerRadius: CGFloat = 18
    var heroTag: String = "Öne çıkan"
    var quickLaunchGridCount: Int = 6
    var tileCornerRadius: CGFloat = 10
    var cardCornerRadius: CGFloat = 10
    var sectionSpacing: CGFloat = 30
    var accentHex: String = "E87D73"
}

final class DynamicUIConfig: ObservableObject {
    static let shared = DynamicUIConfig()
    @Published var style = DynamicStyle()

    private let configURL = URL(string: "https://raw.githubusercontent.com/KlyMorias0/KlyMusic/main/config/ui_layout.json")

    init() {
        loadCached()
    }

    func fetchRemote() async {
        guard let configURL else { return }
        do {
            var request = URLRequest(url: configURL)
            request.timeoutInterval = 3
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            let decoded = try JSONDecoder().decode(DynamicStyle.self, from: data)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.style = decoded
                }
                UserDefaults.standard.set(data, forKey: "klymusic_cached_dynamic_style")
            }
        } catch { }
    }

    private func loadCached() {
        if let data = UserDefaults.standard.data(forKey: "klymusic_cached_dynamic_style"),
           let cached = try? JSONDecoder().decode(DynamicStyle.self, from: data) {
            style = cached
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: MusicPlayer
    @ObservedObject private var uiConfig = DynamicUIConfig.shared
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
            VStack(alignment: .leading, spacing: uiConfig.style.sectionSpacing) {
                if loading && sections.isEmpty { MusicLoadingView() }
                if !featured.isEmpty {
                    HomeSpotlightShelf(title: recommendations.isEmpty ? "Öne çıkanlar" : "Senin için",
                                       subtitle: recommendations.isEmpty ? nil : "Dinlediklerinden yola çıkarak", tracks: featured)
                        .accessibilityIdentifier(recommendations.isEmpty ? "home.featured" : "home.personalized")
                }
                if !library.recent.isEmpty {
                    HomeQuickLaunchShelf(title: "Son dinlenenler", tracks: Array(library.recent.prefix(uiConfig.style.quickLaunchGridCount)))
                }
                ForEach(Array(remaining.enumerated()), id: \.element.id) { index, section in
                    if index == 0 && section.tracks.count >= 4 {
                        HomeQuickLaunchShelf(title: section.title, tracks: Array(section.tracks.prefix(uiConfig.style.quickLaunchGridCount)))
                    } else {
                        BrowseTrackShelf(title: section.title, subtitle: section.subtitle, tracks: section.tracks)
                    }
                }
                if let failure, sections.isEmpty { ErrorState(message: failure) { Task { await load() } }.padding(.horizontal, 20) }
            }.padding(.top, 8).padding(.bottom, 28)
        }.background(Color.pageBackground).navigationTitle("Dinle").navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
            .task(id: ListeningLocale.current.cacheKey + "|" + seedKey) {
                async let _ = uiConfig.fetchRemote()
                await load()
            }
            .refreshable {
                async let _ = uiConfig.fetchRemote()
                await load()
            }
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

private struct HomeSpotlightShelf: View {
    var title: String
    var subtitle: String? = nil
    var tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrowseShelfHeading(title: title, caption: subtitle, tracks: tracks)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(tracks.prefix(6)) { track in
                        HomeSpotlightCard(track: track, tracks: tracks)
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct HomeSpotlightCard: View {
    var track: Track
    var tracks: [Track]
    @EnvironmentObject private var player: MusicPlayer
    @ObservedObject private var uiConfig = DynamicUIConfig.shared
    private var isPlayingThis: Bool {
        (player.current?.id == track.id || player.pendingTrack?.id == track.id) && player.isPlaying
    }

    var body: some View {
        Button {
            player.play(track, in: tracks)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: uiConfig.style.heroCornerRadius, style: .continuous)
                    .fill(Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.94, alpha: 1) }))

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Artwork(url: track.artwork, radius: 0)
                        .frame(width: 175, height: uiConfig.style.heroHeight)
                        .clipped()
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black.opacity(0.4), location: 0.3),
                                    .init(color: .black, location: 0.75)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(L(uiConfig.style.heroTag).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.coral)
                        .padding(.bottom, 6)

                    Text(track.title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 160, alignment: .leading)

                    Text(track.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .padding(.top, 4)
                        .frame(maxWidth: 160, alignment: .leading)

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.12))
                            if player.pendingTrack?.id == track.id {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else {
                                Image(systemName: isPlayingThis ? "waveform" : "play.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isPlayingThis ? Color.coral : .white)
                            }
                        }
                        .frame(width: 38, height: 38)

                        Text(isPlayingThis ? L("Çalıyor") : L("Çal"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                }
                .padding(18)
            }
            .frame(width: 320, height: uiConfig.style.heroHeight)
            .clipShape(RoundedRectangle(cornerRadius: uiConfig.style.heroCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: uiConfig.style.heroCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(track.title), \(track.artist)")
        .accessibilityHint(L("Çal"))
    }
}

private struct HomeQuickLaunchShelf: View {
    var title: String
    var tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrowseShelfHeading(title: title, tracks: tracks)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(Array(tracks.prefix(6))) { track in
                    HomeQuickLaunchTile(track: track, tracks: tracks)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct HomeQuickLaunchTile: View {
    var track: Track
    var tracks: [Track]
    @EnvironmentObject private var player: MusicPlayer
    @ObservedObject private var uiConfig = DynamicUIConfig.shared
    private var isCurrent: Bool { player.current?.id == track.id || player.pendingTrack?.id == track.id }

    var body: some View {
        Button {
            player.play(track, in: tracks)
        } label: {
            HStack(spacing: 10) {
                Artwork(url: track.artwork, radius: uiConfig.style.tileCornerRadius)
                    .frame(width: 52, height: 52)
                    .clipped()

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isCurrent ? Color.coral : Color.primary)
                        .lineLimit(1)

                    Text(track.artist)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isCurrent {
                    Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.coral)
                        .padding(.trailing, 8)
                }
            }
            .padding(4)
            .background(
                Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.085, alpha: 1) : UIColor(white: 0.94, alpha: 1) }),
                in: RoundedRectangle(cornerRadius: uiConfig.style.tileCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: uiConfig.style.tileCornerRadius, style: .continuous)
                    .stroke(isCurrent ? Color.coral.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(track.title), \(track.artist)")
        .accessibilityHint(L("Çal"))
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
                if sections.isEmpty && failure != nil {
                    ErrorState(message: failure!) { Task { await load() } }.padding(.horizontal, 20)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        BrowseShelfHeading(title: "Türler ve ruh halleri")
                        CategoryGrid()
                    }
                }
            }.padding(.top, 8).padding(.bottom, 24)
        }.background(Color.pageBackground).navigationTitle(L("Keşfet")).navigationBarTitleDisplayMode(.large)
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
    @State private var loading = true
    @State private var failed = false
    @State private var requestID = UUID()
    var body: some View {
        Group {
            if categories.isEmpty {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120).accessibilityIdentifier("search.categories.loading")
                } else {
                    VStack(spacing: 12) {
                        Text(L(failed ? "Kategoriler yüklenemedi" : "Kategoriler şu anda kullanılamıyor"))
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button(L("Yeniden dene")) { Task { await load() } }
                            .buttonStyle(.bordered).tint(.primary).accessibilityIdentifier("search.categories.retry")
                    }.frame(maxWidth: .infinity, minHeight: 120).padding(.horizontal, 20)
                }
            } else {
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
            }
        }.task(id: ListeningLocale.current.cacheKey) { await load() }
    }
    private func load() async {
        let request = UUID(); requestID = request
        loading = true; failed = false
        defer { if requestID == request { loading = false } }
        do {
            let response = try await API.shared.categories()
            try Task.checkCancellation()
            guard requestID == request else { return }
            categories = response
        } catch {
            guard requestID == request, !Task.isCancelled else { return }
            failed = true
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
                else if result.tracks.isEmpty { EmptyState(symbol: "music.note", title: L("Sonuç bulunamadı"), message: L("Farklı bir arama dene.")) }
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

/// Build local search results without making a catalogue request or resolving remote IDs.
struct LibrarySearchResults {
    let response: SearchResponse
    let playlists: [SavedPlaylist]
    private let tracks: [Track]
    init(tracks: [Track], playlists: [SavedPlaylist], query: String) {
        self.tracks = tracks
        let terms = NativeCatalog.normalized(query).split(separator: " ")
        func matches(_ value: String) -> Bool {
            let text = NativeCatalog.normalized(value)
            return !terms.isEmpty && terms.allSatisfy { text.contains($0) }
        }
        var albums = [MusicCollection](), artists = [MusicArtist]()
        var seenAlbums = Set<String>(), seenArtists = Set<String>()
        for track in tracks {
            if !track.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               matches(track.album + " " + track.artist),
               seenAlbums.insert(Self.albumID(track)).inserted {
                albums.append(.init(id: Self.albumID(track), title: track.album, artist: track.artist, artwork: track.artwork))
            }
            let artistKey = Self.artistID(track)
            if !NativeCatalog.normalized(track.artist).isEmpty, matches(track.artist), seenArtists.insert(artistKey).inserted {
                artists.append(.init(id: artistKey, name: track.artist, artwork: nil))
            }
        }
        response = SearchResponse(
            tracks: tracks.filter { matches($0.title + " " + $0.artist + " " + $0.album) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
            albums: albums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
            artists: artists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        self.playlists = playlists.filter { matches($0.name) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func albumID(_ track: Track) -> String {
        if let id = track.albumID, !id.isEmpty { return id }
        return "local:" + NativeCatalog.normalized(track.artist) + "|" + NativeCatalog.normalized(track.album)
    }
    func tracks(in album: MusicCollection) -> [Track] { tracks.filter { Self.albumID($0) == album.id } }
    static func artistID(_ track: Track) -> String {
        if let id = track.artistID, !id.isEmpty { return id }
        return "local:" + NativeCatalog.normalized(track.artist)
    }
    func tracks(by artist: MusicArtist) -> [Track] {
        tracks.filter { Self.artistID($0) == artist.id }
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
    private var localResults: LibrarySearchResults { LibrarySearchResults(tracks: library.saved.compactMap(\.track), playlists: library.playlists, query: query) }
    private var visibleResult: SearchResponse { scope == "library" ? localResults.response : result }
    private var songs: [Track] { visibleResult.tracks }
    private var playlists: [SavedPlaylist] { scope == "library" ? localResults.playlists : [] }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if !hasQuery {
                    if scope == "library" {
                        EmptyState(symbol: "magnifyingglass", title: L("Kütüphanende ara"), message: L("Şarkı, albüm, sanatçı veya çalma listesi bul."))
                            .accessibilityIdentifier("search.library.empty")
                    } else if searchActive && !history.isEmpty { recentSearches.padding(.horizontal, 20) }
                    else {
                        BrowseShelfHeading(title: "Kategorilere göz at")
                        CategoryGrid()
                    }
                } else {
                    filters
                    if loading && scope == "catalog" { ProgressView().frame(maxWidth: .infinity).padding(30) }
                    else if let failure, scope == "catalog" { ErrorState(message: failure) { Task { await search() } } }
                    else {
                        if (filter == "albums" && visibleResult.albums.isEmpty) || (filter == "artists" && visibleResult.artists.isEmpty) || (filter == "playlists" && playlists.isEmpty) { noResults }
                        else { searchResults }
                    }
                }
            }.padding(.top, 8).padding(.bottom, 28)
        }.background(Color.pageBackground).navigationTitle(L("Ara")).navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, isPresented: $searchActive, prompt: Text(L("Sanatçılar, Şarkılar, Sözler ve Daha Fazlası")))
            .searchScopes($scope, activation: .onTextEntry) {
                Text("KlyMusic").tag("catalog"); Text(L("Kütüphanen")).tag("library")
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
            .scrollDismissesKeyboard(.interactively)
            .task(id: scope + "|" + query) {
                guard hasQuery else { result = SearchResponse(); loading = false; failure = nil; return }
                guard scope == "catalog" else { loading = false; failure = nil; return }
                loading = true; failure = nil
                do { try await Task.sleep(for: .milliseconds(200)); try Task.checkCancellation(); await search() } catch { }
            }.onSubmit(of: .search) { saveHistory() }
            .onChange(of: scope) { _, value in if value == "catalog", filter == "playlists" { filter = "all" } }
    }
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton("Tümü", value: "all")
                filterButton("Şarkılar", value: "songs")
                filterButton("Albümler", value: "albums")
                filterButton("Sanatçılar", value: "artists")
                if scope == "library" { filterButton("Çalma Listeleri", value: "playlists") }
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
                Text(L("Son Aramalar")).font(.title2.bold())
                Spacer()
                Button(L("Temizle")) { historyData = "" }.font(.subheadline).foregroundStyle(.secondary)
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
        if filter == "songs" { if songs.isEmpty { noResults } else { trackRows(songs) } }
        else if filter == "all" {
            if songs.isEmpty && visibleResult.artists.isEmpty && visibleResult.albums.isEmpty && playlists.isEmpty { noResults }
            else {
                VStack(spacing: 0) {
                    ForEach(Array(songs.prefix(3))) { track in
                        TrackRow(track: track, tracks: songs)
                        Divider().padding(.leading, 67)
                    }
                    ForEach(Array(playlists.prefix(2))) { playlistRow($0) }
                    ForEach(Array(visibleResult.artists.prefix(2))) { artistRow($0) }
                    ForEach(Array(visibleResult.albums.prefix(2))) { albumRow($0) }
                    ForEach(Array(songs.dropFirst(3))) { track in
                        TrackRow(track: track, tracks: songs)
                        Divider().padding(.leading, 67)
                    }
                }.padding(.horizontal, 20)
            }
        } else if filter == "albums" {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 24) {
                ForEach(visibleResult.albums) { album in
                    NavigationLink { albumDestination(album) } label: { AlbumCard(collection: album) }
                        .buttonStyle(.plain).accessibilityIdentifier("album.open.\(album.id)")
                }
            }.padding(.horizontal, 20)
        } else if filter == "artists" {
            VStack(spacing: 0) { ForEach(visibleResult.artists) { artistRow($0) } }.padding(.horizontal, 20)
        } else if filter == "playlists" {
            VStack(spacing: 0) { ForEach(playlists) { playlistRow($0) } }.padding(.horizontal, 20)
        }
    }
    @ViewBuilder private func albumDestination(_ album: MusicCollection) -> some View {
        if scope == "library" { TrackListView(title: album.title, tracks: localResults.tracks(in: album)) }
        else { AlbumDetailView(collection: album) }
    }
    @ViewBuilder private func artistDestination(_ artist: MusicArtist) -> some View {
        if scope == "library" { TrackListView(title: artist.name, tracks: localResults.tracks(by: artist)) }
        else { ArtistDetailView(id: artist.id, name: artist.name) }
    }
    private func playlistRow(_ playlist: SavedPlaylist) -> some View {
        VStack(spacing: 0) {
            NavigationLink { PlaylistDetailView(playlist: playlist) } label: {
                HStack(spacing: 14) {
                    PlaylistArtwork(tracks: library.tracks(in: playlist)).frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playlist.name).font(.body).foregroundStyle(.primary).lineLimit(1)
                        Text("Çalma Listesi").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.vertical, 7)
            }.buttonStyle(.plain).accessibilityIdentifier("search.playlist." + playlist.id.uuidString)
            Divider().padding(.leading, 67)
        }
    }
    private func artistRow(_ artist: MusicArtist) -> some View {
        VStack(spacing: 0) {
            NavigationLink { artistDestination(artist) } label: {
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
            NavigationLink { albumDestination(album) } label: {
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
    private var noResults: some View {
        EmptyState(symbol: "magnifyingglass", title: "Sonuç bulunamadı", message: scope == "library" ? "Kitaplığında eşleşen içerik yok. Farklı bir adla tekrar dene." : "Farklı bir şarkı veya sanatçı adıyla tekrar dene.")
            .accessibilityIdentifier("search.results.empty")
    }
    private func saveHistory() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        historyData = ([value] + history.filter { $0 != value }).prefix(8).joined(separator: "\n")
    }
    private func search() async {
        guard scope == "catalog", hasQuery else { return }
        let requested = query
        loading = true; failure = nil
        do {
            let response = try await API.shared.search(requested)
            try Task.checkCancellation()
            guard requested == query, scope == "catalog" else { return }
            result = response; player.warm(response.tracks); saveHistory()
        } catch is CancellationError { return }
        catch { guard requested == query, scope == "catalog", !Task.isCancelled else { return }; failure = error.localizedDescription }
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
                CollectionCoverHeader(artwork: collection.artwork, eyebrow: L("ALBÜM"), title: collection.title, subtitle: collection.artist)
                if !tracks.isEmpty {
                    CollectionPlayButtons(tracks: tracks).padding(.horizontal, 20)
                    Text(String(format: L("%lld şarkı · %@"), Int64(tracks.count), totalDuration)).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
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
