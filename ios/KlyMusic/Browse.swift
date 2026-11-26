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
    private var allCatalogTracks: [Track] {
        Self.uniqueTracks(featured + remaining.flatMap(\.tracks) + recommendations + sections.flatMap(\.tracks))
    }
    private var personalMixes: [HomePersonalMix] {
        let pool = allCatalogTracks
        guard !pool.isEmpty || !library.favorites.isEmpty else { return [] }
        let favoritesTracks = library.favorites.isEmpty ? (featured.isEmpty ? pool : featured) : library.favorites
        let freshTracks = Self.uniqueTracks(remaining.flatMap(\.tracks))
        let newMusicTracks = freshTracks.isEmpty ? pool : freshTracks
        let halfIndex = max(0, sections.count / 2)
        let chillPool = Self.uniqueTracks(Array(sections.dropFirst(halfIndex)).flatMap(\.tracks) + recommendations)
        let chillTracks = chillPool.isEmpty ? Array(pool.reversed()) : chillPool
        let energyBase = Self.uniqueTracks(remaining.flatMap(\.tracks) + recommendations + featured)
        let energySource = energyBase.isEmpty ? pool : energyBase
        let strideOffset = min(3, energySource.count / 2)
        let energyTracks = Array(energySource.dropFirst(strideOffset) + energySource.prefix(strideOffset))

        return [
            HomePersonalMix(
                id: "favorites",
                title: "Favoriler Miksi",
                subtitle: "Sana Özel",
                tracks: Array(favoritesTracks.prefix(25)),
                colors: [Color(red: 0.98, green: 0.24, blue: 0.34), Color(red: 0.70, green: 0.08, blue: 0.22)]
            ),
            HomePersonalMix(
                id: "new-music",
                title: "Yeni Müzik Miksi",
                subtitle: "Her Gün Güncellenir",
                tracks: Array(newMusicTracks.prefix(25)),
                colors: [Color(red: 0.36, green: 0.24, blue: 0.88), Color(red: 0.54, green: 0.14, blue: 0.72)]
            ),
            HomePersonalMix(
                id: "chill",
                title: "Chill Miksi",
                subtitle: "Sana Özel",
                tracks: Array(chillTracks.prefix(25)),
                colors: [Color(red: 0.08, green: 0.44, blue: 0.56), Color(red: 0.08, green: 0.16, blue: 0.36)]
            ),
            HomePersonalMix(
                id: "energy",
                title: "Enerji Miksi",
                subtitle: "Her Gün Güncellenir",
                tracks: Array(energyTracks.prefix(25)),
                colors: [Color(red: 0.95, green: 0.44, blue: 0.14), Color(red: 0.80, green: 0.12, blue: 0.48)]
            )
        ]
    }
    private var homeStations: [HomeStationItem] {
        let pool = allCatalogTracks
        let personalSeeds = Self.uniqueTracks(seeds + pool)
        guard !personalSeeds.isEmpty else { return [] }
        let discoveryPool = Self.uniqueTracks(remaining.flatMap(\.tracks) + recommendations)
        let hitPool = Self.uniqueTracks((sections.first?.tracks ?? []) + featured)
        let chillPool = Self.uniqueTracks((sections.last?.tracks ?? []) + recommendations)
        let primaryArtist = seeds.first?.artist
        let defaultQuery = ListeningLocale.current.languageCode == "tr" ? "Türkçe Pop" : "Pop Hits"
        let personalQuery = (primaryArtist?.isEmpty == false) ? primaryArtist! : defaultQuery

        return [
            HomeStationItem(
                id: "personal",
                title: "Senin İstasyonun",
                subtitle: "Sevdiğin sanatçılar ve sana özel kesintisiz müzik",
                query: personalQuery,
                symbol: "dot.radiowaves.left.and.right",
                colors: [Color(red: 0.98, green: 0.16, blue: 0.25), Color(red: 0.56, green: 0.08, blue: 0.34)],
                seedTracks: Array(personalSeeds.prefix(20))
            ),
            HomeStationItem(
                id: "discovery",
                title: "Keşif İstasyonu",
                subtitle: "Yeni sesler ve benzer sanatçılar",
                query: "Keşif",
                symbol: "sparkles",
                colors: [Color(red: 0.32, green: 0.28, blue: 0.86), Color(red: 0.14, green: 0.12, blue: 0.48)],
                seedTracks: Array((discoveryPool.isEmpty ? pool : discoveryPool).prefix(20))
            ),
            HomeStationItem(
                id: "hits",
                title: "Hit Müzik İstasyonu",
                subtitle: "Günün en popüler parçaları",
                query: "Pop Hits",
                symbol: "flame.fill",
                colors: [Color(red: 0.92, green: 0.22, blue: 0.44), Color(red: 0.44, green: 0.10, blue: 0.42)],
                seedTracks: Array((hitPool.isEmpty ? pool : hitPool).prefix(20))
            ),
            HomeStationItem(
                id: "chill",
                title: "Gece & Chill İstasyonu",
                subtitle: "Geceye eşlik eden sakin ve akustik seçkiler",
                query: "Chill Akustik",
                symbol: "moon.stars.fill",
                colors: [Color(red: 0.14, green: 0.36, blue: 0.58), Color(red: 0.08, green: 0.14, blue: 0.30)],
                seedTracks: Array((chillPool.isEmpty ? pool : chillPool).prefix(20))
            )
        ]
    }
    private var favoriteArtists: [HomeArtistItem] {
        Self.extractArtists(from: seeds + sections.flatMap(\.tracks), limit: 10)
    }
    private var spatialTracks: [Track] {
        let later = Self.uniqueTracks(remaining.dropFirst().flatMap(\.tracks))
        let source = later.isEmpty ? allCatalogTracks : later
        return Array(source.prefix(14))
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
                        tracks: featured,
                        personalized: !recommendations.isEmpty
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

                if let firstSection = remaining.first, !firstSection.tracks.isEmpty {
                    CompactTrackShelf(title: firstSection.title, tracks: firstSection.tracks, rows: 4)
                }

                if !personalMixes.isEmpty {
                    HomePersonalMixShelf(mixes: personalMixes)
                }

                if !homeStations.isEmpty {
                    HomeStationsShelf(stations: homeStations)
                }

                if !favoriteArtists.isEmpty {
                    HomeArtistsShelf(artists: favoriteArtists)
                }

                if !CommandLine.arguments.contains("-serverURL"), library.saved.contains(where: { $0.playCount > 0 }) {
                    NavigationLink {
                        ListeningReplayView()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    LinearGradient(
                                        colors: [Color.coral, Color(red: 0.72, green: 0.14, blue: 0.42)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("KlyMusic Replay"))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(L("En çok dinlediğin şarkılar ve sanatçılar"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(CardButtonStyle())
                    .accessibilityIdentifier("replay.open")
                }

                if !spatialTracks.isEmpty {
                    HomeSpatialShelf(title: "Uzamsal Ses", tracks: spatialTracks)
                }

                ForEach(Array(remaining.dropFirst().enumerated()), id: \.element.id) { index, section in
                    if index % 2 == 0 {
                        BrowseTrackShelf(
                            title: section.title,
                            subtitle: section.subtitle.isEmpty ? nil : section.subtitle,
                            tracks: section.tracks
                        )
                    } else {
                        CompactTrackShelf(title: section.title, tracks: section.tracks, rows: 4)
                    }
                }

                if !(sections.isEmpty && failure != nil) {
                    MoreToExploreSection()
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

    private static func uniqueTracks(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.id).inserted }
    }

    private static func extractArtists(from tracks: [Track], limit: Int) -> [HomeArtistItem] {
        var order: [String] = []
        var byKey: [String: HomeArtistItem] = [:]
        for track in tracks {
            let trimmed = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = NativeCatalog.normalized(trimmed)
            guard !trimmed.isEmpty, !key.isEmpty else { continue }
            let artistID = track.artistID ?? ""
            if var existing = byKey[key] {
                if existing.id.isEmpty && !artistID.isEmpty {
                    existing.id = artistID
                }
                if existing.artwork == nil, let art = track.artwork, !art.isEmpty {
                    existing.artwork = art
                }
                byKey[key] = existing
            } else if order.count < limit {
                order.append(key)
                byKey[key] = HomeArtistItem(id: artistID, name: trimmed, artwork: track.artwork)
            }
        }
        return order.compactMap { byKey[$0] }
    }
}

private struct HomeSpotlightShelf: View {
    var title: String
    var tracks: [Track]
    var personalized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrowseShelfHeading(title: title, tracks: tracks)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(tracks.prefix(6)) { track in
                        HomeSpotlightCard(track: track, tracks: tracks, eyebrow: personalized ? "Senin için" : "Öne Çıkan")
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
    var eyebrow: String
    @EnvironmentObject private var player: MusicPlayer
    @State private var tint = ArtworkPalette.fallback.bottom.color

    private var isCurrent: Bool { player.current?.id == track.id }
    private var isPending: Bool { player.pendingTrack?.id == track.id }

    var body: some View {
        Button { player.play(track, in: tracks) } label: {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay { Artwork(url: track.artwork, radius: 0) }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.42),
                            .init(color: tint.opacity(0.68), location: 0.72),
                            .init(color: .black.opacity(0.88), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L(eyebrow))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                            Text(track.title)
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(track.artist)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.84))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ZStack {
                            Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                            if isPending {
                                ProgressView().controlSize(.small).tint(.white)
                            } else if isCurrent {
                                NowPlayingBars(isPlaying: player.isPlaying, color: .white, size: 12)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .offset(x: 1)
                            }
                        }
                        .frame(width: 32, height: 32)
                    }
                    .padding(16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)
                .containerRelativeFrame(.horizontal) { width, _ in
                    min(310, max(230, (width - 40) * 0.68))
                }
                .contentShape(RoundedRectangle(cornerRadius: 18))
                .task(id: track.artwork) {
                    let url = ArtworkRequest.sized(track.artworkURL, pixels: 320)
                    if let image = await ArtworkCache.shared.image(url, fallback: track.artworkURL, maxPixels: 240),
                       let extracted = await ArtworkCache.shared.palette(image),
                       !Task.isCancelled {
                        tint = extracted.bottom.color
                    }
                }
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
                        TrackCard(track: track, tracks: tracks, size: 158)
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
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(0..<((min(tracks.count, 16) + rows - 1) / rows), id: \.self) { column in
                        VStack(spacing: 0) {
                            ForEach(Array(tracks.dropFirst(column * rows).prefix(rows))) { track in
                                TrackRow(track: track, tracks: tracks)
                                Divider().padding(.leading, 64)
                            }
                        }.frame(width: 318)
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
                NavigationLink { TrackListView(title: L(title), tracks: tracks) } label: {
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

private struct HomePersonalMix: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let tracks: [Track]
    let colors: [Color]
}

private struct HomePersonalMixShelf: View {
    var mixes: [HomePersonalMix]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrowseShelfHeading(title: "Sana Özel Miksler")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(mixes) { mix in
                        NavigationLink {
                            TrackListView(title: L(mix.title), tracks: mix.tracks, subtitle: L("Sana Özel"), style: .collection)
                        } label: {
                            HomePersonalMixCard(mix: mix)
                        }
                        .buttonStyle(CardButtonStyle())
                        .accessibilityIdentifier("home.mix.\(mix.id)")
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct HomePersonalMixCard: View {
    var mix: HomePersonalMix

    private var collageArtworks: [String] {
        var seen = Set<String>()
        var urls: [String] = []
        for track in mix.tracks {
            if let art = track.artwork, !art.isEmpty, seen.insert(art).inserted {
                urls.append(art)
                if urls.count == 3 { break }
            }
        }
        return urls
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: mix.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 140, height: 140)
                .offset(x: 68, y: -74)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(0.45), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(L("MİKS"))
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.84))

                Spacer(minLength: 6)

                PersonalMixCollage(artworks: collageArtworks)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 8)

                Text(L(mix.title))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(L(mix.subtitle))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(14)
        }
        .frame(width: 168, height: 216)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
    }
}

private struct PersonalMixCollage: View {
    var artworks: [String]

    var body: some View {
        ZStack {
            if artworks.count >= 3 {
                Artwork(url: artworks[1], radius: 8)
                    .frame(width: 48, height: 48)
                    .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.24), lineWidth: 0.6) }
                    .rotationEffect(.degrees(-8))
                    .offset(x: -30, y: 6)
                Artwork(url: artworks[2], radius: 8)
                    .frame(width: 48, height: 48)
                    .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.24), lineWidth: 0.6) }
                    .rotationEffect(.degrees(8))
                    .offset(x: 30, y: 6)
                Artwork(url: artworks[0], radius: 9)
                    .frame(width: 60, height: 60)
                    .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.32), lineWidth: 0.8) }
                    .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
            } else if artworks.count == 2 {
                Artwork(url: artworks[1], radius: 8)
                    .frame(width: 52, height: 52)
                    .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.24), lineWidth: 0.6) }
                    .rotationEffect(.degrees(-6))
                    .offset(x: -18, y: 4)
                Artwork(url: artworks[0], radius: 9)
                    .frame(width: 58, height: 58)
                    .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.32), lineWidth: 0.8) }
                    .rotationEffect(.degrees(4))
                    .offset(x: 16, y: -2)
                    .shadow(color: .black.opacity(0.26), radius: 6, y: 3)
            } else if let first = artworks.first {
                Artwork(url: first, radius: 10)
                    .frame(width: 66, height: 66)
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.30), lineWidth: 0.8) }
                    .shadow(color: .black.opacity(0.26), radius: 6, y: 3)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.18))
                        .frame(width: 62, height: 62)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(height: 76)
        .accessibilityHidden(true)
    }
}

