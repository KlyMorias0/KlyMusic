import SwiftUI

extension Color {
    static let pageBackground = Color.musicBackground
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.045, alpha: 1) : UIColor(white: 0.98, alpha: 1) })
    static let panel = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.075, alpha: 1) : UIColor(white: 0.96, alpha: 1) })
}

extension View {
    func musicPanel(radius: CGFloat = 12) -> some View {
        self.background(Color.panel, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct SettingsButton: View {
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 28, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.coral)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }.accessibilityLabel(L("Ayarlar")).accessibilityIdentifier("settings.open")
            .sheet(isPresented: $presented) { NavigationStack { SettingsView() }.presentationCornerRadius(28).presentationBackground(Color.pageBackground) }
    }
}

struct NowPlayingBars: View {
    var isPlaying: Bool
    var color: Color = .coral
    var size: CGFloat = 13
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func barHeights(at date: Date) -> [CGFloat] {
        guard isPlaying && !reduceMotion else { return [0.46, 0.78, 0.38] }
        let t: Double = date.timeIntervalSinceReferenceDate * 5.2
        let h0 = CGFloat(0.42 + 0.55 * abs(Foundation.sin(t)))
        let h1 = CGFloat(0.35 + 0.62 * abs(Foundation.sin(t * 1.3 + 1.1)))
        let h2 = CGFloat(0.45 + 0.50 * abs(Foundation.sin(t * 0.9 + 2.3)))
        return [h0, h1, h2]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying || reduceMotion)) { timeline in
            let heights = barHeights(at: timeline.date)
            let barWidth: CGFloat = max(2, size * 0.2)
            let barSpacing: CGFloat = max(1.5, size * 0.16)
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: max(3, size * heights[index]))
                }
            }
            .frame(width: size, height: size, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

struct SectionHeading: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L(title)).font(.title2.bold()).tracking(-0.7)
            if let subtitle, !subtitle.isEmpty { Text(L(subtitle)).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2) }
        }
    }
}

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TrackCard: View {
    var track: Track
    var tracks: [Track]
    var size: CGFloat = 166
    @EnvironmentObject private var player: MusicPlayer
    var body: some View {
        Button { player.play(track, in: tracks) } label: {
            VStack(alignment: .leading, spacing: 7) {
                Artwork(url: track.artwork, radius: 10)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)
                    .overlay(alignment: .bottomTrailing) {
                        if player.current?.id == track.id || player.pendingTrack?.id == track.id {
                            ZStack {
                                Circle().fill(.black.opacity(0.75))
                                if player.pendingTrack?.id == track.id { ProgressView().controlSize(.small).tint(.white) }
                                else { NowPlayingBars(isPlaying: player.isPlaying, color: .white, size: 12) }
                            }.frame(width: 28, height: 28).padding(8)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(track.title).font(.system(size: 15)).foregroundStyle(.primary).lineLimit(1)
                        if track.explicit { Image(systemName: "e.square.fill").font(.system(size: 9)).foregroundStyle(.tertiary) }
                    }
                    Text(track.artist).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(width: size, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(CardButtonStyle()).accessibilityLabel("\(track.title), \(track.artist)").accessibilityHint(L("Çal"))
    }
}

struct TrackRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TrackRow: View {
    var track: Track
    var tracks: [Track] = []
    var number: Int? = nil
    var showFavoriteDot: Bool = false
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    private var current: Bool { player.current?.id == track.id }
    var body: some View {
        HStack(spacing: 2) {
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                player.play(track, in: tracks.isEmpty ? [track] : tracks)
            } label: {
                HStack(spacing: 12) {
                    if let number {
                        Text(String(number)).font(.system(size: 13, weight: .regular)).monospacedDigit()
                            .foregroundStyle(current ? Color.coral : Color.secondary).frame(width: 20, alignment: .leading)
                    } else if showFavoriteDot && library.isFavorite(track) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.coral)
                            .frame(width: 10, alignment: .center)
                            .accessibilityHidden(true)
                    }
                    Artwork(url: track.artwork, radius: 7).frame(width: 52, height: 52)
                        .overlay {
                            if player.pendingTrack?.id == track.id {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.black.opacity(0.45))
                                    ProgressView().controlSize(.small).tint(.white)
                                }
                            } else if current {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.black.opacity(0.38))
                                    NowPlayingBars(isPlaying: player.isPlaying, color: .white, size: 13)
                                }
                            }
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(track.title).font(.system(size: 16)).lineLimit(1)
                            if track.explicit { Image(systemName: "e.square.fill").font(.system(size: 10)).foregroundStyle(.tertiary) }
                        }.foregroundStyle(current ? Color.coral : Color.primary)
                        HStack(spacing: 4) {
                            if library.localURL(track.id) != nil { Image(systemName: "arrow.down.circle.fill").font(.system(size: 10)) }
                            Text(track.artist).lineLimit(1)
                        }.font(.system(size: 13.5)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 6).contentShape(Rectangle())
            }.buttonStyle(TrackRowButtonStyle()).accessibilityLabel("\(track.title), \(track.artist)")
                .accessibilityHint(L("Çal")).accessibilityIdentifier("track.row.\(track.id)")
            TrackMenu(track: track)
        }
    }
}

