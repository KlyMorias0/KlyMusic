import SwiftUI

// A compact, artwork-led layout keeps music within reach on small displays.
struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: MusicPlayer
    @State private var sections: [HomeSection] = []
    @State private var loading = true
    @State private var failure: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var highlights: [Track] { Array((sections.first?.tracks ?? []).prefix(4)) }
    private var artists: [Track] {
        var seen = Set<String>()
        return Array(sections.flatMap(\.tracks).filter { $0.artistID != nil && seen.insert($0.artist).inserted }.prefix(10))
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                if !highlights.isEmpty {
                    featured
                } else if loading {
                    MusicLoadingView().padding(.top, 24)
                }
                if let failure, sections.isEmpty { ErrorState(message: failure) { Task { await load() } }.padding(.horizontal, 22) }
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    if index == 0 { rankedShelf(section) }
                    else { BrowseTrackShelf(title: section.title, subtitle: section.subtitle, tracks: section.tracks) }
                }
                if !library.recent.isEmpty { quickListening }
                if !artists.isEmpty { artistShelf }
            }.padding(.top, 8).padding(.bottom, 32)
        }
        .background(Color.musicBackground)
        .navigationTitle("Dinle").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
        }
        .refreshable { await load() }
        .task(id: ListeningLocale.current.cacheKey) { await load() }
    }
    private var featured: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrowseShelfHeading(title: "Senin için")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(highlights) { track in
                        FeaturedTrackCard(track: track, tracks: sections.first?.tracks ?? [])
                    }
                }.padding(.horizontal, 22).scrollTargetLayout()
            }.scrollTargetBehavior(.viewAligned)
        }
    }
    private var quickListening: some View {
        VStack(alignment: .leading, spacing: 16) {
            BrowseShelfHeading(title: "Tekrar çal")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(Array(library.recent.prefix(6).enumerated()), id: \.element.id) { index, track in
                        Button { player.resume(track); player.isPresented = true } label: {
                            HStack(spacing: 12) {
                                Artwork(url: track.artwork, radius: 4).frame(width: 54, height: 54)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                                    Text(track.artist).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                                }.frame(width: 124, alignment: .leading)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier(index == 0 ? "home.resume" : "home.recent.\(track.id)")
                            .accessibilityLabel("\(track.title), \(track.artist)")
                    }
                }.padding(.horizontal, 22)
            }
        }
    }
    private func rankedShelf(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            BrowseShelfHeading(title: section.title, caption: section.subtitle, tracks: section.tracks)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 26) {
                    ForEach(0..<((min(section.tracks.count, 9) + 2) / 3), id: \.self) { column in
                        VStack(spacing: 0) {
                            ForEach(Array(section.tracks.enumerated()).dropFirst(column * 3).prefix(3), id: \.element.id) { index, track in
                                TrackRow(track: track, tracks: section.tracks, number: index + 1)
                                if index % 3 != 2 { Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5).padding(.leading, 88) }
                            }
                        }.frame(width: typeSize.isAccessibilitySize ? 340 : 310)
                    }
                }.padding(.horizontal, 22).scrollTargetLayout()
            }.scrollTargetBehavior(.viewAligned)
        }
    }
    private var artistShelf: some View {
        VStack(alignment: .leading, spacing: 19) {
            BrowseShelfHeading(title: "Sanatçılar")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(artists) { track in
                        NavigationLink { ArtistDetailView(id: track.artistID ?? "", name: track.artist) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Artwork(url: track.artwork, radius: 60).frame(width: 112, height: 112)
                                Text(track.artist).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                            }.frame(width: 112, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 22)
            }
        }
    }
    private func load() async {
        loading = true; failure = nil
        defer { loading = false }
        do { sections = try await API.shared.home().sections; player.warm(sections.first?.tracks ?? []) }
        catch is CancellationError { }
        catch { failure = error.localizedDescription }
    }
}

private struct FeaturedTrackCard: View {
    var track: Track
    var tracks: [Track]
    @EnvironmentObject private var player: MusicPlayer
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 18
    var body: some View {
        Button { player.play(track, in: tracks); player.isPresented = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                Artwork(url: track.artwork, radius: 10).frame(width: 224, height: 224)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "play.fill").font(.system(size: 15, weight: .semibold))
                            .offset(x: 1).foregroundStyle(.black)
                            .frame(width: 40, height: 40).background(.white, in: Circle()).padding(12)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.system(size: titleSize, weight: .semibold)).tracking(-0.35)
                        .foregroundStyle(.primary).lineLimit(1)
                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(width: 224, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(track.title), \(track.artist)").accessibilityHint(L("Çal"))
    }
}