private struct HomeStationItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let query: String
    let symbol: String
    let colors: [Color]
    let seedTracks: [Track]
}

private struct HomeStationsShelf: View {
    var stations: [HomeStationItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrowseShelfHeading(title: "Senin İçin İstasyonlar")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(stations) { station in
                        HomeStationCard(station: station)
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct HomeStationCard: View {
    var station: HomeStationItem
    @EnvironmentObject private var player: MusicPlayer

    var body: some View {
        let localizedTitle = L(station.title)
        let active = player.activeStationTitle == localizedTitle
        Button {
            player.startStation(title: localizedTitle, query: station.query, seedTracks: station.seedTracks)
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: station.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

                if let art = station.seedTracks.first?.artwork {
                    Artwork(url: art, radius: 0)
                        .opacity(0.24)
                }

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.28),
                        .init(color: .black.opacity(0.68), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: station.symbol)
                            .font(.system(size: 11, weight: .bold))
                        Text(L("RADYO"))
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.8)
                        Spacer(minLength: 4)
                        if active {
                            ZStack {
                                Circle().fill(.black.opacity(0.48))
                                NowPlayingBars(isPlaying: player.isPlaying, color: .white, size: 11)
                            }
                            .frame(width: 26, height: 26)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.92))

                    Spacer(minLength: 6)

                    Text(localizedTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(L(station.subtitle))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.80))
                        .lineLimit(1)
                }
                .padding(12)
            }
            .frame(width: 160, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel(localizedTitle)
        .accessibilityHint(L("Çal"))
        .accessibilityIdentifier("home.station.\(station.id)")
    }
}

private struct HomeArtistItem: Identifiable {
    var id: String
    let name: String
    var artwork: String?
}