struct TrackMenu: View {
    var track: Track
    var pill = false
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @State private var chooseList = false
    private var isCurrent: Bool { player.current?.id == track.id || player.pendingTrack?.id == track.id }
    private var hasArtist: Bool { !(track.artistID ?? "").isEmpty }
    private var hasAlbum: Bool { !(track.albumID ?? "").isEmpty }
    var body: some View {
        Menu {
            Section {
                Button { library.toggleFavorite(track) } label: {
                    Label(library.isFavorite(track) ? L("Favorilerden çıkar") : L("Favorilere ekle"),
                          systemImage: library.isFavorite(track) ? "star.slash" : "star")
                }.accessibilityIdentifier("track.options.favorite")
                Button { chooseList = true } label: { Label("Listeye ekle", systemImage: "text.badge.plus") }
                    .accessibilityIdentifier("track.options.playlist")
                if library.localURL(track.id) != nil {
                    Button(role: .destructive) { library.removeDownload(track) } label: { Label("İndirmeyi sil", systemImage: "trash") }
                } else {
                    Button { downloads.enqueue(track) } label: { Label("İndir", systemImage: "arrow.down.circle") }
                        .accessibilityIdentifier("track.options.download")
                }
            }
            if !isCurrent {
                Section {
                    Button { player.playNext(track) } label: { Label("Sıradaki çal", systemImage: "text.line.first.and.arrowtriangle.forward") }
                        .accessibilityIdentifier("track.options.next")
                    if !player.queue.contains(where: { $0.id == track.id }) {
                        Button { player.addToQueue(track) } label: { Label("Sıraya ekle", systemImage: "text.line.last.and.arrowtriangle.forward") }
                            .accessibilityIdentifier("track.options.append")
                    }
                }
            }
            if hasArtist || hasAlbum {
                Section {
                    Menu {
                        if let albumID = track.albumID, !albumID.isEmpty {
                            NavigationLink { AlbumDetailView(collection: .init(id: albumID, title: track.album, artist: track.artist, artwork: track.artwork)) } label: {
                                Label("Albüme git", systemImage: "square.stack")
                            }
                        }
                        if let artistID = track.artistID, !artistID.isEmpty {
                            NavigationLink { ArtistDetailView(id: artistID, name: track.artist) } label: { Label("Sanatçıya git", systemImage: "person") }
                        }
                    } label: { Label(L("Sanatçı ve albüm"), systemImage: "arrow.up.right") }
                }
            }
        } label: {
            if pill {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.playerPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.playerPrimary.opacity(0.11), in: Circle())
                    .frame(width: 34, height: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            } else {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: 36, height: 48).contentShape(Rectangle())
            }
        }.tint(.primary)
            .accessibilityLabel(L("Şarkı seçenekleri")).accessibilityValue(track.title)
            .accessibilityIdentifier("track.options.\(track.id)")
            .sheet(isPresented: $chooseList) { PlaylistPicker(track: track) }
    }
}

