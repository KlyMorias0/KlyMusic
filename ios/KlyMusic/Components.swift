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
            Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.primary).frame(width: 32, height: 36).contentShape(Rectangle())
        }.accessibilityLabel("Ayarlar").accessibilityIdentifier("settings.open")
            .sheet(isPresented: $presented) { NavigationStack { SettingsView() }.presentationCornerRadius(28) }
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

struct TrackCard: View {
    var track: Track
    var tracks: [Track]
    var size: CGFloat = 166
    @EnvironmentObject private var player: MusicPlayer
    var body: some View {
        Button { player.play(track, in: tracks) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Artwork(url: track.artwork, radius: 7).frame(width: size, height: size)
                    .overlay(alignment: .bottomTrailing) {
                        if player.current?.id == track.id || player.pendingTrack?.id == track.id {
                            ZStack {
                                Circle().fill(.black.opacity(0.85))
                                if player.pendingTrack?.id == track.id { ProgressView().tint(.white) }
                                else { Image(systemName: player.isPlaying ? "waveform" : "play.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white) }
                            }.frame(width: 30, height: 30).padding(8)
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(track.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(width: size, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(track.title), \(track.artist)").accessibilityHint(L("Çal"))
    }
}

struct TrackRow: View {
    var track: Track
    var tracks: [Track] = []
    var number: Int? = nil
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    private var current: Bool { player.current?.id == track.id }
    var body: some View {
        HStack(spacing: 2) {
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                player.play(track, in: tracks.isEmpty ? [track] : tracks)
            } label: {
                HStack(spacing: 13) {
                    if let number {
                        Text(String(number)).font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(current ? Color.coral : Color.secondary).frame(width: 18, alignment: .leading)
                    }
                    Artwork(url: track.artwork, radius: 6).frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(track.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                            if track.explicit { Image(systemName: "e.square.fill").font(.system(size: 10)).foregroundStyle(.tertiary) }
                        }.foregroundStyle(current ? Color.coral : Color.primary)
                        HStack(spacing: 4) {
                            if library.localURL(track.id) != nil { Image(systemName: "arrow.down.circle.fill").font(.system(size: 10)) }
                            Text(track.artist).lineLimit(1)
                        }.font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if player.pendingTrack?.id == track.id { ProgressView().controlSize(.small).tint(Color.coral) }
                    else if current && player.isPlaying { Image(systemName: "waveform").font(.system(size: 14)).foregroundStyle(Color.coral) }
                }.padding(.vertical, 7).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(track.title), \(track.artist)")
                .accessibilityHint(L("Çal")).accessibilityIdentifier("track.row.\(track.id)")
            TrackMenu(track: track)
        }
    }
}

struct TrackMenu: View {
    var track: Track
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
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 36, height: 48).contentShape(Rectangle())
        }.tint(.primary)
            .accessibilityLabel(L("Şarkı seçenekleri")).accessibilityValue(track.title)
            .accessibilityIdentifier("track.options.\(track.id)")
            .sheet(isPresented: $chooseList) { PlaylistPicker(track: track) }
    }
}

struct TrackListView: View {
    var title: String
    var tracks: [Track]
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var downloads: DownloadManager
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let first = tracks.first {
                    collectionHeader(first)
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in TrackRow(track: track, tracks: tracks, number: index + 1) }
                } else { EmptyState(symbol: "music.note.list", title: "Henüz şarkı yok", message: "Kaydettiğin şarkılar burada görünecek.") }
            }.padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 28).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(Color.pageBackground).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
    private func collectionHeader(_ first: Track) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom, spacing: 18) {
                Artwork(url: first.artwork, radius: 6).frame(width: 124, height: 124)
                VStack(alignment: .leading, spacing: 9) {
                    Text(L("Koleksiyon")).font(.caption).foregroundStyle(.secondary)
                    Text(title).font(.title2.bold()).tracking(-0.7).lineLimit(3)
                    Text("\(tracks.count) " + L("Şarkılar").lowercased()).font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                Button { player.play(first, in: tracks) } label: {
                    Label("Çal", systemImage: "play.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 46).background(Color.coral, in: Capsule())
                }
                Button { tracks.forEach { downloads.enqueue($0) } } label: {
                    Image(systemName: "arrow.down").font(.system(size: 17, weight: .semibold)).frame(width: 46, height: 46)
                        .foregroundStyle(.primary).overlay { Circle().strokeBorder(.primary.opacity(0.22), lineWidth: 1) }
                }.accessibilityLabel("Tümünü indir")
            }.buttonStyle(.plain)
            Rectangle().fill(.primary.opacity(0.1)).frame(height: 0.5)
        }.padding(.bottom, 18)
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
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
            Text("Şu an yüklenemiyor").font(.headline)
            Text(message).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Yeniden dene", action: retry).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.coral)
                .padding(.horizontal, 22).padding(.vertical, 12).overlay { Capsule().strokeBorder(Color.coral.opacity(0.7), lineWidth: 1) }
        }.frame(maxWidth: .infinity).padding(26)
    }
}

struct MusicLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                ProgressView().tint(Color.coral)
                Text(L("Müziğin hazırlanıyor")).font(.system(size: 13)).foregroundStyle(.secondary)
            }.padding(.vertical, 35)
            ForEach(0..<3) { _ in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.musicElevated).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 9) {
                        Capsule().fill(.primary.opacity(0.1)).frame(width: 140, height: 6)
                        Capsule().fill(.primary.opacity(0.06)).frame(width: 85, height: 5)
                    }
                    Spacer()
                }
            }
        }.padding(.horizontal, 22).accessibilityLabel("Yükleniyor")
    }
}
