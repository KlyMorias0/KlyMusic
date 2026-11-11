import SwiftUI
import AVKit
import MediaPlayer

struct MiniPlayer: View {
    var inSystemAccessory = false
    var isCompact = false
    @EnvironmentObject private var player: MusicPlayer
    var body: some View {
        HStack(spacing: 9) {
            Button { player.isPresented = true } label: {
                HStack(spacing: 11) {
                    Artwork(url: (player.current ?? player.pendingTrack)?.artwork, radius: 6)
                        .frame(width: isCompact ? 28 : 40, height: isCompact ? 28 : 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text((player.current ?? player.pendingTrack)?.title ?? "KlyMusic").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        if !isCompact {
                            Text(player.pendingTrack.map { L("Hazırlanıyor…") + " " + $0.title } ?? player.current?.artist ?? "")
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle()).foregroundStyle(.primary)
            }.buttonStyle(.plain).accessibilityLabel("Oynatıcıyı aç").accessibilityIdentifier("player.open")
            Button { player.toggle() } label: {
                if player.isBuffering || (player.current == nil && player.pendingTrack != nil) { ProgressView().frame(width: 38, height: 44) }
                else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22, weight: .semibold)).frame(width: 38, height: 44) }
            }.buttonStyle(.plain).accessibilityLabel(player.isPlaying ? L("Duraklat") : L("Çal"))
            if !isCompact {
                Button { player.next() } label: { Image(systemName: "forward.fill").font(.system(size: 21)).frame(width: 34, height: 44) }.buttonStyle(.plain).accessibilityLabel("Sonraki şarkı")
            }
        }.padding(.horizontal, isCompact ? 8 : 12).padding(.vertical, isCompact ? 0 : 6)
            .background {
                if !inSystemAccessory { RoundedRectangle(cornerRadius: 21).fill(.regularMaterial) }
            }
    }
}

struct MiniProgress: View {
    @EnvironmentObject private var clock: PlaybackClock
    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Color.coral.opacity(0.7)).frame(width: max(0, min(1, clock.position / max(clock.duration, 1))) * geo.size.width, height: 2)
        }
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showLyrics = false
    @State private var showQueue = false
    private var displayed: Track? { player.pendingTrack ?? player.current }
    private var waitingForFirstTrack: Bool { player.current == nil && player.pendingTrack != nil }

    var body: some View {
        GeometryReader { geometry in
            let side = min(360, min(geometry.size.width - 56, max(190, geometry.size.height - 410)))
            ZStack {
                AlbumBackdrop(artwork: displayed?.artwork)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Button { dismiss() } label: {
                            Capsule().fill(Color.primary.opacity(0.3)).frame(width: 38, height: 5)
                                .frame(maxWidth: .infinity).frame(height: 28).contentShape(Rectangle())
                        }.accessibilityLabel("Kapat").accessibilityIdentifier("player.close")
                        ZStack {
                            if showLyrics {
                                LyricsView().padding(.horizontal, 4).transition(.opacity)
                            } else {
                                Artwork(url: displayed?.artwork, radius: 15)
                                    .frame(width: side, height: side)
                                    .shadow(color: .black.opacity(0.2), radius: 22, y: 12)
                                    .accessibilityIdentifier("player.cover").transition(.opacity)
                            }
                        }.frame(height: side).frame(maxWidth: .infinity)
                            .padding(.top, 10).padding(.bottom, 25)
                        appleMetadata.padding(.bottom, 15)
                        ApplePlaybackTimeline().padding(.bottom, 10)
                        appleTransport.padding(.bottom, 20)
                        volume.padding(.bottom, 12)
                        Spacer(minLength: 8)
                        appleTools.padding(.bottom, 14)
                    }
                    .padding(.horizontal, 28).frame(maxWidth: 560)
                    .frame(minHeight: geometry.size.height).frame(maxWidth: .infinity)
                }.scrollBounceBehavior(.basedOnSize)
            }
        }
        .buttonStyle(.plain).presentationBackground(Color.canvas)
        .sheet(isPresented: $showQueue) { QueueView() }
    }

    private var volume: some View {
        HStack(spacing: 13) {
            Image(systemName: "speaker.fill").font(.system(size: 10))
            VolumeControl().frame(height: 26)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 12))
        }.foregroundStyle(.secondary)
    }

    private var appleMetadata: some View {
        let displayed = player.pendingTrack ?? player.current
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayed?.title ?? "KlyMusic").font(.system(size: 22, weight: .semibold)).lineLimit(2)
                Text(displayed?.artist ?? "").font(.system(size: 19)).foregroundStyle(.secondary).lineLimit(1)
                if player.pendingTrack != nil { Text(L("Hazırlanıyor…")).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let displayed {
                Button { library.toggleFavorite(displayed) } label: {
                    Image(systemName: library.isFavorite(displayed) ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(library.isFavorite(displayed) ? Color.coral : Color.primary)
                        .frame(width: 32, height: 32).background(.primary.opacity(0.08), in: Circle())
                        .frame(width: 44, height: 44)
                }.accessibilityIdentifier("player.favorite")
                    .accessibilityLabel(library.isFavorite(displayed) ? L("Favorilerden çıkar") : L("Favorilere ekle"))
                TrackMenu(track: displayed).frame(width: 30)
            }
        }
    }

    private var appleTransport: some View {
        HStack {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 30)).frame(maxWidth: .infinity, minHeight: 62)
            }.accessibilityLabel("Önceki şarkı")
            Button { player.toggle() } label: {
                Group {
                    if player.isBuffering || waitingForFirstTrack { ProgressView().tint(.primary) }
                    else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 42, weight: .semibold)) }
                }.frame(maxWidth: .infinity, minHeight: 62)
            }.accessibilityLabel(player.isPlaying ? L("Duraklat") : L("Çal"))
                .accessibilityIdentifier("player.playPause").accessibilityValue(player.isPlaying ? "playing" : "paused")
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 30)).frame(maxWidth: .infinity, minHeight: 62)
            }.accessibilityLabel("Sonraki şarkı")
        }.foregroundStyle(.primary)
    }

    private var appleTools: some View {
        HStack {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showLyrics.toggle() }
                if showLyrics { player.loadLyrics() }
            } label: {
                Image(systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble").font(.system(size: 20)).frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(showLyrics ? Color.primary : Color.secondary)
            }.accessibilityLabel("Şarkı sözleri").accessibilityIdentifier("lyrics.toggle").accessibilityValue(showLyrics ? "visible" : "hidden")
            AirPlayControl().frame(maxWidth: .infinity).frame(height: 46).accessibilityLabel("AirPlay")
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").font(.system(size: 20)).frame(maxWidth: .infinity, minHeight: 46)
            }.accessibilityLabel("Çalma sırası").accessibilityIdentifier("player.queue")
        }.foregroundStyle(.secondary)
    }

}