private struct BrowseShelfHeading: View {
    var title: String
    var caption: String? = nil
    var tracks: [Track]? = nil
    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L(title)).font(.title3.weight(.bold)).tracking(-0.4).lineLimit(2)
                if let caption, !caption.isEmpty {
                    Text(L(caption)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let tracks {
                NavigationLink { TrackListView(title: title, tracks: tracks) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(width: 44, height: 44)
                }.accessibilityLabel("Tümünü göster")
            }
        }.padding(.horizontal, 22)
    }
}

private struct BrowseTrackShelf: View {
    var title: String
    var subtitle: String? = nil
    var tracks: [Track]
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            BrowseShelfHeading(title: title, caption: subtitle, tracks: tracks)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(tracks.prefix(14)) { TrackCard(track: $0, tracks: tracks, size: 152) }
                }.padding(.horizontal, 22)
            }
        }
    }
}

private struct MusicMood: Identifiable {
    var id: String { query }
    var title: String
    var subtitle: String
    var query: String
    var symbol: String
    static var all: [MusicMood] {
        let turkish = ListeningLocale.current.languageCode == "tr"
        return [
            .init(title: turkish ? "Türkçe Rap" : "Hip-Hop", subtitle: "Sokakların sesi", query: turkish ? "Türkçe Rap" : "hip hop", symbol: "waveform"),
            .init(title: turkish ? "Türkçe Pop" : "Pop", subtitle: "Birlikte söyle", query: turkish ? "Türkçe Pop" : "pop", symbol: "mic.fill"),
            .init(title: "Gece", subtitle: "Geceye bir şarkı", query: turkish ? "gece" : "night drive", symbol: "moon.stars.fill"),
            .init(title: "Sakin", subtitle: "Biraz yavaşla", query: "chill", symbol: "water.waves"),
            .init(title: "Enerji", subtitle: "Hareketin ritmi", query: "workout", symbol: "bolt.fill"),
            .init(title: "Rock", subtitle: "Sesi aç", query: "rock", symbol: "guitars.fill"),
            .init(title: "Jazz", subtitle: "Zamana ara ver", query: "jazz", symbol: "pianokeys"),
            .init(title: "Odaklan", subtitle: "Kendi alanın", query: "lofi", symbol: "headphones")
        ]
    }
}

struct DiscoverView: View {
    @State private var tracks: [Track] = []
    @State private var sectionTitle = "Dünyanın ritmi"
    @State private var covers: [String: String] = [:]
    @State private var failure: String?
    @EnvironmentObject private var player: MusicPlayer
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 18) {
                    BrowseShelfHeading(title: "Türler ve ruh halleri")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 270 : 145), spacing: 12)], spacing: 12) {
                        ForEach(MusicMood.all) { mood in
                            NavigationLink { QueryView(query: mood.query, title: L(mood.title)) } label: {
                                MoodTile(mood: mood, artwork: covers[mood.id])
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 22)
                }
                if !tracks.isEmpty { BrowseTrackShelf(title: sectionTitle, subtitle: nil, tracks: tracks) }
                if let failure, tracks.isEmpty { ErrorState(message: failure) { Task { await load() } }.padding(.horizontal, 22) }
            }.padding(.bottom, 32)
        }.background(Color.musicBackground)
            .navigationTitle("Keşfet").navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
            }
            .task(id: ListeningLocale.current.cacheKey) { await load() }
            .refreshable { await load() }
    }
    private func load() async {
        failure = nil
        do {
            let sections = try await API.shared.home().sections
            tracks = sections.first?.tracks ?? []
            sectionTitle = sections.first?.title ?? "Şimdi keşfet"
            let artwork = sections.flatMap(\.tracks).compactMap(\.artwork)
            let quietArtwork = sections.first(where: { $0.id.hasPrefix("calm") })?.tracks.compactMap(\.artwork) ?? []
            for (index, mood) in MusicMood.all.enumerated() {
                let pool = ["chill", "lofi"].contains(mood.query) && !quietArtwork.isEmpty ? quietArtwork : artwork
                if !pool.isEmpty { covers[mood.id] = pool[index % pool.count] }
            }
        } catch is CancellationError { }
        catch { failure = error.localizedDescription }
    }
}