enum TrackListSort: String, CaseIterable, Identifiable {
    case standard
    case title
    case artist

    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "Varsayılan"
        case .title: "Başlık"
        case .artist: "Sanatçı"
        }
    }

    static func apply(_ sort: TrackListSort, query: String, to tracks: [Track]) -> [Track] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [Track]
        if trimmed.isEmpty {
            filtered = tracks
        } else {
            let needle = NativeCatalog.normalized(trimmed)
            filtered = tracks.filter {
                NativeCatalog.normalized($0.title).contains(needle) ||
                NativeCatalog.normalized($0.artist).contains(needle) ||
                NativeCatalog.normalized($0.album).contains(needle)
            }
        }
        switch sort {
        case .standard:
            return filtered
        case .title:
            return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            return filtered.sorted {
                let cmp = $0.artist.localizedStandardCompare($1.artist)
                return cmp == .orderedSame ? ($0.title.localizedStandardCompare($1.title) == .orderedAscending) : (cmp == .orderedAscending)
            }
        }
    }
}

struct TrackListView: View {
    enum Style {
        case collection
        case songs
    }

    var title: String
    var tracks: [Track]
    var subtitle: String? = nil
    var style: Style = .collection
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var downloads: DownloadManager
    @State private var searchText = ""
    @State private var sort: TrackListSort = .standard

    private var visibleTracks: [Track] {
        TrackListSort.apply(sort, query: searchText, to: tracks)
    }

    private var totalMinutes: Int64 {
        Int64(max(0, Int(visibleTracks.reduce(0.0) { $0 + ($1.duration.isFinite && $1.duration > 0 ? $1.duration : 0.0) } / 60)))
    }

    private var summaryText: String {
        let count = Int64(visibleTracks.count)
        return totalMinutes > 0
            ? String(format: L("%lld şarkı, %lld dakika"), count, totalMinutes)
            : String(format: L("%lld şarkı"), count)
    }

    private var resolvedSubtitle: String? {
        if let subtitle, !subtitle.isEmpty { return subtitle }
        let artists = Set(tracks.map(\.artist).filter { !$0.isEmpty })
        return artists.count == 1 ? artists.first : nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !tracks.isEmpty {
                    if style == .songs {
                        songsHeader
                    } else {
                        collectionHeader
                    }
                    if visibleTracks.isEmpty {
                        EmptyState(symbol: "magnifyingglass", title: "Sonuç bulunamadı", message: "Farklı bir arama dene.")
                    } else {
                        Divider().padding(.leading, 64)
                        ForEach(visibleTracks) { track in
                            TrackRow(track: track, tracks: visibleTracks, showFavoriteDot: true)
                            Divider().padding(.leading, 64)
                        }
                        if style == .collection {
                            Text(summaryText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 14)
                        }
                    }
                } else {
                    EmptyState(symbol: "music.note.list", title: "Henüz şarkı yok", message: "Kaydettiğin şarkılar burada görünecek.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color.pageBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(style == .songs && !tracks.isEmpty ? .inlineLarge : .inline)
        .optionalSearchable(!tracks.isEmpty, text: $searchText, prompt: "Şarkılarda ara")
        .toolbar {
            if !tracks.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker(L("Sırala"), selection: $sort) {
                            ForEach(TrackListSort.allCases) { option in
                                Text(L(option.title)).tag(option)
                            }
                        }
                        Section {
                            Button { tracks.forEach { downloads.enqueue($0) } } label: {
                                Label(L("Tümünü indir"), systemImage: "arrow.down.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(Color.primary)
                }
            }
        }
    }

    private var songsHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            CollectionPlayButtons(tracks: visibleTracks)
            Text(summaryText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
    }

    private var collectionHeader: some View {
        VStack(spacing: 16) {
            PlaylistArtwork(tracks: tracks, radius: 14)
                .frame(width: 236, height: 236)
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 9)
                .padding(.top, 8)
            VStack(spacing: 5) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                if let resolvedSubtitle {
                    Text(resolvedSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.coral)
                }
                Text(summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            CollectionPlayButtons(tracks: visibleTracks)
                .padding(.top, 4)
        }
        .padding(.bottom, 16)
    }
}

extension View {
    @ViewBuilder
    func optionalSearchable(_ enabled: Bool, text: Binding<String>, prompt: String) -> some View {
        if enabled {
            self.searchable(text: text, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(L(prompt)))
        } else {
            self
        }
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 28, weight: .medium)).foregroundStyle(Color.coral).frame(width: 76, height: 76)
                .background(Color.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 25))
            Text(L(title)).font(.title3.weight(.semibold)).tracking(-0.4)
            Text(L(message)).font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 285)
        }.frame(maxWidth: .infinity).padding(.horizontal, 22).padding(.vertical, 42)
    }
}