private struct ApplePlaybackTimeline: View {
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var player: MusicPlayer
    @State private var scrubbing = false
    @State private var scrub = 0.0
    private var value: Double { scrubbing ? scrub : clock.position }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.16))
                    Capsule().fill(.primary.opacity(0.65))
                        .frame(width: max(0, min(1, value / max(1, clock.duration))) * geometry.size.width)
                }.frame(height: scrubbing ? 6 : 4).frame(height: 28)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                        scrubbing = true
                        scrub = min(max(0, event.location.x / max(1, geometry.size.width)), 1) * max(0, clock.duration)
                    }.onEnded { _ in player.seek(scrub); scrubbing = false })
            }.frame(height: 28)
                .accessibilityElement().accessibilityLabel("Oynatma konumu")
                .accessibilityValue(Track.time(value)).accessibilityIdentifier("player.scrubber")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: player.seek(clock.position + 5)
                    case .decrement: player.seek(clock.position - 5)
                    @unknown default: break
                    }
                }
            HStack {
                Text(Track.time(value)).accessibilityIdentifier("player.elapsed").accessibilityValue(String(Int(clock.position)))
                Spacer()
                Text("−" + Track.time(max(0, clock.duration - value)))
            }.font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("player.timeline")
    }
}

struct LyricsView: View {
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var clock: PlaybackClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var following = true
    private var lines: [LyricLine] { player.lyrics?.lines ?? [] }
    private var active: Int { lines.last(where: { $0.time <= clock.position })?.id ?? -1 }

