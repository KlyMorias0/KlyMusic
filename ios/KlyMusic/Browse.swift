import SwiftUI

struct DynamicStyle: Codable {
    var heroHeight: CGFloat = 180
    var heroCornerRadius: CGFloat = 16
    var heroTag: String = "Öne çıkan"
    var quickLaunchGridCount: Int = 6
    var tileCornerRadius: CGFloat = 12
    var cardCornerRadius: CGFloat = 12
    var sectionSpacing: CGFloat = 28
    var accentHex: String = "E87D73"
    var endlessFeedCount: Int = 30
    var endlessPageSize: Int = 20

    enum CodingKeys: String, CodingKey {
        case heroHeight, heroCornerRadius, heroTag, quickLaunchGridCount
        case tileCornerRadius, cardCornerRadius, sectionSpacing, accentHex
        case endlessFeedCount, endlessPageSize
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        heroHeight = try container.decodeIfPresent(CGFloat.self, forKey: .heroHeight) ?? 180
        heroCornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .heroCornerRadius) ?? 16
        heroTag = try container.decodeIfPresent(String.self, forKey: .heroTag) ?? "Öne çıkan"
        quickLaunchGridCount = try container.decodeIfPresent(Int.self, forKey: .quickLaunchGridCount) ?? 6
        tileCornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .tileCornerRadius) ?? 12
        cardCornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .cardCornerRadius) ?? 12
        sectionSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .sectionSpacing) ?? 28
        accentHex = try container.decodeIfPresent(String.self, forKey: .accentHex) ?? "E87D73"
        endlessFeedCount = try container.decodeIfPresent(Int.self, forKey: .endlessFeedCount) ?? 30
        endlessPageSize = try container.decodeIfPresent(Int.self, forKey: .endlessPageSize) ?? 20
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(heroHeight, forKey: .heroHeight)
        try container.encode(heroCornerRadius, forKey: .heroCornerRadius)
        try container.encode(heroTag, forKey: .heroTag)
        try container.encode(quickLaunchGridCount, forKey: .quickLaunchGridCount)
        try container.encode(tileCornerRadius, forKey: .tileCornerRadius)
        try container.encode(cardCornerRadius, forKey: .cardCornerRadius)
        try container.encode(sectionSpacing, forKey: .sectionSpacing)
        try container.encode(accentHex, forKey: .accentHex)
        try container.encode(endlessFeedCount, forKey: .endlessFeedCount)
        try container.encode(endlessPageSize, forKey: .endlessPageSize)
    }
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
    private var recommendations: [Track] {
        HomeFeed.interleaved(HomeFeed.distinct(personal, excluding: seeds))
    }
    private var featured: [Track] {
        if !recommendations.isEmpty { return recommendations }
        return Array(HomeFeed.distinct(sections, excluding: library.recent).first?.tracks.prefix(6) ?? [])
    }
    private var quickLaunch: [Track] {
        let count = max(0, uiConfig.style.quickLaunchGridCount)
        if !library.recent.isEmpty { return Array(library.recent.prefix(count)) }
        guard let first = sections.first, first.tracks.count >= 4 else { return [] }
        return Array(first.tracks.prefix(count))
    }
    private var remaining: [HomeSection] {
        HomeFeed.distinct(sections, excluding: Array(featured.prefix(6)) + quickLaunch + library.recent)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                if loading && sections.isEmpty {
                    MusicLoadingView()
                }

                // Spotlight hero shelf.
                if !featured.isEmpty {
                    HomeSpotlightShelf(
                        title: recommendations.isEmpty ? "Öne çıkanlar" : "Senin için",
                        tracks: featured
                    )
                    .accessibilityIdentifier(recommendations.isEmpty ? "home.featured" : "home.personalized")
                }

                // Quick-launch "Son dinlenenler" (or regional popular if no recent history)
                if !quickLaunch.isEmpty {
                    HomeQuickLaunchShelf(
                        title: library.recent.isEmpty ? (sections.first?.title ?? "Öne çıkanlar") : "Son dinlenenler",
                        tracks: quickLaunch
                    )
                }

                // Keep each catalog category in its own horizontal shelf.
                ForEach(Array(remaining.enumerated()), id: \.element.id) { index, section in
                    if index % 2 == 0 {
                        CompactTrackShelf(title: section.title, tracks: section.tracks)
                    } else {
                        BrowseTrackShelf(
                            title: section.title,
                            subtitle: section.subtitle.isEmpty ? nil : section.subtitle,
                            tracks: section.tracks
                        )
                    }
                }

                if let failure, sections.isEmpty {
                    ErrorState(message: failure) { Task { await load() } }
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.pageBackground)
        .navigationTitle(L("Dinle"))
        .toolbarTitleDisplayMode(.inlineLarge)
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
        loading = sections.isEmpty
        failure = nil
        defer { loading = false }
        do {
            let homeRes = try await API.shared.home()
            try Task.checkCancellation()
            sections = homeRes.sections
            loading = false
            if seeds.isEmpty {
                personal = []
            } else {
                let recommended = (try? await API.shared.recommendations(for: seeds).sections) ?? []
                try Task.checkCancellation()
                personal = recommended
            }
            player.warm(featured)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }
}