struct ErrorState: View {
    var message: String
    var retry: () -> Void
    private var cleanMessage: String {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [". Yeniden dene.", " Yeniden dene.", ". Yeniden dene", " Yeniden dene", ". Try again.", " Try again.", ". Try again", " Try again"] {
            if text.hasSuffix(suffix) {
                text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.hasSuffix(".") { text += "." }
                break
            }
        }
        return text
    }
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
            Text(L("Şu an yüklenemiyor")).font(.headline)
            Text(cleanMessage).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: retry) {
                Text(L("Yeniden dene"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.coral, in: Capsule())
            }
            .buttonStyle(CardButtonStyle())
        }.frame(maxWidth: .infinity).padding(26)
    }
}

struct MusicLoadingView: View {
    @State private var isPulsing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                ProgressView().tint(Color.coral)
                Text(L("Müziğin hazırlanıyor")).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }.padding(.vertical, 20)
            ForEach(0..<5) { _ in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.musicElevated).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(.primary.opacity(0.12)).frame(width: 140, height: 10)
                        Capsule().fill(.primary.opacity(0.06)).frame(width: 85, height: 8)
                    }
                    Spacer()
                }
            }
        }
        .opacity(isPulsing ? 0.45 : 1.0)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
        .padding(.horizontal, 22)
        .accessibilityLabel(L("Yükleniyor"))
    }
}


struct CollectionPlayButtons: View {
    var tracks: [Track]
    @EnvironmentObject private var player: MusicPlayer
    var body: some View {
        HStack(spacing: 12) {
            Button {
                if let first = tracks.first { player.play(first, in: tracks) }
            } label: {
                Label(L("Çal"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(CollectionButtonStyle())

            Button {
                let shuffled = tracks.shuffled()
                if let first = shuffled.first { player.play(first, in: shuffled) }
            } label: {
                Label(L("Karıştır"), systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(CollectionButtonStyle())
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Color.coral)
        .disabled(tracks.isEmpty)
        .opacity(tracks.isEmpty ? 0.35 : 1)
    }
}

private struct CollectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}


struct ArtistPortrait: View {
    var url: String?
    var name: String
    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            if let url, !url.isEmpty {
                Artwork(url: url, radius: diameter / 2)
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.8))
            } else {
                ZStack {
                    Circle().fill(Color.musicElevated)
                    Image(systemName: "person.fill")
                        .font(.system(size: diameter * 0.48))
                        .foregroundStyle(.tertiary)
                }
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.8))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(name)
    }
}