    var body: some View {
        Group {
            if player.lyricsLoading {
                ProgressView(L("Şarkı sözleri yükleniyor…")).tint(Color.playerSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = player.lyricsError {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(Color.playerSecondary)
                    Text(message).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Color.playerSecondary)
                    Button(L("Yeniden dene")) { player.loadLyrics(force: true) }
                        .buttonStyle(.bordered).tint(.coral).accessibilityIdentifier("lyrics.retry")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !lines.isEmpty {
                ScrollViewReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(lines) { line in
                                    Button {
                                        following = true
                                        player.seek(line.time)
                                        scroll(to: line.id, proxy: proxy)
                                    } label: {
                                        AnimatedLyricLine(text: line.text, isActive: line.id == active,
                                                          isPast: line.id < active, progress: progress(for: line))
                                    }.buttonStyle(.plain).id(line.id)
                                        .accessibilityIdentifier("lyrics.line.\(line.id)")
                                        .accessibilityLabel(line.text)
                                        .accessibilityHint(L("Bu satırdan çal"))
                                        .accessibilityAddTraits(line.id == active ? .isSelected : [])
                                }
                            }.padding(.vertical, 70).padding(.horizontal, 3)
                        }
                        .accessibilityIdentifier("lyrics.scroll")
                        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in following = false })
                        .onAppear { proxy.scrollTo(max(0, active), anchor: .center) }
                        .onChange(of: active) { _, id in
                            guard following, !voiceOver, id >= 0 else { return }
                            scroll(to: id, proxy: proxy)
                        }
                        if !following {
                            Button {
                                following = true
                                scroll(to: max(0, active), proxy: proxy)
                            } label: {
                                Label(L("Sözleri takip et"), systemImage: "location.fill")
                                    .font(.caption.weight(.semibold)).padding(.horizontal, 4)
                            }
                            .buttonStyle(.borderedProminent).tint(.coral).clipShape(Capsule())
                            .accessibilityIdentifier("lyrics.follow").padding(.bottom, 6)
                        }
                    }
                }
            } else if let plain = player.lyrics?.plain, !plain.isEmpty {
                ScrollView {
                    Text(plain).font(.title2.weight(.semibold)).foregroundStyle(Color.playerPrimary)
                        .lineSpacing(12).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
                }.transition(.opacity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble").font(.system(size: 32)).foregroundStyle(Color.playerSecondary)
                    Text(L(player.lyrics?.instrumental == true ? "Sadece müzik" : "Sözler bulunamadı")).font(.headline)
                    Text(L("Bu kayıt için şarkı sözü mevcut değil.")).font(.subheadline)
                        .foregroundStyle(Color.playerSecondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("lyrics.content")
        .task(id: player.current?.id) { following = true; player.loadLyrics() }
    }

    // LRCLIB supplies line timestamps, not word timings. Sweep only within the real line interval.
    private func progress(for line: LyricLine) -> Double {
        guard line.id == active else { return line.id < active ? 1 : 0 }
        let end = lines.first(where: { $0.time > line.time })?.time ?? clock.duration
        guard end > line.time else { return 1 }
        return min(1, max(0, (clock.position - line.time) / (end - line.time)))
    }

    private func scroll(to id: Int, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

private struct AnimatedLyricLine: View {
    var text: String
    var isActive: Bool
    var isPast: Bool
    var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var textSize = 29.0

    private var label: some View {
        Text(text).font(.system(size: textSize, weight: .semibold))
            .lineSpacing(4).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        label
            .foregroundStyle(isActive ? Color.playerPrimary.opacity(0.75) : Color.playerSecondary.opacity(isPast ? 0.85 : 1))
            .overlay(alignment: .leading) {
                if isActive {
                    label.foregroundStyle(Color.playerPrimary)
                        .mask {
                            GeometryReader { geo in
                                Rectangle().frame(width: geo.size.width * (reduceMotion ? 1 : progress))
                            }
                        }
                        .animation(reduceMotion ? nil : .linear(duration: 0.25), value: progress)
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(isActive || reduceMotion ? 1 : 0.97, anchor: .leading)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isActive)
            .contentShape(Rectangle()).accessibilityHidden(true)
    }
}

struct QueueView: View {
    @EnvironmentObject private var player: MusicPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        let upcoming = player.upcomingTracks
        NavigationStack {
            List {
                if let current = player.pendingTrack ?? player.current {
                    Section {
                        HStack(spacing: 13) {
                            queueArtwork(current)
                            queueMetadata(current)
                            Spacer(minLength: 8)
                            if player.pendingTrack != nil { ProgressView().controlSize(.small) }
                            else {
                                Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                                    .font(.system(size: 16)).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 7).accessibilityIdentifier("queue.current")
                    } header: {
                        Text("Şimdi çalıyor").font(.subheadline.weight(.medium)).textCase(nil)
                    }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
                }
                Section {
                    if upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Sıra boş")).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            Text(L("Şarkı menüsünden sıraya ekleyebilirsin.")).font(.footnote).foregroundStyle(.secondary)
                        }.padding(.vertical, 14).accessibilityIdentifier("queue.empty")
                    } else {
                        ForEach(upcoming) { track in
                            Button { player.playUpcoming(id: track.id) } label: {
                                HStack(spacing: 13) {
                                    queueArtwork(track)
                                    queueMetadata(track)
                                }.padding(.vertical, 7).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel("\(track.title), \(track.artist)")
                                .accessibilityHint(L("Çal")).accessibilityIdentifier("queue.track.\(track.id)")
                                .contextMenu {
                                    Button { player.playNext(track) } label: { Label("Sıradaki çal", systemImage: "text.line.first.and.arrowtriangle.forward") }
                                    Button(role: .destructive) { player.removeUpcoming(id: track.id) } label: { Label("Sıradan kaldır", systemImage: "minus.circle") }
                                }
                        }.onMove { offsets, destination in
                            player.moveUpcoming(from: offsets, to: destination, snapshot: upcoming)
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text(L("Sıradaki")).font(.headline).foregroundStyle(.primary)
                        if !upcoming.isEmpty { Text("\(upcoming.count)").font(.subheadline).foregroundStyle(.secondary) }
                        Spacer(minLength: 0)
                        Button { player.toggleShuffle() } label: {
                            Image(systemName: "shuffle").frame(width: 40, height: 40).contentShape(Rectangle())
                                .foregroundStyle(player.shuffle ? Color.coral : Color.secondary)
                        }.accessibilityLabel(L("Karıştır")).accessibilityValue(player.shuffle ? L("Açık") : L("Kapalı"))
                        Button { player.cycleRepeat() } label: {
                            Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").frame(width: 40, height: 40).contentShape(Rectangle())
                                .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.coral)
                        }.accessibilityLabel(L("Tekrarlama")).accessibilityValue(player.repeatMode == .off ? L("Kapalı") : (player.repeatMode == .one ? L("Bir Şarkı") : L("Tümü")))
                    }.textCase(nil)
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 18))
            }
            .listStyle(.plain).listSectionSpacing(20).scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .background(Color.pageBackground)
            .navigationTitle(L("Çalma sırası")).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.pageBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L("Kapat"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Menu {
                            Button(L("Kapalı")) { player.setSleep(minutes: nil) }
                            Button(L("Şarkı bitince")) { player.setSleepAtEnd() }
                            ForEach([15, 30, 60], id: \.self) { minutes in
                                Button(String(format: L("%lld dakika"), Int64(minutes))) { player.setSleep(minutes: minutes) }
                            }
                        } label: { Label(L("Uyku zamanlayıcısı"), systemImage: "moon") }
                        if !upcoming.isEmpty {
                            Section {
                                Button(role: .destructive) { confirmClear = true } label: { Label(L("Sırayı temizle"), systemImage: "trash") }
                                    .accessibilityIdentifier("queue.clear")
                            }
                        }
                    } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel(L("Sıra seçenekleri")).accessibilityIdentifier("queue.options")
                }
            }.tint(.primary)
            .confirmationDialog(L("Sıradaki şarkılar kaldırılsın mı?"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(L("Sırayı temizle"), role: .destructive) { player.clearUpcoming() }
                Button(L("Vazgeç"), role: .cancel) { }
            } message: { Text(L("Çalan şarkı devam eder.")) }
        }
        .presentationBackground(Color.pageBackground).presentationDragIndicator(.visible)
    }

    private func queueArtwork(_ track: Track) -> some View {
        Artwork(url: track.artwork, radius: 6).frame(width: 48, height: 48)
    }
    private func queueMetadata(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.title).font(.system(size: 16, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
            Text(track.artist).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AirPlayControl: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(); view.prioritizesVideoDevices = false
        view.activeTintColor = UIColor(Color.coral); view.tintColor = UIColor(Color.playerSecondary)
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.activeTintColor = UIColor(Color.coral); view.tintColor = UIColor(Color.playerSecondary)
    }
}

struct VolumeControl: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(); view.tintColor = UIColor(Color.playerSecondary)
        view.showsRouteButton = false
        return view
    }
    func updateUIView(_ view: MPVolumeView, context: Context) { view.tintColor = UIColor(Color.playerSecondary) }
}
