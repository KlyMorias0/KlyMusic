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

struct PlaybackTimeline: View {
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var player: MusicPlayer
    @State private var scrubbing = false
    @State private var scrub = 0.0
    var body: some View {
        VStack(spacing: 1) {
            Slider(value: $scrub, in: 0...max(1, clock.duration), onEditingChanged: { editing in
                scrubbing = editing
                if !editing { player.seek(scrub) }
            }).tint(Color.playerPrimary.opacity(0.8)).accessibilityLabel("Oynatma konumu")
            HStack {
                Text(Track.time(scrubbing ? scrub : clock.position)).accessibilityIdentifier("player.elapsed").accessibilityValue(String(Int(clock.position)))
                Spacer()
                Text("−" + Track.time(max(0, clock.duration - (scrubbing ? scrub : clock.position))))
            }.font(.system(.caption2, design: .monospaced)).monospacedDigit().foregroundStyle(Color.playerSecondary)
        }.onAppear { scrub = min(max(0, clock.position), max(1, clock.duration)) }
            .onChange(of: clock.position) { _, value in if !scrubbing { scrub = min(max(0, value), max(1, clock.duration)) } }
            .onChange(of: clock.duration) { _, value in if !scrubbing { scrub = min(max(0, clock.position), max(1, value)) } }
            .accessibilityElement(children: .contain).accessibilityIdentifier("player.timeline").accessibilityValue(String(Int(clock.position)))
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var titleSize = 25.0
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var layoutHeights: [PlayerLayoutPart: CGFloat] = [:]
    private var track: Track? { player.current ?? player.pendingTrack }
    private var waitingForFirstTrack: Bool { player.current == nil && player.pendingTrack != nil }

    var body: some View {
        Group {
            if showLyrics { originalLyricsLayout }
            else { redesignedLayout }
        }
    }

    private var redesignedLayout: some View {
        GeometryReader { geometry in
            let side = min(360, min(geometry.size.width - 64, max(160, geometry.size.height - 430)))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Button { dismiss() } label: {
                        Capsule().fill(Color.primary.opacity(0.3)).frame(width: 38, height: 5)
                            .frame(maxWidth: .infinity).frame(height: 28).contentShape(Rectangle())
                    }.accessibilityLabel("Kapat").accessibilityIdentifier("player.close")
                    Artwork(url: (player.pendingTrack ?? player.current)?.artwork, radius: 8)
                        .frame(width: side, height: side)
                        .padding(.top, 10).padding(.bottom, 28)
                    appleMetadata.padding(.bottom, 18)
                    ApplePlaybackTimeline().padding(.bottom, 12)
                    appleTransport.padding(.bottom, 26)
                    volume.padding(.bottom, 14)
                    Spacer(minLength: 8)
                    appleTools.padding(.bottom, 14)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 560)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }.scrollBounceBehavior(.basedOnSize)
                .background(Color.canvas.ignoresSafeArea())
        }
        .buttonStyle(.plain)
        .presentationBackground(Color.canvas)
        .sheet(isPresented: $showQueue) { QueueView() }
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
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showLyrics = true }
                player.loadLyrics()
            } label: {
                Image(systemName: "quote.bubble").font(.system(size: 20)).frame(maxWidth: .infinity, minHeight: 46)
            }.accessibilityLabel("Şarkı sözleri").accessibilityIdentifier("lyrics.toggle").accessibilityValue("hidden")
            AirPlayControl().frame(maxWidth: .infinity).frame(height: 46).accessibilityLabel("AirPlay")
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").font(.system(size: 20)).frame(maxWidth: .infinity, minHeight: 46)
            }.accessibilityLabel("Çalma sırası").accessibilityIdentifier("player.queue")
        }.foregroundStyle(.secondary)
    }

    // Keep the complete existing lyrics presentation, including its layout.
    private var originalLyricsLayout: some View {
        GeometryReader { geometry in
            let inset: CGFloat = geometry.size.width < 390 ? 28 : 32
            let compact = geometry.size.height < 720
            let headerHeight = layoutHeights[.header] ?? (compact ? 57 : 67)
            let controlsHeight = layoutHeights[.controls] ?? (compact ? 235 : 270)
            let toolsHeight = layoutHeights[.tools] ?? (compact ? 58 : 66)
            let coverSpacing: CGFloat = compact ? 26 : 42
            let coverSide = min(geometry.size.width - inset * 2,
                                min(400, max(128, geometry.size.height - headerHeight - controlsHeight - toolsHeight - coverSpacing - 2)))
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, inset - 8)
                    .padding(.top, 7)
                    .padding(.bottom, compact ? 6 : 16)
                    .background { measureLayout(.header) }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        cover(side: coverSide)
                            .padding(.top, compact ? 4 : 8)
                            .padding(.bottom, compact ? 22 : 34)
                        VStack(spacing: 0) {
                            metadata.padding(.bottom, compact ? 12 : 22)
                            PlaybackTimeline().padding(.bottom, compact ? 8 : 16)
                            transport.padding(.bottom, compact ? 15 : 24)
                            volume.padding(.bottom, compact ? 8 : 12)
                        }
                        .background { measureLayout(.controls) }
                    }
                    .padding(.horizontal, inset)
                    .frame(maxWidth: 550)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                tools.padding(.horizontal, inset - 6)
                    .padding(.bottom, compact ? 3 : 11)
                    .background { measureLayout(.tools) }
            }
            .foregroundStyle(.primary)
            .background(Color.musicBackground.ignoresSafeArea())
            .buttonStyle(.plain)
            .onPreferenceChange(PlayerLayoutHeightKey.self) { heights in
                if heights != layoutHeights { layoutHeights = heights }
            }
        }
        .presentationBackground(Color.musicBackground)
        .sheet(isPresented: $showQueue) { QueueView() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Kapat").accessibilityIdentifier("player.close")
            VStack(spacing: 4) {
                Text("Şimdi çalıyor")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(player.pendingTrack.map { L("Hazırlanıyor…") + " " + $0.title }
                     ?? (track?.album.isEmpty == false ? track?.album ?? "KlyMusic" : "KlyMusic"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            if let track {
                TrackMenu(track: track).frame(width: 44, height: 44)
                    .accessibilityIdentifier("player.options")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }

    @ViewBuilder private func cover(side: CGFloat) -> some View {
        if showLyrics {
            LyricsView().frame(height: side).transition(.opacity)
        } else {
            Artwork(url: track?.artwork, radius: 10)
                .frame(width: side, height: side)
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
                .scaleEffect(!reduceMotion && !player.isPlaying && !waitingForFirstTrack ? 0.98 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: player.isPlaying)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
        }
    }

    private var metadata: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(track?.title ?? "KlyMusic")
                    .font(.system(size: titleSize, weight: .semibold))
                    .tracking(-0.5).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(track?.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let track {
                Button { library.toggleFavorite(track) } label: {
                    Image(systemName: library.isFavorite(track) ? "heart.fill" : "heart")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(library.isFavorite(track) ? Color.musicAccent : Color.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(library.isFavorite(track) ? L("Favorilerden çıkar") : L("Favorilere ekle"))
                .accessibilityIdentifier("player.favorite")
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Button { player.toggleShuffle() } label: {
                transportSymbol("shuffle", active: player.shuffle)
            }
            .accessibilityLabel("Karıştır")
            .accessibilityValue(player.shuffle ? L("Karıştırma açık") : L("Kapalı"))
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 25, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 64)
            }.accessibilityLabel("Önceki şarkı")
            Button { player.toggle() } label: {
                Group {
                    if player.isBuffering || waitingForFirstTrack {
                        ProgressView().tint(Color.musicBackground).scaleEffect(1.1)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .offset(x: player.isPlaying ? 0 : 2)
                    }
                }.foregroundStyle(Color.musicBackground)
                    .frame(width: 64, height: 64)
                    .background(Color.primary, in: Circle())
                    .frame(width: 82, height: 72)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(player.isPlaying ? L("Duraklat") : L("Çal"))
            .accessibilityIdentifier("player.playPause")
            .accessibilityValue(player.isPlaying ? "playing" : "paused")
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 25, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 64)
            }.accessibilityLabel("Sonraki şarkı")
            Button { player.cycleRepeat() } label: {
                transportSymbol(player.repeatMode == .one ? "repeat.1" : "repeat", active: player.repeatMode != .off)
            }
            .accessibilityLabel("Tekrarlama")
            .accessibilityValue(player.repeatMode == .off ? L("Kapalı") : player.repeatMode == .one ? L("Tek şarkı") : L("Tümü"))
        }
    }

    private func transportSymbol(_ name: String, active: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: name).font(.system(size: 16, weight: .medium))
            Circle().fill(active ? Color.musicAccent : .clear).frame(width: 3, height: 3)
        }
        .foregroundStyle(active ? Color.musicAccent : Color.secondary)
        .frame(maxWidth: .infinity, minHeight: 64)
        .offset(y: 4)
    }

    private var volume: some View {
        HStack(spacing: 13) {
            Image(systemName: "speaker.fill").font(.system(size: 10))
            VolumeControl().frame(height: 26)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 12))
        }.foregroundStyle(.secondary)
    }

    private var tools: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showLyrics.toggle() }
                if showLyrics { player.loadLyrics() }
            } label: {
                toolSymbol(showLyrics ? "quote.bubble.fill" : "quote.bubble", active: showLyrics)
            }
            .accessibilityLabel("Şarkı sözleri")
            .accessibilityIdentifier("lyrics.toggle").accessibilityValue(showLyrics ? "visible" : "hidden")
            AirPlayControl().frame(maxWidth: .infinity).frame(height: 48).accessibilityLabel("AirPlay")
            if let track {
                Button { downloads.enqueue(track) } label: {
                    toolSymbol(library.localURL(track.id) != nil ? "checkmark.circle.fill" : downloads.jobs[track.id] != nil ? "arrow.down.circle.dotted" : "arrow.down.circle", active: library.localURL(track.id) != nil)
                }
                .accessibilityLabel("İndir").accessibilityIdentifier("player.download")
                .disabled(library.localURL(track.id) != nil)
            }
            Menu {
                Button("Kapalı") { player.setSleep(minutes: nil) }
                Button("Şarkı bitince") { player.setSleepAtEnd() }
                ForEach([15, 30, 60], id: \.self) { minutes in
                    Button("\(minutes) dakika") { player.setSleep(minutes: minutes) }
                }
            } label: {
                toolSymbol(player.sleepUntil == nil && !player.sleepAtEnd ? "moon" : "moon.fill", active: player.sleepUntil != nil || player.sleepAtEnd)
            }.accessibilityLabel("Uyku zamanlayıcısı")
            Button { showQueue = true } label: { toolSymbol("text.line.first.and.arrowtriangle.forward") }
                .accessibilityLabel("Çalma sırası").accessibilityIdentifier("player.queue")
        }
        .padding(.top, 7)
        .background(Color.musicBackground)
        .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5) }
    }

    private func toolSymbol(_ name: String, active: Bool = false) -> some View {
        Image(systemName: name).font(.system(size: 18, weight: .regular))
            .foregroundStyle(active ? Color.musicAccent : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 48)
    }

    private func measureLayout(_ part: PlayerLayoutPart) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: PlayerLayoutHeightKey.self,
                                   value: [part: geometry.size.height.rounded(.up)])
        }
    }
}