private struct MoodTile: View {
    var mood: MusicMood
    var artwork: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Artwork(url: artwork, radius: 10).aspectRatio(1.35, contentMode: .fit)
            Text(L(mood.title)).font(.headline).foregroundStyle(.primary).lineLimit(2)
            Text(L(mood.subtitle)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(.bottom, 6)
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
            VStack(alignment: .leading, spacing: 24) {
                if let track = result.tracks.first {
                    CollectionCoverHeader(artwork: track.artwork, eyebrow: "Seçki", title: title, subtitle: nil)
                }
                if loading { ProgressView().frame(maxWidth: .infinity).padding(60) }
                else if let failure { ErrorState(message: failure) { Task { await load() } }.padding(.horizontal, 22) }
                else if result.tracks.isEmpty { EmptyState(symbol: "music.note.list", title: "Henüz şarkı yok", message: "Farklı bir şarkı veya sanatçı adıyla tekrar dene.") }
                else {
                    BrowseShelfHeading(title: "Şarkılar")
                    LazyVStack(spacing: 2) {
                        ForEach(Array(result.tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, tracks: result.tracks, number: index + 1)
                        }
                    }.padding(.horizontal, 22)
                }
            }.padding(.bottom, 32)
        }.background(Color.musicBackground).navigationTitle(title).navigationBarTitleDisplayMode(.inline).task { await load() }
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
    @State private var filter = "songs"
    @State private var suggestions: [Track] = []
    @EnvironmentObject private var player: MusicPlayer
    @AppStorage("searchHistory") private var historyData = ""
    private var history: [String] { historyData.components(separatedBy: "\n").filter { !$0.isEmpty } }
    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !hasQuery { discovery }
                else {
                    HStack(spacing: 9) {
                        filterButton("Şarkılar", value: "songs")
                        filterButton("Albümler", value: "albums")
                        filterButton("Sanatçılar", value: "artists")
                    }.padding(.top, 6)
                    if loading { ProgressView().frame(maxWidth: .infinity).padding(40) }
                    else if let failure { ErrorState(message: failure) { Task { await search() } } }
                    else { results }
                }
            }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 32)
        }.background(Color.musicBackground)
            .navigationTitle("Ara").navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "Şarkı, sanatçı veya albüm")
            .scrollDismissesKeyboard(.interactively)
            .task(id: ListeningLocale.current.cacheKey) { suggestions = (try? await API.shared.home().sections.first?.tracks) ?? [] }
            .task(id: query) {
                guard hasQuery else { result = SearchResponse(); loading = false; failure = nil; return }
                result = SearchResponse(); loading = true; failure = nil
                do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation(); await search() } catch { }
            }.onSubmit(of: .search) { saveHistory() }
    }
    private var discovery: some View {
        VStack(alignment: .leading, spacing: 30) {
            if !history.isEmpty { recentSearches }
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Gündemdekiler")).font(.system(size: 21, weight: .bold)).tracking(-0.6)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    ForEach(Array(popularQueries.enumerated()), id: \.element) { index, term in
                        Button { query = term } label: {
                            SearchArtistTile(name: term, artwork: suggestions.first(where: { $0.artist == term })?.artwork, index: index)
                        }.buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Bir yerden başla")).font(.system(size: 21, weight: .bold)).tracking(-0.6)
                ForEach(MusicMood.all.prefix(4)) { mood in
                    NavigationLink { QueryView(query: mood.query, title: L(mood.title)) } label: {
                        HStack(spacing: 15) {
                            Image(systemName: mood.symbol).font(.system(size: 19, weight: .medium)).foregroundStyle(Color.musicAccent).frame(width: 28)
                            Text(L(mood.title)).font(.system(size: 18, weight: .semibold)).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        }.padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("Şimdi çal")).font(.system(size: 21, weight: .bold)).tracking(-0.6)
                    ForEach(suggestions.prefix(4)) { TrackRow(track: $0, tracks: suggestions) }
                }
            }
        }
    }
    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Son aramalar")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Temizle") { historyData = "" }.font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(history, id: \.self) { term in
                        Button { query = term } label: {
                            Label(term, systemImage: "clock.arrow.circlepath").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private var popularQueries: [String] {
        var seen = Set<String>()
        let artists = suggestions.map(\.artist).filter { !$0.isEmpty && seen.insert($0).inserted }
        if !artists.isEmpty { return Array(artists.prefix(4)) }
        return ListeningLocale.current.languageCode == "tr" ? ["BLOK3", "Semicenk", "Tarkan", "Türkçe Rap"] : ["Pop", "Hip-Hop", "Indie", "Jazz"]
    }
    private func filterButton(_ title: String, value: String) -> some View {
        Button { filter = value } label: {
            Text(L(title)).font(.system(size: 13, weight: .semibold)).foregroundStyle(filter == value ? Color.musicBackground : Color.primary)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(filter == value ? Color.primary : Color.musicElevated, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(filter == value ? .isSelected : [])
    }
    @ViewBuilder private var results: some View {
        if filter == "songs" {
            if result.tracks.isEmpty { noResults }
            else { LazyVStack(spacing: 2) { ForEach(result.tracks) { TrackRow(track: $0, tracks: result.tracks) } } }
        } else if filter == "albums" {
            if result.albums.isEmpty { noResults }
            else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], alignment: .leading, spacing: 23) {
                    ForEach(result.albums) { album in
                        NavigationLink { AlbumDetailView(collection: album) } label: { AlbumCard(collection: album) }.buttonStyle(.plain)
                    }
                }
            }
        } else {
            if result.artists.isEmpty { noResults }
            else {
                LazyVStack(spacing: 20) {
                    ForEach(result.artists) { artist in
                        NavigationLink { ArtistDetailView(id: artist.id, name: artist.name) } label: {
                            HStack(spacing: 15) {
                                Artwork(url: artist.artwork, radius: 34).frame(width: 68, height: 68)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(artist.name).font(.system(size: 19, weight: .semibold)).foregroundStyle(.primary)
                                    Text(L("Sanatçı")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
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

private struct SearchArtistTile: View {
    var name: String
    var artwork: String?
    var index: Int
    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: artwork, radius: 7).frame(width: 48, height: 48)
            Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
            Spacer(minLength: 0)
        }.padding(.vertical, 5).contentShape(Rectangle())
    }
}

private struct AlbumCard: View {
    var collection: MusicCollection
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Artwork(url: collection.artwork, radius: 4).aspectRatio(1, contentMode: .fit)
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
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Şarkılar")).font(.system(size: 21, weight: .bold)).tracking(-0.6)
                        if !tracks.isEmpty { Text("\(tracks.count) · " + totalDuration).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button { tracks.forEach { downloads.enqueue($0) } } label: {
                        Image(systemName: "arrow.down").font(.system(size: 19, weight: .medium)).frame(width: 42, height: 48).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).accessibilityLabel("Tümünü indir")
                    Button { if let first = tracks.first { player.play(first, in: tracks) } } label: {
                        Image(systemName: "play.fill").font(.system(size: 22, weight: .semibold)).offset(x: 2).foregroundStyle(.white)
                            .frame(width: 56, height: 56).background(Color.musicAccent, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Çal")
                }.padding(.horizontal, 22).disabled(tracks.isEmpty)
                if loading { ProgressView().frame(maxWidth: .infinity).padding(30) }
                if let failure { ErrorState(message: failure) { Task { await load() } }.padding(.horizontal, 22) }
                LazyVStack(spacing: 2) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in TrackRow(track: track, tracks: tracks, number: index + 1) }
                }.padding(.horizontal, 22)
            }.padding(.bottom, 32)
        }.background(Color.musicBackground).navigationTitle(collection.title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar).task { await load() }
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
        VStack(spacing: 16) {
            Artwork(url: artwork, radius: 10)
                .frame(width: typeSize.isAccessibilitySize ? 190 : 224, height: typeSize.isAccessibilitySize ? 190 : 224)
            VStack(spacing: 7) {
                Text(title).font(.title2.weight(.bold)).tracking(-0.5).multilineTextAlignment(.center)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
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
                CollectionCoverHeader(artwork: artwork, eyebrow: "SANATÇI", title: details?.artist.name ?? name, subtitle: nil)
                HStack(spacing: 14) {
                    Button(action: toggleFollow) {
                        Label(isFollowing ? L("Takip ediliyor") : L("Takip et"), systemImage: isFollowing ? "checkmark" : "plus")
                            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 20).frame(height: 40)
                            .foregroundStyle(isFollowing ? Color.musicAccent : Color.primary)
                            .overlay(Capsule().strokeBorder(isFollowing ? Color.musicAccent.opacity(0.6) : Color.primary.opacity(0.25), lineWidth: 1))
                    }.buttonStyle(.plain)
                    Spacer()
                    if let tracks = details?.tracks, let first = tracks.first {
                        Button { player.play(first, in: tracks) } label: {
                            Image(systemName: "play.fill").font(.system(size: 22, weight: .semibold)).offset(x: 2).foregroundStyle(.white)
                                .frame(width: 56, height: 56).background(Color.musicAccent, in: Circle())
                        }.buttonStyle(.plain).accessibilityLabel("Şarkıları çal")
                    }
                }.padding(.horizontal, 22)
                if let details { artistContent(details) }
                else if let failure { ErrorState(message: failure) { Task { await load() } }.padding(.horizontal, 22) }
                else { ProgressView().frame(maxWidth: .infinity).padding(40) }
            }.padding(.bottom, 32)
        }.background(Color.musicBackground).navigationTitle(name).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar).task { await load() }
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
