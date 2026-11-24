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
    var personalized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrowseShelfHeading(title: title, tracks: tracks)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(tracks.prefix(6)) { track in
                        HomeSpotlightCard(track: track, tracks: tracks, eyebrow: personalized ? "SENİN İÇİN" : "Öne Çıkan")
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
                            .init(color: .black.opacity(0.28), location: 0.0),
                            .init(color: .clear, location: 0.25),
                            .init(color: .clear, location: 0.46),
                            .init(color: tint.opacity(0.65), location: 0.72),
                            .init(color: .black.opacity(0.86), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .topLeading) {
                    Text(L(eyebrow).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                        .padding(16)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
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
                                .init(color: .clear, location: 0.48),
                                .init(color: .black.opacity(0.74), location: 1.0)
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
}

struct RadioView: View {
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    @State private var loadingID: String?
    @State private var stationArtwork: [String: String] = [:]

    private let liveStations: [RadioStation] = [
        .init(
            id: "hits",
            title: "Hit Müzik İstasyonu",
            subtitle: "Günün her anına uygun popüler hitler",
            query: "Pop Hits",
            symbol: "dot.radiowaves.left.and.right",
            colors: [Color(red: 0.98, green: 0.14, blue: 0.23), Color(red: 0.62, green: 0.08, blue: 0.24)]
        ),
        .init(
            id: "tr-pop",
            title: "Türkçe Pop İstasyonu",
            subtitle: "En sevilen Türkçe pop parçaları",
            query: "Türkçe Pop",
            symbol: "music.mic",
            colors: [Color(red: 0.88, green: 0.22, blue: 0.44), Color(red: 0.36, green: 0.10, blue: 0.46)]
        ),
        .init(
            id: "chill",
            title: "Gece & Chill İstasyonu",
            subtitle: "Geceye eşlik eden sakin ve akustik seçkiler",
            query: "Chill Akustik",
            symbol: "moon.stars.fill",
            colors: [Color(red: 0.16, green: 0.24, blue: 0.62), Color(red: 0.10, green: 0.12, blue: 0.32)]
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
        .accessibilityIdentifier("radio.personal")
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
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @AppStorage(LibraryPinsStore.storageKey) private var pinsValue = ""

    private var releaseYear: String? {
        if let date = collection.releaseDate, date.count >= 4 {
            return String(date.prefix(4))
        }
        return nil
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
                        if let year = releaseYear {
                            Text(year)
                        }
                        Text(String(format: L("%lld şarkı, %lld dakika"), Int64(tracks.count), totalMinutes))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
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
            tracks = try await API.shared.album(collection.id).tracks
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
    @State private var failure: String?
    @State private var compactTitle = false
    @EnvironmentObject private var player: MusicPlayer
    @AppStorage("followedArtists") private var followed = ""
    @AppStorage(LibraryPinsStore.storageKey) private var pinsValue = ""

    private var isFollowing: Bool {
        followed.split(separator: "\n").contains { $0.split(separator: "|", maxSplits: 1).first == Substring(id) }
    }
    private var artwork: String? { details?.artist.banner ?? details?.artist.artwork }
    private var artistPin: LibraryPin {
        LibraryPin(
            id: "artist:" + id,
            kind: "artist",
            targetID: id,
            title: details?.artist.name ?? name,
            subtitle: L("Sanatçı"),
            artwork: details?.artist.artwork ?? details?.artist.banner
        )
    }
    private var isPinned: Bool { LibraryPinsStore.contains(id: artistPin.id, in: pinsValue) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Full-bleed Apple Music hero header
                VStack(spacing: 0) {
                    if let artwork {
                        ZStack(alignment: .bottom) {
                            Artwork(url: artwork, radius: 0)
                                .frame(height: 316)
                                .clipped()

                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .clear, location: 0.36),
                                    .init(color: Color.pageBackground.opacity(0.65), location: 0.74),
                                    .init(color: Color.pageBackground, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )

                            heroTitleAndPlay(centered: false)
                                .padding(.bottom, 10)
                        }
                    } else {
                        VStack(spacing: 16) {
                            ArtistPortrait(url: nil, name: name)
                                .frame(width: 132, height: 132)
                            heroTitleAndPlay(centered: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
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
        .task { await load() }
    }

    private func heroTitleAndPlay(centered: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            if centered { Spacer(minLength: 0) }
            Text(details?.artist.name ?? name)
                .font(.system(size: 32, weight: .bold))
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
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 1)
                    }
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
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
            geometry.frame(in: .named("artistScroll")).minY < 24
        } action: { compactTitle = $0 }
    }

    private func artistContent(_ details: ArtistResponse) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            if let release = details.featured ?? details.albums.first {
                NavigationLink {
                    AlbumDetailView(collection: release)
                } label: {
                    HStack(spacing: 14) {
                        Artwork(url: release.artwork, radius: 10)
                            .frame(width: 96, height: 96)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L(release.releaseLabel).uppercased())
                                .font(.caption2.weight(.bold))
                                .tracking(0.5)
                                .foregroundStyle(Color.coral)
                            Text(release.title)
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                                .lineLimit(2)
                            if let date = release.releaseDate, date.count >= 4 {
                                Text(String(date.prefix(4)))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.secondary)
                            } else {
                                Text(release.artist)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.secondary)
                                    .lineLimit(1)
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
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
                }
                .buttonStyle(CardButtonStyle())
                .padding(.horizontal, 20)
                .accessibilityIdentifier("artist.latest")
            }

            if !details.tracks.isEmpty {
                CompactTrackShelf(title: "En çok dinlenenler", tracks: details.tracks, rows: 4)
            }

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
                                        AlbumCard(collection: album).frame(width: 158)
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
                                        AlbumCard(collection: single).frame(width: 158)
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
                                        AlbumCard(collection: album).frame(width: 158)
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