private struct HomeArtistsShelf: View {
    var artists: [HomeArtistItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrowseShelfHeading(title: "Sevdiğin Sanatçılar")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                        NavigationLink {
                            if !artist.id.isEmpty {
                                ArtistDetailView(id: artist.id, name: artist.name)
                            } else {
                                QueryView(query: artist.name, title: artist.name)
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ArtistPortrait(url: artist.artwork, name: artist.name, artistID: artist.id, preferEditorialPortrait: true)
                                    .frame(width: 104, height: 104)
                                    .clipShape(Circle())
                                Text(artist.name)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 104)
                            }
                        }
                        .buttonStyle(CardButtonStyle())
                        .accessibilityIdentifier("home.artist.\(index)")
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct HomeSpatialShelf: View {
    var title: String
    var tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                NavigationLink {
                    TrackListView(title: L(title), tracks: tracks)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(L(title))
                            .font(.title2.bold())
                            .tracking(-0.5)
                            .foregroundStyle(Color.primary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(L("Tümünü göster"))

                DolbyAtmosBadge(color: .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.musicElevated, in: Capsule())

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(tracks.prefix(14)) { track in
                        TrackCard(track: track, tracks: tracks, size: 160)
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct MoreToExploreSection: View {
    private let items: [(id: String, title: String, query: String)] = [
        ("genres", "Türlere Göre Göz At", "Pop"),
        ("charts", "Günlük Top 25", "Top Hits"),
        ("moods", "Ruh Halleri ve Etkinlikler", "Chill"),
        ("spatial", "Uzamsal Ses Seçkisi", "Akustik")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrowseShelfHeading(title: "Keşfedilecek Daha Fazla Şey")
            VStack(spacing: 10) {
                ForEach(items, id: \.id) { item in
                    NavigationLink {
                        QueryView(query: item.query, title: L(item.title))
                    } label: {
                        HStack {
                            Text(L(item.title))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.coral)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(TileButtonStyle())
                    .accessibilityIdentifier("explore.more.\(item.id)")
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct DiscoverView: View {
    @State private var sections: [HomeSection] = []
    @State private var failure: String?
    @State private var loading = true
    @EnvironmentObject private var player: MusicPlayer

    private var heroTracks: [Track] {
        Array(sections.first?.tracks.prefix(6) ?? [])
    }
    private var remainingSections: [HomeSection] {
        HomeFeed.distinct(sections, excluding: heroTracks)
    }
    private var chartTracks: [Track] {
        let base = remainingSections.first?.tracks ?? sections.first?.tracks ?? []
        return Array(base.prefix(16))
    }
    private var spatialTracks: [Track] {
        let later = remainingSections.dropFirst().flatMap(\.tracks)
        let combined = later.isEmpty ? (remainingSections.flatMap(\.tracks) + heroTracks) : later
        var seen = Set<String>()
        return Array(combined.filter { seen.insert($0.id).inserted }.prefix(14))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                if loading && sections.isEmpty {
                    MusicLoadingView()
                }

                // Editorial featured hero banners
                if !heroTracks.isEmpty {
                    DiscoverHeroShelf(title: "Öne çıkanlar", tracks: heroTracks, cycleEyebrows: true)
                }

                if !(sections.isEmpty && failure != nil) {
                    DiscoverQuickPills()
                }

                if !chartTracks.isEmpty {
                    ChartTrackShelf(title: "Günlük Top 25", tracks: chartTracks)
                }

                if !(sections.isEmpty && failure != nil) {
                    TopChartsShelf()
                }

                ForEach(Array(remainingSections.dropFirst().enumerated()), id: \.element.id) { _, section in
                    BrowseTrackShelf(
                        title: section.title,
                        subtitle: section.subtitle.isEmpty ? nil : section.subtitle,
                        tracks: section.tracks
                    )
                }

                if !spatialTracks.isEmpty {
                    HomeSpatialShelf(title: "Şimdi Dolby Atmos ile", tracks: spatialTracks)
                }

                // Unified error handling or Categories grid (must stay directly inside non-lazy VStack)
                if sections.isEmpty && failure != nil {
                    ErrorState(message: failure!) { Task { await load() } }
                        .padding(.horizontal, 20)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        BrowseShelfHeading(title: "Türler ve ruh halleri")
                        CategoryGrid()
                    }
                    MoreToExploreSection()
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

private struct DiscoverQuickPills: View {
    private let pills: [(id: String, title: String, query: String, symbol: String)] = [
        ("charts", "Listeler", "Top Hits", "chart.bar.fill"),
        ("new", "Yeni Müzikler", "Yeni Çıkanlar", "sparkles"),
        ("atmos", "Dolby Atmos", "Akustik", "dot.radiowaves.left.and.right"),
        ("moods", "Ruh Halleri", "Chill", "face.smiling"),
        ("hits", "Hit Parçalar", "Pop Hits", "flame.fill")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(pills, id: \.id) { pill in
                    NavigationLink {
                        QueryView(query: pill.query, title: L(pill.title))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: pill.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.coral)
                            Text(L(pill.title))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.musicElevated, in: Capsule())
                        .overlay {
                            Capsule().stroke(.primary.opacity(0.06), lineWidth: 0.6)
                        }
                    }
                    .buttonStyle(TileButtonStyle())
                    .accessibilityIdentifier("discover.pill.\(pill.id)")
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct ChartTrackShelf: View {
    var title: String
    var tracks: [Track]
    private let rows = 4

    var body: some View {
        let visible = Array(tracks.prefix(16))
        let columnCount = (visible.count + rows - 1) / rows
        VStack(alignment: .leading, spacing: 10) {
            BrowseShelfHeading(title: title, tracks: visible)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(0..<columnCount, id: \.self) { column in
                        VStack(spacing: 0) {
                            ForEach(0..<min(rows, max(0, visible.count - column * rows)), id: \.self) { offset in
                                let index = column * rows + offset
                                ChartTrackRow(track: visible[index], tracks: visible, rank: index + 1)
                                Divider().padding(.leading, 94)
                            }
                        }
                        .frame(width: 318)
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct ChartTrackRow: View {
    var track: Track
    var tracks: [Track]
    var rank: Int
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    private var isCurrent: Bool { player.current?.id == track.id }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                player.play(track, in: tracks)
            } label: {
                HStack(spacing: 12) {
                    Artwork(url: track.artwork, radius: 7)
                        .frame(width: 52, height: 52)
                        .overlay {
                            if player.pendingTrack?.id == track.id {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.black.opacity(0.45))
                                    ProgressView().controlSize(.small).tint(.white)
                                }
                            } else if isCurrent {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.black.opacity(0.38))
                                    NowPlayingBars(isPlaying: player.isPlaying, color: .white, size: 13)
                                }
                            }
                        }

                    Text("\(rank)")
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(isCurrent ? Color.coral : Color.primary)
                        .frame(width: 18, alignment: .center)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(track.title)
                                .font(.system(size: 16))
                                .lineLimit(1)
                            if track.explicit {
                                Image(systemName: "e.square.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(isCurrent ? Color.coral : Color.primary)

                        HStack(spacing: 4) {
                            if library.localURL(track.id) != nil {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 10))
                            }
                            Text(track.artist).lineLimit(1)
                        }
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(TrackRowButtonStyle())
            .accessibilityLabel("\(rank). \(track.title), \(track.artist)")
            .accessibilityHint(L("Çal"))
            .accessibilityIdentifier("track.row.\(track.id)")

            TrackMenu(track: track)
        }
    }
}

private struct TopChartCardModel: Identifiable {
    let id: String
    let title: String
    let region: String
    let subtitle: String
    let query: String
    var countryCode: String? = nil
    let symbol: String
    let colors: [Color]
}

private struct TopChartsShelf: View {
    private let charts: [TopChartCardModel] = [
        .init(
            id: "tr",
            title: "Top 25: Türkiye",
            region: "Türkiye",
            subtitle: "Günlük Listeler",
            query: "Türkçe Pop",
            countryCode: "tr",
            symbol: "chart.bar.fill",
            colors: [Color(red: 0.96, green: 0.16, blue: 0.28), Color(red: 0.58, green: 0.06, blue: 0.22)]
        ),
        .init(
            id: "az",
            title: "Top 25: Azerbaycan",
            region: "Azerbaycan",
            subtitle: "Günlük Listeler",
            query: "Azərbaycan",
            countryCode: "az",
            symbol: "sparkles",
            colors: [Color(red: 0.06, green: 0.56, blue: 0.68), Color(red: 0.12, green: 0.18, blue: 0.42)]
        ),
        .init(
            id: "global",
            title: "Top 25: Global",
            region: "Global",
            subtitle: "Dünya Geneli",
            query: "Pop Hits",
            countryCode: "us",
            symbol: "globe.europe.africa.fill",
            colors: [Color(red: 0.16, green: 0.42, blue: 0.94), Color(red: 0.12, green: 0.16, blue: 0.56)]
        ),
        .init(
            id: "istanbul",
            title: "Top 25: İstanbul",
            region: "İstanbul",
            subtitle: "Şehir Listesi",
            query: "İstanbul",
            symbol: "building.2.fill",
            colors: [Color(red: 0.62, green: 0.18, blue: 0.86), Color(red: 0.26, green: 0.08, blue: 0.48)]
        ),
        .init(
            id: "viral",
            title: "Top 25: Viral",
            region: "Viral",
            subtitle: "Yükselenler",
            query: "Viral Hits",
            symbol: "arrow.up.right.circle.fill",
            colors: [Color(red: 0.08, green: 0.58, blue: 0.54), Color(red: 0.06, green: 0.24, blue: 0.36)]
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrowseShelfHeading(title: "Şehir ve Ülke Listeleri")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(charts) { chart in
                        NavigationLink {
                            if let code = chart.countryCode {
                                CountryChartDetailView(countryCode: code, title: L(chart.title), colors: chart.colors, symbol: chart.symbol)
                            } else {
                                QueryView(query: chart.query, title: L(chart.title))
                            }
                        } label: {
                            TopChartCard(chart: chart)
                        }
                        .buttonStyle(CardButtonStyle())
                        .accessibilityIdentifier("discover.chart.\(chart.id)")
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct CountryChartDetailView: View {
    var countryCode: String
    var title: String
    var colors: [Color]
    var symbol: String
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var failure: String?
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: symbol)
                        .font(.system(size: 72, weight: .bold))
                        .foregroundStyle(.white.opacity(0.18))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(18)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("GÜNLÜK TOP 25"))
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.85))
                        Text(title)
                            .font(.title.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(18)
                }
                .frame(height: 156)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 8)

                if !tracks.isEmpty {
                    CollectionPlayButtons(tracks: tracks)
                        .padding(.horizontal, 20)
                }

                if loading && tracks.isEmpty {
                    ProgressView()
                        .tint(Color.coral)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else if let failure, tracks.isEmpty {
                    ErrorState(message: failure) { Task { await load() } }
                        .padding(.horizontal, 20)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 15, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(index < 3 ? Color.coral : Color.secondary)
                                    .frame(width: 26, alignment: .trailing)
                                Button {
                                    Haptics.light()
                                    player.play(track, in: tracks)
                                } label: {
                                    HStack(spacing: 12) {
                                        Artwork(url: track.artwork, radius: 7)
                                            .frame(width: 48, height: 48)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(track.title)
                                                .font(.system(size: 15.5, weight: .medium))
                                                .foregroundStyle(player.current?.id == track.id ? Color.coral : Color.primary)
                                                .lineLimit(1)
                                            HStack(spacing: 4) {
                                                if library.localURL(track.id) != nil {
                                                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 10))
                                                }
                                                Text(track.artist).lineLimit(1)
                                            }
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(TrackRowButtonStyle())
                                .accessibilityIdentifier("chart.row.\(track.id)")
                                TrackMenu(track: track)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 20)
                            Divider().padding(.leading, 118).padding(.trailing, 20)
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        failure = nil
        defer { loading = false }
        do {
            let result = try await API.shared.chartTracks(country: countryCode)
            tracks = Array(result.prefix(25))
            if tracks.isEmpty {
                tracks = try await API.shared.search(countryCode == "az" ? "Azərbaycan" : "Top Hits").tracks
            }
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct TopChartCard: View {
    var chart: TopChartCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: chart.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

                Image(systemName: chart.symbol)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white.opacity(0.18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(14)

                VStack(alignment: .leading, spacing: 0) {
                    Text("TOP")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.88))
                    Text("25")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .tracking(-1.5)
                        .foregroundStyle(.white)
                    Spacer(minLength: 4)
                    Text(L(chart.region))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(14)
            }
            .frame(width: 162, height: 162)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(L(chart.title))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(L(chart.subtitle))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 162, alignment: .leading)
        }
    }
}

private struct DiscoverHeroShelf: View {
    var title: String
    var tracks: [Track]
    var cycleEyebrows = false
    private let editorialEyebrows = ["YENİ SEÇKİ", "ÖZEL LİSTE", "ŞİMDİ DİNLE", "EDİTÖRÜN SEÇİMİ"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    DiscoverHeroCard(
                        track: track,
                        tracks: tracks,
                        eyebrow: cycleEyebrows ? editorialEyebrows[index % editorialEyebrows.count] : title
                    )
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
    @State private var tint = ArtworkPalette.fallback.bottom.color
    private var isCurrent: Bool { player.current?.id == track.id }
    private var isPending: Bool { player.pendingTrack?.id == track.id }

    var body: some View {
        Button { player.play(track, in: tracks) } label: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(eyebrow).uppercased())
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(0.5)
                    Text(track.title).font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(track.artist).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                }
                Color.clear
                    .aspectRatio(3.0 / 2.0, contentMode: .fit)
                    .overlay { Artwork(url: track.artwork, radius: 0) }
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.42),
                                .init(color: tint.opacity(0.68), location: 0.72),
                                .init(color: .black.opacity(0.84), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .bottomLeading) {
                        HStack(alignment: .bottom, spacing: 10) {
                            Text(track.album.isEmpty ? L("Bugünün ritmi burada başlıyor.") : track.album)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ZStack {
                                Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                                if isPending {
                                    ProgressView().controlSize(.small).tint(.white)
                                } else if isCurrent {
                                    NowPlayingBars(isPlaying: player.isPlaying, color: .white, size: 11)
                                } else {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .offset(x: 1)
                                }
                            }
                            .frame(width: 30, height: 30)
                        }
                        .padding(14)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .task(id: track.artwork) {
                        let url = ArtworkRequest.sized(track.artworkURL, pixels: 320)
                        if let image = await ArtworkCache.shared.image(url, fallback: track.artworkURL, maxPixels: 240),
                           let extracted = await ArtworkCache.shared.palette(image),
                           !Task.isCancelled {
                            tint = extracted.bottom.color
                        }
                    }
            }
            .containerRelativeFrame(.horizontal) { width, _ in
                min(460, max(280, width - 56))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SpotlightButtonStyle())
        .accessibilityLabel("\(track.title), \(track.artist)")
        .accessibilityHint(L("Çal"))
    }
}

private struct RadioStation: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let query: String
    let symbol: String
    let colors: [Color]
    var streamURL: URL? = nil
}

struct RadioView: View {
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    @State private var loadingID: String?
    @State private var stationArtwork: [String: String] = [:]

    private let liveStations: [RadioStation] = [
        .init(
            id: "tr-pop",
            title: "Türkçe Pop İstasyonu",
            subtitle: "En sevilen Türkçe pop parçaları",
            query: "Türkçe Pop",
            symbol: "music.mic",
            colors: [Color(red: 0.88, green: 0.22, blue: 0.44), Color(red: 0.36, green: 0.10, blue: 0.46)],
            streamURL: URL(string: "https://listen.powerapp.com.tr/powerturk/128/chunks.m3u8")
        ),
        .init(
            id: "hits",
            title: "Hit Müzik İstasyonu",
            subtitle: "Günün her anına uygun popüler hitler",
            query: "Pop Hits",
            symbol: "dot.radiowaves.left.and.right",
            colors: [Color(red: 0.98, green: 0.14, blue: 0.23), Color(red: 0.62, green: 0.08, blue: 0.24)],
            streamURL: URL(string: "https://listen.powerapp.com.tr/powerpop/128/chunks.m3u8")
        ),
        .init(
            id: "az-live",
            title: "Azerbaycan Canlı Radyo",
            subtitle: "Bakü'den kesintisiz canlı müzik yayını",
            query: "Azeri Pop",
            symbol: "dot.radiowaves.left.and.right",
            colors: [Color(red: 0.08, green: 0.48, blue: 0.72), Color(red: 0.10, green: 0.20, blue: 0.44)],
            streamURL: URL(string: "https://icecast.livetv.az/yurdfm")
        ),
        .init(
            id: "chill",
            title: "Gece & Chill İstasyonu",
            subtitle: "Geceye eşlik eden sakin ve akustik seçkiler",
            query: "Chill Akustik",
            symbol: "moon.stars.fill",
            colors: [Color(red: 0.16, green: 0.24, blue: 0.62), Color(red: 0.10, green: 0.12, blue: 0.32)],
            streamURL: URL(string: "https://ice4.somafm.com/groovesalad-128-aac")
        ),
        .init(
            id: "rap",
            title: "Hip-Hop & Ritim",
            subtitle: "Yüksek tempo ve sokakların ritmi",
            query: "Türkçe Rap",
            symbol: "waveform",
            colors: [Color(red: 0.14, green: 0.46, blue: 0.38), Color(red: 0.08, green: 0.18, blue: 0.24)]
        )
    ]

    private let genreStations: [RadioStation] = [
        .init(id: "pop", title: "Pop", subtitle: "Pop", query: "Pop", symbol: "sparkles", colors: [Color(red: 0.95, green: 0.25, blue: 0.38), Color(red: 0.72, green: 0.12, blue: 0.28)]),
        .init(id: "rock", title: "Rock", subtitle: "Rock", query: "Rock", symbol: "guitars.fill", colors: [Color(red: 0.78, green: 0.18, blue: 0.18), Color(red: 0.35, green: 0.08, blue: 0.12)]),
        .init(id: "acoustic", title: "Akustik", subtitle: "Akustik", query: "Akustik", symbol: "music.note", colors: [Color(red: 0.74, green: 0.42, blue: 0.22), Color(red: 0.42, green: 0.20, blue: 0.14)]),
        .init(id: "electronic", title: "Elektronik", subtitle: "Elektronik", query: "Electronic Dance", symbol: "bolt.fill", colors: [Color(red: 0.24, green: 0.32, blue: 0.85), Color(red: 0.14, green: 0.12, blue: 0.48)]),
        .init(id: "alternative", title: "Alternatif", subtitle: "Alternatif", query: "Alternatif", symbol: "headphones", colors: [Color(red: 0.42, green: 0.26, blue: 0.64), Color(red: 0.18, green: 0.12, blue: 0.34)]),
        .init(id: "focus", title: "Odaklan", subtitle: "Odaklan", query: "Ambient Focus", symbol: "brain.head.profile", colors: [Color(red: 0.16, green: 0.44, blue: 0.52), Color(red: 0.08, green: 0.20, blue: 0.28)]),
        .init(id: "classical", title: "Klasik", subtitle: "Klasik", query: "Classical Piano", symbol: "pianokeys", colors: [Color(red: 0.48, green: 0.36, blue: 0.24), Color(red: 0.22, green: 0.16, blue: 0.12)]),
        .init(id: "decades", title: "90'lar & 2000'ler", subtitle: "90'lar & 2000'ler", query: "90s 2000s hits", symbol: "clock.arrow.circlepath", colors: [Color(red: 0.82, green: 0.38, blue: 0.16), Color(red: 0.45, green: 0.18, blue: 0.10)])
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                personalStationCard
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 14) {
                    BrowseShelfHeading(title: "Canlı İstasyonlar")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(liveStations) { station in
                                liveStationCard(station)
                            }
                        }
                        .padding(.horizontal, 20)
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                }

                VStack(alignment: .leading, spacing: 14) {
                    BrowseShelfHeading(title: "Tür İstasyonları")
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(genreStations) { station in
                            genreStationTile(station)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.pageBackground)
        .navigationTitle(L("Radyo"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
        .task { await preloadStationArtwork() }
    }

    private var personalStationCard: some View {
        let active = player.activeStationTitle == L("Senin İstasyonun")
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.14, blue: 0.23), Color(red: 0.56, green: 0.08, blue: 0.34), Color(red: 0.14, green: 0.10, blue: 0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 210, height: 210)
                .offset(x: 185, y: -70)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("KİŞİSEL İSTASYON"))
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.88))
                    Spacer()
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 8)
                Text(L("Senin İstasyonun"))
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text(L("Sevdiğin sanatçılar ve sana özel kesintisiz müzik"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                Button {
                    Task { await playPersonalStation() }
                } label: {
                    HStack(spacing: 8) {
                        if loadingID == "personal" {
                            ProgressView().controlSize(.small).tint(Color.coral)
                        } else if active {
                            NowPlayingBars(isPlaying: player.isPlaying, color: .coral, size: 12)
                        } else {
                            Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
                        }
                        Text(L(active ? "Şimdi çalıyor" : "Çal"))
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(Color.coral)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(CardButtonStyle())
                .accessibilityIdentifier("radio.play.personal")
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(minHeight: 205)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    private func liveStationCard(_ station: RadioStation) -> some View {
        let localizedTitle = L(station.title)
        let active = player.activeStationTitle == localizedTitle
        return Button {
            Task { await playStation(station) }
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: station.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                if let art = stationArtwork[station.id] {
                    Artwork(url: art, radius: 0)
                        .opacity(0.32)
                        .blendMode(.plusLighter)
                }
                LinearGradient(
                    stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.75), location: 1.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(L("CANLI İSTASYON"), systemImage: station.symbol)
                            .font(.caption2.weight(.bold))
                            .tracking(0.6)
                            .foregroundStyle(.white.opacity(0.92))
                        Spacer()
                    }
                    Spacer()
                    Text(localizedTitle)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(L(station.subtitle))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.84))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .padding(16)
            }
            .overlay(alignment: .topTrailing) {
                if loadingID == station.id {
                    ProgressView().controlSize(.small).tint(.white).padding(14)
                } else if active {
                    ZStack {
                        Circle().fill(.black.opacity(0.45))
                        NowPlayingBars(isPlaying: player.isPlaying, color: .white, size: 12)
                    }
                    .frame(width: 30, height: 30)
                    .padding(12)
                }
            }
            .frame(width: 244, height: 288)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
        }
        .buttonStyle(SpotlightButtonStyle())
        .accessibilityLabel(localizedTitle)
        .accessibilityHint(L("Çal"))
        .accessibilityIdentifier("radio.station.\(station.id)")
    }

    private func genreStationTile(_ station: RadioStation) -> some View {
        let localizedTitle = L(station.title)
        let active = player.activeStationTitle == localizedTitle
        return Button {
            Task { await playStation(station) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    LinearGradient(colors: station.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    if loadingID == station.id {
                        ProgressView().controlSize(.small).tint(.white)
                    } else if active {
                        NowPlayingBars(isPlaying: player.isPlaying, color: .white, size: 14)
                    } else {
                        Image(systemName: station.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(localizedTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(10)
            .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
            }
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(localizedTitle)
        .accessibilityHint(L("Çal"))
        .accessibilityIdentifier("radio.genre.\(station.id)")
    }

    private func preloadStationArtwork() async {
        guard !PlaybackPreferences.savesData() else { return }
        for station in liveStations where stationArtwork[station.id] == nil {
            guard !Task.isCancelled else { return }
            if let track = try? await API.shared.search(station.query).tracks.first,
               let art = track.artwork {
                stationArtwork[station.id] = art
            }
        }
    }

    private func playPersonalStation() async {
        loadingID = "personal"
        defer { loadingID = nil }
        var seen = Set<String>()
        var seeds = (library.favorites + library.recent).filter { seen.insert($0.id).inserted }
        let queryArtist = seeds.first?.artist
        if seeds.count < 10, let home = try? await API.shared.home() {
            let extra = home.sections.flatMap(\.tracks).filter { seen.insert($0.id).inserted }
            seeds.append(contentsOf: extra.prefix(15))
        }
        let stationQuery = queryArtist?.isEmpty == false ? queryArtist! : (ListeningLocale.current.languageCode == "tr" ? "Türkçe Pop" : "Pop Hits")
        if seeds.isEmpty, let searched = try? await API.shared.search(stationQuery) {
            seeds = searched.tracks
        }
        guard !seeds.isEmpty else { return }
        player.startStation(title: L("Senin İstasyonun"), query: stationQuery, seedTracks: seeds.shuffled())
    }

    private func playStation(_ station: RadioStation) async {
        Haptics.light()
        if let streamURL = station.streamURL {
            player.playLiveRadio(
                id: station.id,
                title: L(station.title),
                subtitle: L(station.subtitle),
                streamURL: streamURL,
                artwork: stationArtwork[station.id],
                fallbackQuery: station.query
            )
            return
        }
        loadingID = station.id
        defer { loadingID = nil }
        var tracks = (try? await API.shared.search(station.query).tracks) ?? []
        if tracks.isEmpty, let home = try? await API.shared.home() {
            tracks = home.sections.flatMap(\.tracks)
        }
        guard !tracks.isEmpty else { return }
        player.startStation(title: L(station.title), query: station.query, seedTracks: tracks)
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                if loading && result.tracks.isEmpty {
                    MusicLoadingView()
                } else if let failure, result.tracks.isEmpty {
                    ErrorState(message: failure) { Task { await load() } }
                        .padding(.horizontal, 20)
                } else if result.tracks.isEmpty && result.albums.isEmpty && result.artists.isEmpty {
                    EmptyState(symbol: "music.note", title: L("Sonuç bulunamadı"), message: L("Farklı bir arama dene."))
                } else {
                    if !result.tracks.isEmpty {
                        DiscoverHeroShelf(title: "Öne çıkan", tracks: Array(result.tracks.prefix(4)))
                        CompactTrackShelf(
                            title: "Popüler Şarkılar",
                            tracks: Array(result.tracks.prefix(12)),
                            rows: min(4, max(1, result.tracks.count))
                        )
                    }

                    if !result.albums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            BrowseShelfHeading(title: "Albümler")
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 14) {
                                    ForEach(result.albums) { album in
                                        NavigationLink {
                                            AlbumDetailView(collection: album)
                                        } label: {
                                            AlbumCard(collection: album).frame(width: 152)
                                        }
                                        .buttonStyle(CardButtonStyle())
                                        .accessibilityIdentifier("album.open.\(album.id)")
                                    }
                                }
                                .padding(.horizontal, 20)
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.viewAligned)
                        }
                    }

                    if !result.artists.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            BrowseShelfHeading(title: "Sanatçılar")
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(result.artists) { artist in
                                        NavigationLink {
                                            ArtistDetailView(id: artist.id, name: artist.name)
                                        } label: {
                                            VStack(spacing: 8) {
                                                ArtistPortrait(url: artist.artwork, name: artist.name, artistID: artist.id)
                                                    .frame(width: 88, height: 88)
                                                    .clipShape(Circle())
                                                Text(artist.name)
                                                    .font(.system(size: 13.5, weight: .semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                    .frame(width: 92)
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

                    if !result.tracks.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            BrowseShelfHeading(title: "Şarkılar", tracks: result.tracks)
                            CollectionPlayButtons(tracks: result.tracks)
                                .padding(.horizontal, 20)
                            trackRows(result.tracks)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inlineLarge)
        .task { await load() }
    }

    private func load() async {
        loading = result.tracks.isEmpty
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
    @State private var suggestions: [String] = []
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

                    if scope == "catalog" && !suggestions.isEmpty {
                        suggestionBar
                    }

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
            .padding(.bottom, 104)
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
                suggestions = []
                loading = false
                failure = nil
                return
            }
            guard scope == "catalog" else {
                suggestions = []
                loading = false
                failure = nil
                return
            }
            loading = true
            failure = nil
            do {
                let targetQuery = query
                try await Task.sleep(for: .milliseconds(200))
                try Task.checkCancellation()
                async let suggested = API.shared.searchSuggestions(targetQuery)
                await search()
                let list = await suggested
                if !Task.isCancelled && targetQuery == query && scope == "catalog" {
                    suggestions = list
                }
            } catch { }
        }
        .onSubmit(of: .search) { saveHistory() }
        .onChange(of: scope) { _, value in
            if value == "catalog", filter == "playlists" { filter = "all" }
        }
    }

    private var suggestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { idx, item in
                    Button {
                        Haptics.selection()
                        query = item
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(item)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.musicElevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.suggestion.\(idx)")
                }
            }
            .padding(.horizontal, 20)
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
                .foregroundStyle(filter == value ? Color.white : Color.primary)
                .background(
                    filter == value ? Color.coral : Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.92, alpha: 1) }),
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
                    if !visibleResult.artists.isEmpty || !visibleResult.albums.isEmpty || !songs.isEmpty {
                        topResultsShelf
                    }

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
                                                ArtistPortrait(url: artist.artwork, name: artist.name, artistID: artist.id)
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

    @ViewBuilder private var topResultsShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrowseShelfHeading(title: "En İyi Sonuçlar")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if let topArtist = visibleResult.artists.first {
                        NavigationLink { artistDestination(topArtist) } label: {
                            topResultCard(
                                title: topArtist.name,
                                subtitle: L("Sanatçı"),
                                artwork: topArtist.artwork,
                                isArtist: true,
                                artistID: topArtist.id,
                                trailingSymbol: "chevron.right"
                            )
                        }
                        .buttonStyle(CardButtonStyle())
                        .accessibilityIdentifier("search.top.artist")
                    }
                    if let topTrack = songs.first {
                        Button { player.play(topTrack, in: songs) } label: {
                            topResultCard(
                                title: topTrack.title,
                                subtitle: L("Şarkı") + " · " + topTrack.artist,
                                artwork: topTrack.artwork,
                                isArtist: false,
                                trailingSymbol: player.current?.id == topTrack.id && player.isPlaying ? "pause.fill" : "play.fill"
                            )
                        }
                        .buttonStyle(CardButtonStyle())
                        .accessibilityIdentifier("search.top.song")
                    }
                    if let topAlbum = visibleResult.albums.first {
                        NavigationLink { albumDestination(topAlbum) } label: {
                            topResultCard(
                                title: topAlbum.title,
                                subtitle: L("Albüm") + " · " + topAlbum.artist,
                                artwork: topAlbum.artwork,
                                isArtist: false,
                                trailingSymbol: "chevron.right"
                            )
                        }
                        .buttonStyle(CardButtonStyle())
                        .accessibilityIdentifier("search.top.album")
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func topResultCard(title: String, subtitle: String, artwork: String?, isArtist: Bool, artistID: String? = nil, trailingSymbol: String) -> some View {
        HStack(spacing: 12) {
            if isArtist {
                ArtistPortrait(url: artwork, name: title, artistID: artistID)
                    .frame(width: 58, height: 58)
                    .clipShape(Circle())
            } else {
                Artwork(url: artwork, radius: 9)
                    .frame(width: 58, height: 58)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: trailingSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(trailingSymbol.contains("chevron") ? AnyShapeStyle(Color(uiColor: .tertiaryLabel)) : AnyShapeStyle(Color.coral))
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(width: 266)
        .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 0.6)
        )
    }

    private func playlistRow(_ playlist: SavedPlaylist) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                PlaylistDetailView(playlist: playlist)
            } label: {
                HStack(spacing: 14) {
                    PlaylistArtwork(tracks: library.tracks(in: playlist), playlistID: playlist.id)
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
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
                    ArtistPortrait(url: artist.artwork, name: artist.name, artistID: artist.id)
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
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
    var subtitleOverride: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Artwork(url: collection.artwork, radius: 12)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
            Text(collection.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(Color.primary)
            Text(subtitleOverride ?? collection.artist)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(Color.secondary)
        }
    }
}

struct AlbumDetailView: View {
    var collection: MusicCollection
    @State private var tracks: [Track] = []
    @State private var moreAlbums: [MusicCollection] = []
    @State private var failure: String?
    @State private var loading = true
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @AppStorage(LibraryPinsStore.storageKey) private var pinsValue = ""

    private var releaseYear: String? {
        if let date = collection.releaseDate, date.count >= 4 {
            return String(date.prefix(4))
        }
        return nil
    }

    private var formattedReleaseDate: String? {
        guard let raw = collection.releaseDate, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) {
            let f = DateFormatter()
            f.dateStyle = .long
            f.timeStyle = .none
            return f.string(from: date)
        }
        return releaseYear
    }

    private var totalMinutes: Int64 {
        Int64(max(0, Int(tracks.reduce(0) { $0 + $1.duration } / 60)))
    }

    private var allFavorited: Bool {
        !tracks.isEmpty && tracks.allSatisfy { library.isFavorite($0) }
    }

    private var albumPin: LibraryPin {
        LibraryPin(
            id: "album:" + collection.id,
            kind: "album",
            targetID: collection.id,
            title: collection.title,
            subtitle: collection.artist,
            artwork: collection.artwork
        )
    }
    private var isPinned: Bool { LibraryPinsStore.contains(id: albumPin.id, in: pinsValue) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .center, spacing: 18) {
                Artwork(url: collection.artwork, radius: 12)
                    .frame(width: 236, height: 236)
                    .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 10)
                    .padding(.top, 14)

                VStack(spacing: 5) {
                    Text(collection.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 20)

                    NavigationLink {
                        if let firstTrack = tracks.first, let artistID = firstTrack.artistID, !artistID.isEmpty {
                            ArtistDetailView(id: artistID, name: collection.artist)
                        } else {
                            QueryView(query: collection.artist, title: collection.artist)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(collection.artist)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(Color.coral)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.coral.opacity(0.75))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("album.artist.\(collection.artist)")
                    .padding(.horizontal, 20)

                    Text((releaseYear.map { L("Albüm") + " · " + $0 } ?? L("Albüm")).uppercased())
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Color.secondary)
                        .padding(.top, 2)
                }

                if !tracks.isEmpty {
                    CollectionPlayButtons(tracks: tracks)
                        .padding(.horizontal, 20)
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

                if !tracks.isEmpty {
                    VStack(spacing: 0) {
                        Divider().padding(.leading, 48)
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            AlbumTrackRow(
                                track: track,
                                tracks: tracks,
                                number: index + 1,
                                albumArtist: collection.artist
                            )
                            Divider().padding(.leading, 48)
                        }
                    }
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 3) {
                        if let fullDate = formattedReleaseDate {
                            Text(fullDate)
                        }
                        Text(String(format: L("%lld şarkı, %lld dakika"), Int64(tracks.count), totalMinutes))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    if !moreAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            BrowseShelfHeading(title: "Sanatçının Diğer Albümleri")
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 14) {
                                    ForEach(moreAlbums) { album in
                                        NavigationLink {
                                            AlbumDetailView(collection: album)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 7) {
                                                Artwork(url: album.artwork, radius: 10)
                                                    .frame(width: 148, height: 148)
                                                    .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                                                Text(album.title)
                                                    .font(.system(size: 13.5, weight: .semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Text(album.releaseDate.map { String($0.prefix(4)) } ?? album.artist)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 148, alignment: .leading)
                                        }
                                        .buttonStyle(CardButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 20)
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.viewAligned)
                        }
                        .padding(.top, 14)
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard !tracks.isEmpty else { return }
                    if allFavorited {
                        tracks.forEach { if library.isFavorite($0) { library.toggleFavorite($0) } }
                    } else {
                        tracks.forEach { if !library.isFavorite($0) { library.toggleFavorite($0) } }
                    }
                } label: {
                    Image(systemName: allFavorited ? "checkmark" : "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(Color.coral)
                .disabled(tracks.isEmpty)
                .accessibilityLabel(L(allFavorited ? "Favorilerden çıkar" : "Favorilere ekle"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        pinsValue = LibraryPinsStore.toggle(albumPin, in: pinsValue)
                    } label: {
                        Label(L(isPinned ? "Sabitlemeyi Kaldır" : "Kütüphaneye Sabitle"), systemImage: isPinned ? "pin.slash" : "pin")
                    }
                    if !tracks.isEmpty {
                        Button {
                            tracks.forEach { downloads.enqueue($0) }
                        } label: {
                            Label(L("Tümünü indir"), systemImage: "arrow.down.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(Color.primary)
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        failure = nil
        defer { loading = false }
        do {
            let loaded = try await API.shared.album(collection.id).tracks
            tracks = loaded
            if let artistID = loaded.first?.artistID, !artistID.isEmpty,
               !CommandLine.arguments.contains("-serverURL"),
               moreAlbums.isEmpty {
                Task {
                    if let profile = try? await API.shared.artist(artistID) {
                        let filtered = profile.albums.filter { $0.id != collection.id }
                        if !filtered.isEmpty { moreAlbums = Array(filtered.prefix(10)) }
                    }
                }
            }
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct AlbumTrackRow: View {
    var track: Track
    var tracks: [Track]
    var number: Int
    var albumArtist: String
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore

    private var isCurrent: Bool { player.current?.id == track.id }
    private var showArtistSubtitle: Bool {
        !track.artist.isEmpty && NativeCatalog.normalized(track.artist) != NativeCatalog.normalized(albumArtist)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                player.play(track, in: tracks)
            } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        if library.isFavorite(track) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(Color.coral)
                        } else {
                            Color.clear.frame(width: 7, height: 7)
                        }
                        Group {
                            if player.pendingTrack?.id == track.id {
                                ProgressView().controlSize(.mini).tint(Color.coral)
                            } else if isCurrent {
                                NowPlayingBars(isPlaying: player.isPlaying, color: .coral, size: 12)
                            } else {
                                Text("\(number)")
                                    .font(.system(size: 15, weight: .regular))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .frame(width: 20, alignment: .center)
                    }
                    .frame(width: 32, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(track.title)
                                .font(.system(size: 16))
                                .foregroundStyle(isCurrent ? Color.coral : Color.primary)
                                .lineLimit(1)
                            if track.explicit {
                                Image(systemName: "e.square.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        if showArtistSubtitle {
                            Text(track.artist)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if library.localURL(track.id) != nil {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(TrackRowButtonStyle())
            .accessibilityLabel("\(track.title), \(track.artist)")
            .accessibilityHint(L("Çal"))
            .accessibilityIdentifier("track.row.\(track.id)")
            .contextMenu {
                Button { Haptics.light(); library.toggleFavorite(track) } label: {
                    Label(library.isFavorite(track) ? L("Favorilerden çıkar") : L("Favorilere ekle"),
                          systemImage: library.isFavorite(track) ? "star.slash" : "star")
                }
                Button { Haptics.light(); player.playNext(track) } label: {
                    Label(L("Sıradaki çal"), systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button { Haptics.light(); player.addToQueue(track) } label: {
                    Label(L("Sıraya ekle"), systemImage: "text.line.last.and.arrowtriangle.forward")
                }
                ShareLink(item: TrackMenu.shareText(for: track)) {
                    Label(L("Paylaş"), systemImage: "square.and.arrow.up")
                }
            }

            TrackMenu(track: track)
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
    @State private var similarArtists: [MusicArtist] = []
    @State private var failure: String?
    @State private var compactTitle = false
    @EnvironmentObject private var player: MusicPlayer
    @AppStorage("followedArtists") private var followed = ""
    @AppStorage(LibraryPinsStore.storageKey) private var pinsValue = ""

    private var isFollowing: Bool {
        followed.split(separator: "\n").contains { $0.split(separator: "|", maxSplits: 1).first == Substring(id) }
    }
    private var artwork: String? { details?.artist.banner ?? details?.artist.artwork }
    private var displayName: String { details?.artist.name ?? name }
    private var artistPin: LibraryPin {
        LibraryPin(
            id: "artist:" + id,
            kind: "artist",
            targetID: id,
            title: displayName,
            subtitle: L("Sanatçı"),
            artwork: details?.artist.artwork ?? details?.artist.banner
        )
    }
    private var isPinned: Bool { LibraryPinsStore.contains(id: artistPin.id, in: pinsValue) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Full-bleed edge-to-edge hero header
                VStack(spacing: 0) {
                    if let artwork {
                        ZStack(alignment: .bottom) {
                            Artwork(url: artwork, radius: 0)
                                .frame(maxWidth: .infinity)
                                .frame(height: 376)
                                .clipped()

                            // Top status-bar scrim for back/star/menu legibility
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.42), location: 0.0),
                                    .init(color: .black.opacity(0.16), location: 0.14),
                                    .init(color: .clear, location: 0.26)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )

                            // Smooth bottom blend into page background
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.48),
                                    .init(color: Color.pageBackground.opacity(0.76), location: 0.75),
                                    .init(color: Color.pageBackground, location: 0.98)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )

                            heroTitleAndPlay(centered: false)
                                .padding(.bottom, 12)
                        }
                        .frame(height: 376)
                    } else {
                        VStack(spacing: 16) {
                            ArtistPortrait(url: nil, name: name)
                                .frame(width: 132, height: 132)
                            heroTitleAndPlay(centered: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 96)
                        .padding(.bottom, 8)
                    }
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
        .ignoresSafeArea(edges: .top)
        .coordinateSpace(name: "artistScroll")
        .background(Color.pageBackground)
        .navigationTitle(compactTitle ? name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(compactTitle ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleFollow) {
                    Image(systemName: isFollowing ? "star.fill" : "star")
                }
                .foregroundStyle(isFollowing ? Color.coral : .primary)
                .accessibilityLabel(isFollowing ? L("Takibi bırak") : L("Takip et"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        pinsValue = LibraryPinsStore.toggle(artistPin, in: pinsValue)
                    } label: {
                        Label(L(isPinned ? "Sabitlemeyi Kaldır" : "Kütüphaneye Sabitle"), systemImage: isPinned ? "pin.slash" : "pin")
                    }
                    if let tracks = details?.tracks, !tracks.isEmpty {
                        Button {
                            let shuffled = tracks.shuffled()
                            if let first = shuffled.first { player.play(first, in: shuffled) }
                        } label: {
                            Label(L("Karıştır"), systemImage: "shuffle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(.primary)
            }
        }
        .task(id: id) { await load() }
    }

    private func heroTitleAndPlay(centered: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            if centered { Spacer(minLength: 0) }
            Text(displayName)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(centered ? .center : .leading)
                .lineLimit(2)
            if !centered { Spacer(minLength: 8) }
            if let tracks = details?.tracks, let first = tracks.first {
                Button {
                    player.play(first, in: tracks)
                } label: {
                    ZStack {
                        Circle().fill(Color.coral)
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 1)
                    }
                    .frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
                }
                .buttonStyle(CardButtonStyle())
                .accessibilityLabel(L("Çal"))
                .accessibilityIdentifier("artist.play")
            }
            if centered { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: Bool.self) { geometry in
            geometry.frame(in: .named("artistScroll")).minY < 108
        } action: { compactTitle = $0 }
    }

    private func artistContent(_ details: ArtistResponse) -> some View {
        let albums = details.albums.filter { $0.kind.lowercased() != "single" }
        let singles = details.albums.filter { $0.kind.lowercased() == "single" }
        let latest = details.featured ?? details.albums.first
        let essential = albums.count >= 2 ? (albums.first(where: { $0.id != latest?.id }) ?? albums[0]) : nil

        return VStack(alignment: .leading, spacing: 28) {
            if let release = latest {
                latestReleaseCard(release)
            }

            if !details.tracks.isEmpty {
                CompactTrackShelf(title: "En çok dinlenenler", tracks: details.tracks, rows: 4)
            }

            if let essential {
                essentialAlbumCard(essential)
            }

            if !albums.isEmpty {
                releaseShelf(title: "Albümler", items: albums, fallbackKind: "Albüm")
            }

            if !singles.isEmpty {
                releaseShelf(title: "Tekliler", items: singles, fallbackKind: "Tekli")
            } else if albums.isEmpty && !details.albums.isEmpty {
                releaseShelf(title: "Albümler", items: details.albums, fallbackKind: "Albüm")
            }

            if !details.tracks.isEmpty {
                ArtistStationBanner(
                    artistName: name,
                    displayName: displayName,
                    seedTracks: details.tracks
                )
            }

            if !similarArtists.isEmpty {
                SimilarArtistsShelf(artists: similarArtists)
            }
        }
    }

    private func latestReleaseCard(_ release: MusicCollection) -> some View {
        let year = releaseYear(for: release)
        let caption = year.map { L("SON ÇIKAN") + " · " + $0 } ?? L("SON ÇIKAN")
        let kindTitle = L(release.kind.lowercased() == "single" ? "Tekli" : "Albüm")
        return NavigationLink {
            AlbumDetailView(collection: release)
        } label: {
            HStack(spacing: 14) {
                Artwork(url: release.artwork, radius: 10)
                    .frame(width: 106, height: 106)
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(caption)
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.coral)
                    Text(release.title)
                        .font(.headline.bold())
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(kindTitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(CardButtonStyle())
        .padding(.horizontal, 20)
        .accessibilityIdentifier("artist.latest")
    }

    private func essentialAlbumCard(_ album: MusicCollection) -> some View {
        let year = releaseYear(for: album)
        let subtitle = year.map { L("Albüm") + " · " + $0 } ?? L("Albüm")
        return NavigationLink {
            AlbumDetailView(collection: album)
        } label: {
            HStack(spacing: 14) {
                Artwork(url: album.artwork, radius: 10)
                    .frame(width: 90, height: 90)
                    .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("TEMEL ALBÜM"))
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.coral)
                    Text(album.title)
                        .font(.headline.bold())
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(CardButtonStyle())
        .padding(.horizontal, 20)
        .accessibilityIdentifier("artist.essential")
    }

    private func releaseShelf(title: String, items: [MusicCollection], fallbackKind: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            BrowseShelfHeading(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink {
                            AlbumDetailView(collection: item)
                        } label: {
                            AlbumCard(
                                collection: item,
                                subtitleOverride: releaseSubtitle(for: item, fallbackKind: fallbackKind)
                            )
                            .frame(width: 158)
                        }
                        .buttonStyle(CardButtonStyle())
                        .accessibilityIdentifier("album.open.\(item.id)")
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func releaseYear(for item: MusicCollection) -> String? {
        guard let date = item.releaseDate, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }

    private func releaseSubtitle(for item: MusicCollection, fallbackKind: String) -> String {
        if let year = releaseYear(for: item) { return year }
        return L(item.kind.lowercased() == "single" ? "Tekli" : fallbackKind)
    }

    private func toggleFollow() {
        let value = id + "|" + name
        var values = followed.components(separatedBy: "\n").filter { !$0.isEmpty && $0.split(separator: "|", maxSplits: 1).first != Substring(id) }
        if !isFollowing { values.append(value) }
        followed = values.joined(separator: "\n")
    }

    private func load() async {
        failure = nil
        similarArtists = []
        do {
            let fetched = try await API.shared.artist(id)
            try Task.checkCancellation()
            details = fetched
            let queryName = fetched.artist.name.isEmpty ? name : fetched.artist.name
            if let searched = try? await API.shared.search(queryName), !Task.isCancelled {
                var seen = Set<String>()
                similarArtists = Array(
                    searched.artists
                        .filter { $0.id != id && seen.insert($0.id).inserted }
                        .prefix(12)
                )
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }
}

private struct ArtistStationBanner: View {
    var artistName: String
    var displayName: String
    var seedTracks: [Track]
    @EnvironmentObject private var player: MusicPlayer

    var body: some View {
        let active = player.activeStationTitle == artistName
        Button {
            player.startStation(title: artistName, query: artistName, seedTracks: seedTracks)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.14, blue: 0.23), Color(red: 0.62, green: 0.08, blue: 0.30)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    if active {
                        NowPlayingBars(isPlaying: player.isPlaying, color: .white, size: 16)
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: L("%@ İstasyonu"), displayName))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(L("Sanatçı İstasyonu"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle().fill(Color.coral.opacity(0.14))
                    Image(systemName: active ? "waveform" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.coral)
                        .offset(x: active ? 0 : 1)
                }
                .frame(width: 34, height: 34)
            }
            .padding(12)
            .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(CardButtonStyle())
        .padding(.horizontal, 20)
        .accessibilityIdentifier("artist.station")
    }
}

private struct SimilarArtistsShelf: View {
    var artists: [MusicArtist]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrowseShelfHeading(title: "Benzer Sanatçılar")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(artists) { similar in
                        NavigationLink {
                            ArtistDetailView(id: similar.id, name: similar.name)
                        } label: {
                            VStack(spacing: 8) {
                                ArtistPortrait(url: similar.artwork, name: similar.name)
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                Text(similar.name)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 100)
                            }
                        }
                        .buttonStyle(CardButtonStyle())
                        .accessibilityIdentifier("artist.similar.\(similar.id)")
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}