private enum PlayerLayoutPart: Hashable {
    case header, controls, tools
}

private struct PlayerLayoutHeightKey: PreferenceKey {
    static let defaultValue: [PlayerLayoutPart: CGFloat] = [:]
    static func reduce(value: inout [PlayerLayoutPart: CGFloat], nextValue: () -> [PlayerLayoutPart: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
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
                .accessibilityValue(Track.time(value))
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
        }.accessibilityIdentifier("player.timeline")
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
    var body: some View {
        NavigationStack {
            List {
                if let current = player.current {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Şimdi çalıyor").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 15) {
                            Artwork(url: current.artwork, radius: 8).frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(current.title).font(.system(.headline).weight(.semibold)).lineLimit(2)
                                Text(current.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: player.isPlaying ? "waveform" : "pause.fill").font(.system(size: 17, weight: .medium)).foregroundStyle(Color.coral)
                        }
                    }
                    .padding(.vertical, 16)
                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 18, trailing: 24))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                Section {
                    ForEach(player.queue) { track in
                        TrackRow(track: track, tracks: player.queue)
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 16))
                    }.onMove(perform: player.moveQueue).onDelete(perform: player.removeFromQueue)
                } header: {
                    HStack {
                        Text(L("Sıradaki şarkılar")).font(.system(size: 18, weight: .semibold)).foregroundStyle(.primary)
                        Spacer()
                        Button { player.toggleShuffle() } label: {
                            Image(systemName: "shuffle").foregroundStyle(player.shuffle ? Color.coral : Color.secondary).frame(width: 40, height: 44)
                        }.accessibilityLabel("Karıştır")
                        Button { player.cycleRepeat() } label: {
                            Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                                .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.coral).frame(width: 40, height: 44)
                        }.accessibilityLabel("Tekrarlama")
                    }.textCase(nil).padding(.bottom, 7)
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .background(Color.canvas)
            .navigationTitle("Çalma sırası").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() }.foregroundStyle(.primary) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Kapalı") { player.setSleep(minutes: nil) }
                        Button("Şarkı bitince") { player.setSleepAtEnd() }
                        ForEach([15, 30, 60], id: \.self) { minutes in
                            Button("\(minutes) dakika") { player.setSleep(minutes: minutes) }
                        }
                    } label: { Image(systemName: "moon") }.accessibilityLabel("Uyku zamanlayıcısı")
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton().tint(Color.coral) }
            }
        }
        .presentationBackground(Color.canvas)
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