private struct HomeSpotlightShelf: View {
    var title: String
    var tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrowseShelfHeading(title: title, tracks: tracks)
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

    var body: some View {
        Button { player.play(track, in: tracks) } label: {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay { Artwork(url: track.artwork, radius: 0) }
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.08), .black.opacity(0.8)],
                                   startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                        Text(track.title)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay(alignment: .topTrailing) {
                    if player.pendingTrack?.id == track.id {
                        ProgressView().tint(.white).padding(14)
                    } else if player.current?.id == track.id && player.isPlaying {
                        Image(systemName: "waveform")
                            .font(.body.weight(.semibold)).foregroundStyle(.white)
                            .padding(10).background(.black.opacity(0.35), in: Circle()).padding(10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 5)
                .containerRelativeFrame(.horizontal) { width, _ in
                    min(320, max(220, (width - 40) * 0.68))
                }
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(SpotlightButtonStyle())
        .accessibilityLabel("\(track.title), \(track.artist)")
        .accessibilityHint(L("Çal"))
        .accessibilityIdentifier("home.spotlight.\(track.id)")
    }
}

private struct SpotlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}


private struct HomeQuickLaunchShelf: View {
    var title: String
    var tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrowseShelfHeading(title: title, tracks: tracks)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(tracks) { track in
                        TrackCard(track: track, tracks: tracks, size: 152)
                            .accessibilityIdentifier("track.row.\(track.id)")
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CompactTrackShelf: View {
    var title: String
    var tracks: [Track]
    var rows = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BrowseShelfHeading(title: title, tracks: tracks)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 24) {
                    ForEach(0..<((min(tracks.count, 12) + rows - 1) / rows), id: \.self) { column in
                        VStack(spacing: 0) {
                            ForEach(Array(tracks.dropFirst(column * rows).prefix(rows))) { track in
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
            if let tracks, !tracks.isEmpty {
                NavigationLink { TrackListView(title: title, tracks: tracks) } label: {
                    heading(showChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint(L("Tümünü göster"))
            } else {
                heading(showChevron: false)
            }
            if let caption, !caption.isEmpty {
                Text(L(caption)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }

    private func heading(showChevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(L(title)).font(.title2.bold()).tracking(-0.5).foregroundStyle(Color.primary)
            if showChevron {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.secondary).accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
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
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(tracks.prefix(14)) { track in
                        TrackCard(track: track, tracks: tracks, size: large ? 240 : 160)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

struct DiscoverView: View {
    @State private var sections: [HomeSection] = []
    @State private var failure: String?
    @State private var loading = true
    @EnvironmentObject private var player: MusicPlayer

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                if loading && sections.isEmpty {
                    MusicLoadingView()
                }

                // Editorial featured hero banners
                if let first = sections.first, !first.tracks.isEmpty {
                    DiscoverHeroShelf(title: "Öne çıkanlar", tracks: Array(first.tracks.prefix(6)))
                }

                // Four-row song shelves alternate with square-cover collections.
                ForEach(Array(HomeFeed.distinct(sections, excluding: Array(sections.first?.tracks.prefix(6) ?? [])).enumerated()), id: \.element.id) { index, section in
                    if index == 0 {
                        CompactTrackShelf(title: section.title, tracks: section.tracks, rows: 4)
                    } else {
                        BrowseTrackShelf(title: section.title, subtitle: section.subtitle, tracks: section.tracks)
                    }
                }

                // Unified error handling or Categories grid
                if sections.isEmpty && failure != nil {
                    ErrorState(message: failure!) { Task { await load() } }
                        .padding(.horizontal, 20)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        BrowseShelfHeading(title: "Türler ve ruh halleri")
                        CategoryGrid()
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.pageBackground)
        .navigationTitle(L("Keşfet"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
        .task(id: ListeningLocale.current.cacheKey) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = sections.isEmpty
        failure = nil
        defer { loading = false }
        do {
            sections = try await API.shared.home().sections
            player.warm(sections.first?.tracks ?? [])
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
    }
}


private struct DiscoverHeroShelf: View {
    var title: String
    var tracks: [Track]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(tracks) { track in
                    DiscoverHeroCard(track: track, tracks: tracks, eyebrow: title)
                }
            }
            .padding(.horizontal, 20)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

private struct DiscoverHeroCard: View {
    var track: Track
    var tracks: [Track]
    var eyebrow: String
    @EnvironmentObject private var player: MusicPlayer

    var body: some View {
        Button { player.play(track, in: tracks) } label: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(eyebrow).uppercased())
                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary).tracking(0.4)
                    Text(track.title).font(.title3).foregroundStyle(.primary).lineLimit(1)
                    Text(track.artist).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                }
                Color.clear
                    .aspectRatio(3.0 / 2.0, contentMode: .fit)
                    .overlay { Artwork(url: track.artwork, radius: 0) }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 4)
            }
            .containerRelativeFrame(.horizontal) { width, _ in
                min(460, max(280, width - 64))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SpotlightButtonStyle())
        .accessibilityLabel("\(track.title), \(track.artist)")
        .accessibilityHint(L("Çal"))
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
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityIdentifier("search.categories.loading")
                } else {
                    VStack(spacing: 12) {
                        Text(L(failed ? "Kategoriler yüklenemedi" : "Kategoriler şu anda kullanılamıyor"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(L("Yeniden dene")) { Task { await load() } }
                            .buttonStyle(.bordered)
                            .tint(Color.coral)
                            .accessibilityIdentifier("search.categories.retry")
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .padding(.horizontal, 20)
                }
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(categories) { category in
                        NavigationLink {
                            QueryView(query: category.query, title: category.title)
                        } label: {
                            CategoryCard(category: category)
                        }
                        .buttonStyle(TileButtonStyle())
                        .accessibilityIdentifier("search.category.\(category.id)")
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .task(id: ListeningLocale.current.cacheKey) { await load() }
    }

    private func load() async {
        let request = UUID()
        requestID = request
        loading = true
        failed = false
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


private struct CategoryCard: View {
    var category: BrowseCategory

    var body: some View {
        Color.musicElevated
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay { Artwork(url: category.artwork, radius: 0) }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                if !result.tracks.isEmpty {
                    CollectionPlayButtons(tracks: result.tracks)
                        .padding(.horizontal, 20)
                }
                if loading {
                    ProgressView().padding(40)
                } else if let failure {
                    ErrorState(message: failure) { Task { await load() } }
                } else if result.tracks.isEmpty {
                    EmptyState(symbol: "music.note", title: L("Sonuç bulunamadı"), message: L("Farklı bir arama dene."))
                }
                trackRows(result.tracks)
            }
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color.pageBackground)
        .navigationTitle(title)
        .task { await load() }
    }

    private func load() async {
        loading = true
        failure = nil
        defer { loading = false }
        do {
            result = try await API.shared.search(query)
            player.warm(result.tracks)
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
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
                    } else if searchActive && !history.isEmpty {
                        recentSearches.padding(.horizontal, 20)
                    } else {
                        CategoryGrid().accessibilityIdentifier("search.categories")
                    }
                } else {
                    filters

                    if loading && scope == "catalog" {
                        ProgressView().frame(maxWidth: .infinity).padding(30)
                    } else if let failure, scope == "catalog" {
                        ErrorState(message: failure) { Task { await search() } }
                    } else {
                        if (filter == "albums" && visibleResult.albums.isEmpty) ||
                           (filter == "artists" && visibleResult.artists.isEmpty) ||
                           (filter == "playlists" && playlists.isEmpty) {
                            noResults
                        } else {
                            searchResults
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.pageBackground)
        .navigationTitle(L("Ara"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $query, isPresented: $searchActive, prompt: Text(L("Sanatçılar, Şarkılar, Sözler ve Daha Fazlası")))
        .searchScopes($scope, activation: .onTextEntry) {
            Text("KlyMusic").tag("catalog")
            Text(L("Kütüphanen")).tag("library").accessibilityIdentifier("Kitaplığın")
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
        .scrollDismissesKeyboard(.interactively)
        .task(id: scope + "|" + query) {
            guard hasQuery else {
                result = SearchResponse()
                loading = false
                failure = nil
                return
            }
            guard scope == "catalog" else {
                loading = false
                failure = nil
                return
            }
            loading = true
            failure = nil
            do {
                try await Task.sleep(for: .milliseconds(200))
                try Task.checkCancellation()
                await search()
            } catch { }
        }
        .onSubmit(of: .search) { saveHistory() }
        .onChange(of: scope) { _, value in
            if value == "catalog", filter == "playlists" { filter = "all" }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton("Tümü", value: "all")
                filterButton("Şarkılar", value: "songs")
                filterButton("Albümler", value: "albums")
                filterButton("Sanatçılar", value: "artists")
                if scope == "library" { filterButton("Çalma Listeleri", value: "playlists") }
            }
            .padding(.horizontal, 20)
        }
        .accessibilityIdentifier("search.filters")
    }

    private func filterButton(_ title: String, value: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { filter = value }
        } label: {
            Text(L(title))
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(filter == value ? Color.pageBackground : Color.primary)
                .background(
                    filter == value ? Color.primary : Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.92, alpha: 1) }),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(filter == value ? Color.clear : Color.white.opacity(0.06), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search.filter.\(value)")
        .accessibilityAddTraits(filter == value ? .isSelected : [])
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Son Aramalar")).font(.headline.bold())
                Spacer()
                Button(L("Temizle")) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        historyData = ""
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Color.coral)
            }
            .padding(.bottom, 6)

            ForEach(history.prefix(5), id: \.self) { term in
                Button {
                    query = term
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                        Text(term)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 32)
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        if filter == "songs" {
            if songs.isEmpty { noResults } else { trackRows(songs) }
        } else if filter == "all" {
            if songs.isEmpty && visibleResult.artists.isEmpty && visibleResult.albums.isEmpty && playlists.isEmpty {
                noResults
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    if !songs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            BrowseShelfHeading(title: "Şarkılar", tracks: songs)
                            VStack(spacing: 0) {
                                ForEach(Array(songs.prefix(5))) { track in
                                    TrackRow(track: track, tracks: songs)
                                    Divider().padding(.leading, 67)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    if !visibleResult.artists.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            BrowseShelfHeading(title: "Sanatçılar")
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(visibleResult.artists) { artist in
                                        NavigationLink {
                                            artistDestination(artist)
                                        } label: {
                                            VStack(spacing: 8) {
                                                ArtistPortrait(url: artist.artwork, name: artist.name)
                                                    .frame(width: 80, height: 80)
                                                    .clipShape(Circle())
                                                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                                                Text(artist.name)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                    .frame(width: 86)
                                            }
                                        }
                                        .buttonStyle(CardButtonStyle())
                                        .accessibilityIdentifier("artist.open.\(artist.id)")
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }

                    if !visibleResult.albums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            BrowseShelfHeading(title: "Albümler")
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 14) {
                                    ForEach(visibleResult.albums) { album in
                                        NavigationLink {
                                            albumDestination(album)
                                        } label: {
                                            AlbumCard(collection: album).frame(width: 140)
                                        }
                                        .buttonStyle(CardButtonStyle())
                                        .accessibilityIdentifier("album.open.\(album.id)")
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }

                    if !playlists.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            BrowseShelfHeading(title: "Çalma Listeleri")
                            VStack(spacing: 0) {
                                ForEach(playlists) { playlistRow($0) }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    if songs.count > 5 {
                        VStack(alignment: .leading, spacing: 10) {
                            BrowseShelfHeading(title: "Şarkılar", tracks: songs)
                            VStack(spacing: 0) {
                                ForEach(Array(songs.dropFirst(5))) { track in
                                    TrackRow(track: track, tracks: songs)
                                    Divider().padding(.leading, 67)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
        } else if filter == "albums" {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
                ForEach(visibleResult.albums) { album in
                    NavigationLink {
                        albumDestination(album)
                    } label: {
                        AlbumCard(collection: album)
                    }
                    .buttonStyle(CardButtonStyle())
                    .accessibilityIdentifier("album.open.\(album.id)")
                }
            }
            .padding(.horizontal, 20)
        } else if filter == "artists" {
            VStack(spacing: 0) {
                ForEach(visibleResult.artists) { artistRow($0) }
            }
            .padding(.horizontal, 20)
        } else if filter == "playlists" {
            VStack(spacing: 0) {
                ForEach(playlists) { playlistRow($0) }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder private func albumDestination(_ album: MusicCollection) -> some View {
        if scope == "library" {
            TrackListView(title: album.title, tracks: localResults.tracks(in: album))
        } else {
            AlbumDetailView(collection: album)
        }
    }

    @ViewBuilder private func artistDestination(_ artist: MusicArtist) -> some View {
        if scope == "library" {
            TrackListView(title: artist.name, tracks: localResults.tracks(by: artist))
        } else {
            ArtistDetailView(id: artist.id, name: artist.name)
        }
    }

    private func playlistRow(_ playlist: SavedPlaylist) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                PlaylistDetailView(playlist: playlist)
            } label: {
                HStack(spacing: 14) {
                    PlaylistArtwork(tracks: library.tracks(in: playlist))
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(playlist.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(L("Çalma Listesi"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(TrackRowButtonStyle())
            .accessibilityIdentifier("search.playlist." + playlist.id.uuidString)
            Divider().padding(.leading, 66)
        }
    }

    private func artistRow(_ artist: MusicArtist) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                artistDestination(artist)
            } label: {
                HStack(spacing: 14) {
                    ArtistPortrait(url: artist.artwork, name: artist.name)
                        .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(artist.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(L("Sanatçı"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(TrackRowButtonStyle())
            .accessibilityIdentifier("artist.open.\(artist.id)")
            Divider().padding(.leading, 66)
        }
    }

    private func albumRow(_ album: MusicCollection) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                albumDestination(album)
            } label: {
                HStack(spacing: 14) {
                    Artwork(url: album.artwork, radius: 10)
                        .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(album.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(album.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(TrackRowButtonStyle())
            .accessibilityIdentifier("album.open.\(album.id)")
            Divider().padding(.leading, 66)
        }
    }
    private var noResults: some View {
        EmptyState(
            symbol: "magnifyingglass",
            title: L("Sonuç bulunamadı"),
            message: scope == "library" ? L("Kitaplığında eşleşen içerik yok. Farklı bir adla tekrar dene.") : L("Farklı bir şarkı veya sanatçı adıyla tekrar dene.")
        )
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
        loading = true
        failure = nil
        do {
            let response = try await API.shared.search(requested)
            try Task.checkCancellation()
            guard requested == query, scope == "catalog" else { return }
            result = response
            player.warm(response.tracks)
            saveHistory()
        } catch is CancellationError {
            return
        } catch {
            guard requested == query, scope == "catalog", !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
        loading = false
    }
}

@ViewBuilder private func trackRows(_ tracks: [Track]) -> some View {
    LazyVStack(spacing: 0) {
        ForEach(tracks) { track in
            TrackRow(track: track, tracks: tracks)
            Divider().padding(.leading, 67)
        }
    }
    .padding(.horizontal, 20)
}

private struct AlbumCard: View {
    var collection: MusicCollection
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Artwork(url: collection.artwork, radius: 12)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
            Text(collection.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(Color.primary)
            Text(collection.artist)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(Color.secondary)
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

    private var releaseYear: String? {
        if let date = collection.releaseDate, date.count >= 4 {
            return String(date.prefix(4))
        }
        return nil
    }

    private var totalDuration: String {
        String(format: L("%lld dakika"), Int64(tracks.reduce(0) { $0 + $1.duration } / 60))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .center, spacing: 20) {
                // Centered artwork with 14pt radius, deep shadow and subtle ambient aura
                ZStack {
                    Artwork(url: collection.artwork, radius: 0)
                        .frame(width: 200, height: 200)
                        .blur(radius: 40)
                        .opacity(0.3)
                    Artwork(url: collection.artwork, radius: 14)
                        .frame(width: 220, height: 220)
                        .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 9)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .padding(.top, 16)

                // Title, Artist and Release Year
                VStack(spacing: 6) {
                    Text(collection.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 20)

                    NavigationLink {
                        if let firstTrack = tracks.first, let artistID = firstTrack.artistID {
                            ArtistDetailView(id: artistID, name: collection.artist)
                        } else {
                            QueryView(query: collection.artist, title: collection.artist)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(collection.artist)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.coral)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.coral.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("album.artist.\(collection.artist)")
                    .padding(.horizontal, 20)

                    if let year = releaseYear {
                        Text(year)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                }

                // Play & Shuffle pill buttons (hidden until tracks load!)
                if !tracks.isEmpty {
                    VStack(spacing: 8) {
                        CollectionPlayButtons(tracks: tracks)
                            .padding(.horizontal, 20)

                        Text(String(format: L("%lld şarkı · %@"), Int64(tracks.count), totalDuration))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 4)
                }

                if loading {
                    ProgressView()
                        .tint(Color.coral)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                }

                if let failure {
                    ErrorState(message: failure) {
                        Task { await load() }
                    }
                    .padding(.horizontal, 20)
                }

                // Track list with track numbers
                if !tracks.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, tracks: tracks, number: index + 1)
                            Divider().padding(.leading, 40)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        loading = true
        failure = nil
        defer { loading = false }
        do {
            tracks = try await API.shared.album(collection.id).tracks
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct CollectionCoverHeader: View {
    var artwork: String?
    var eyebrow: String
    var title: String
    var subtitle: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 16) {
            Artwork(url: artwork, radius: 12)
                .frame(width: typeSize.isAccessibilitySize ? 180 : 220, height: typeSize.isAccessibilitySize ? 180 : 220)
                .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 7)
                .padding(.bottom, 4)

            VStack(spacing: 6) {
                Text(L(eyebrow).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color.coral)

                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
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

    private var isFollowing: Bool {
        followed.split(separator: "\n").contains { $0.split(separator: "|", maxSplits: 1).first == Substring(id) }
    }
    private var artwork: String? { details?.artist.banner ?? details?.artist.artwork }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Immersive hero banner
                VStack(spacing: 16) {
                    if let artwork {
                        ZStack(alignment: .bottom) {
                            Artwork(url: artwork, radius: 0)
                                .frame(height: 320)
                                .clipped()

                            // Smooth fade into pure black (Color.pageBackground)
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .clear, location: 0.35),
                                    .init(color: Color.pageBackground.opacity(0.6), location: 0.72),
                                    .init(color: Color.pageBackground, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )

                            artistNameView
                                .padding(.bottom, 8)
                        }
                    } else {
                        VStack(spacing: 18) {
                            ArtistPortrait(url: nil, name: name)
                                .frame(width: 120, height: 120)
                            artistNameView
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }

                    // Play buttons & Follow button
                    HStack(spacing: 12) {
                        if let tracks = details?.tracks, !tracks.isEmpty {
                            CollectionPlayButtons(tracks: tracks)
                        }
                        Button(action: toggleFollow) {
                            Image(systemName: isFollowing ? "star.fill" : "star")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(isFollowing ? Color.coral : Color.primary)
                                .frame(width: 44, height: 44)
                                .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(CardButtonStyle())
                        .accessibilityLabel(isFollowing ? L("Takibi bırak") : L("Takip et"))
                    }
                    .padding(.horizontal, 20)
                }

                if let details {
                    artistContent(details)
                } else if let failure {
                    ErrorState(message: failure) { Task { await load() } }
                        .padding(.horizontal, 20)
                } else {
                    ProgressView()
                        .tint(Color.coral)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                }
            }
            .padding(.bottom, 32)
        }
        .coordinateSpace(name: "artistScroll")
        .background(Color.pageBackground)
        .navigationTitle(compactTitle ? name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleFollow) {
                    Image(systemName: isFollowing ? "star.fill" : "star")
                }
                .foregroundStyle(isFollowing ? Color.coral : .primary)
                .accessibilityLabel(isFollowing ? L("Takibi bırak") : L("Takip et"))
            }
        }
        .task { await load() }
    }

    private var artistNameView: some View {
        Text(details?.artist.name ?? name)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: Bool.self) { geometry in
                geometry.frame(in: .named("artistScroll")).maxY < 0
            } action: { compactTitle = $0 }
    }

    private func artistContent(_ details: ArtistResponse) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            // Latest / Featured release card
            if let release = details.featured ?? details.albums.first {
                NavigationLink {
                    AlbumDetailView(collection: release)
                } label: {
                    HStack(spacing: 14) {
                        Artwork(url: release.artwork, radius: 10)
                            .frame(width: 80, height: 80)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L(release.releaseLabel).uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.coral)
                            Text(release.title)
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Text(release.artist)
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                            if let date = release.releaseDate, date.count >= 4 {
                                Text(String(date.prefix(4)))
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
                    )
                }
                .buttonStyle(CardButtonStyle())
                .padding(.horizontal, 20)
                .accessibilityIdentifier("artist.latest")
            }

            // Popular tracks with rank numbers (1, 2, 3...)
            if !details.tracks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    BrowseShelfHeading(title: "En çok dinlenenler", tracks: details.tracks)
                    LazyVStack(spacing: 0) {
                        ForEach(Array(details.tracks.prefix(10).enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, tracks: details.tracks, number: index + 1)
                            Divider().padding(.leading, 40)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            // Discography shelves (Albums & Singles)
            if !details.albums.isEmpty {
                let albums = details.albums.filter { $0.kind.lowercased() != "single" }
                let singles = details.albums.filter { $0.kind.lowercased() == "single" }

                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        BrowseShelfHeading(title: "Albümler")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(albums) { album in
                                    NavigationLink {
                                        AlbumDetailView(collection: album)
                                    } label: {
                                        AlbumCard(collection: album).frame(width: 154)
                                    }
                                    .buttonStyle(CardButtonStyle())
                                    .accessibilityIdentifier("album.open.\(album.id)")
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if !singles.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        BrowseShelfHeading(title: "Tekliler")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(singles) { single in
                                    NavigationLink {
                                        AlbumDetailView(collection: single)
                                    } label: {
                                        AlbumCard(collection: single).frame(width: 154)
                                    }
                                    .buttonStyle(CardButtonStyle())
                                    .accessibilityIdentifier("album.open.\(single.id)")
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                } else if albums.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        BrowseShelfHeading(title: "Albümler")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(details.albums) { album in
                                    NavigationLink {
                                        AlbumDetailView(collection: album)
                                    } label: {
                                        AlbumCard(collection: album).frame(width: 154)
                                    }
                                    .buttonStyle(CardButtonStyle())
                                    .accessibilityIdentifier("album.open.\(album.id)")
                                }
                            }
                            .padding(.horizontal, 20)
                        }
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
        do {
            details = try await API.shared.artist(id)
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
    }
}
