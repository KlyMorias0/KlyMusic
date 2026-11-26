import SwiftUI
import AVFoundation
import AVKit
import MediaPlayer

struct DolbyDoubleDMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        guard w > 0, h > 0 else { return path }

        let blockWidth = w * 0.455
        let halfBlock = CGRect(x: rect.minX, y: rect.minY, width: blockWidth, height: h)
        let rightBlock = CGRect(x: rect.maxX - blockWidth, y: rect.minY, width: blockWidth, height: h)
        path.addRect(halfBlock)
        path.addRect(rightBlock)

        let r = h * 0.34
        let topY = rect.midY - r
        let botY = rect.midY + r
        let k: CGFloat = 0.55228475
        let spineX = rect.minX + w * 0.095
        let curveStartX = rect.minX + w * 0.21
        let curveEndX = rect.minX + w * 0.40
        let dx = curveEndX - curveStartX

        var leftCutout = Path()
        leftCutout.move(to: CGPoint(x: spineX, y: topY))
        leftCutout.addLine(to: CGPoint(x: curveStartX, y: topY))
        leftCutout.addCurve(
            to: CGPoint(x: curveEndX, y: rect.midY),
            control1: CGPoint(x: curveStartX + dx * k, y: topY),
            control2: CGPoint(x: curveEndX, y: rect.midY - r * k)
        )
        leftCutout.addCurve(
            to: CGPoint(x: curveStartX, y: botY),
            control1: CGPoint(x: curveEndX, y: rect.midY + r * k),
            control2: CGPoint(x: curveStartX + dx * k, y: botY)
        )
        leftCutout.addLine(to: CGPoint(x: spineX, y: botY))
        leftCutout.closeSubpath()

        let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0)
        path.addPath(leftCutout)
        path.addPath(leftCutout.applying(mirror))
        return path
    }
}

struct DolbyAtmosBadge: View {
    var color: Color = .playerSecondary
    var body: some View {
        HStack(spacing: 4.5) {
            DolbyDoubleDMark()
                .fill(color, style: FillStyle(eoFill: true))
                .frame(width: 14, height: 9.5)
                .accessibilityHidden(true)
            Text("Dolby Atmos")
                .font(.system(size: 11, weight: .semibold))
                .tracking(-0.15)
                .foregroundStyle(color)
        }
    }
}

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
            .overlay(alignment: .bottom) {
                if !isCompact && !player.isLiveStream {
                    MiniProgress()
                        .frame(height: 2)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 1)
                }
            }
            .background {
                if !inSystemAccessory { RoundedRectangle(cornerRadius: 21).fill(.regularMaterial) }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 32)
                    .onEnded { value in
                        guard !isCompact, !player.isLiveStream,
                              abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width < -48 {
                            Haptics.light()
                            player.next()
                        } else if value.translation.width > 48 {
                            Haptics.light()
                            player.previous()
                        }
                    }
            )
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
    @AppStorage("animatedArtwork") private var animatedArtwork = true
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var coverDragOffset: CGFloat = 0
    private var displayed: Track? { player.pendingTrack ?? player.current }
    private var waitingForFirstTrack: Bool { player.current == nil && player.pendingTrack != nil }

    var body: some View {
        GeometryReader { geometry in
            let side = min(388, min(geometry.size.width - 56, max(190, geometry.size.height - 410)))
            ZStack {
                AlbumBackdrop(artwork: displayed?.artwork, isPlaying: player.isPlaying, intense: showLyrics)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Button { dismiss() } label: {
                            Capsule().fill(Color.primary.opacity(0.3)).frame(width: 38, height: 5)
                                .frame(maxWidth: .infinity).frame(height: 28).contentShape(Rectangle())
                        }.accessibilityLabel("Kapat").accessibilityIdentifier("player.close")
                        if showQueue {
                            InlineQueuePanel(showQueue: $showQueue)
                                .frame(maxWidth: .infinity)
                                .frame(height: side + 208)
                                .padding(.top, 8)
                                .padding(.bottom, 12)
                                .transition(.opacity)
                        } else {
                            ZStack {
                                if showLyrics {
                                    LyricsView().padding(.horizontal, 4).transition(.opacity)
                                } else {
                                    Artwork(url: displayed?.artwork, radius: 15)
                                        .frame(width: side, height: side)
                                        .shadow(color: .black.opacity(player.isPlaying ? 0.34 : 0.16), radius: player.isPlaying ? 26 : 12, y: player.isPlaying ? 14 : 6)
                                        .scaleEffect((player.isPlaying || reduceMotion || !animatedArtwork) ? 1.0 : 0.86)
                                        .offset(x: coverDragOffset)
                                        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.76), value: player.isPlaying)
                                        .gesture(
                                            DragGesture(minimumDistance: 28)
                                                .onChanged { value in
                                                    guard !player.isLiveStream, abs(value.translation.width) > abs(value.translation.height) else { return }
                                                    coverDragOffset = max(-60, min(60, value.translation.width * 0.45))
                                                }
                                                .onEnded { value in
                                                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78)) { coverDragOffset = 0 }
                                                    guard !player.isLiveStream, abs(value.translation.width) > abs(value.translation.height) else { return }
                                                    if value.translation.width < -55 { Haptics.light(); player.next() }
                                                    else if value.translation.width > 55 { Haptics.light(); player.previous() }
                                                }
                                        )
                                        .accessibilityIdentifier("player.cover").transition(.opacity)
                                }
                            }.frame(height: side).frame(maxWidth: .infinity)
                                .padding(.top, 10).padding(.bottom, 25)
                            appleMetadata.padding(.bottom, 15)
                            ApplePlaybackTimeline().padding(.bottom, 12)
                            appleTransport.padding(.bottom, 18)
                            AppleVolumeBar().padding(.bottom, 12)
                            Spacer(minLength: 8)
                        }
                        appleTools.padding(.bottom, 14)
                    }
                    .padding(.horizontal, 28).frame(maxWidth: 560)
                    .frame(minHeight: geometry.size.height).frame(maxWidth: .infinity)
                }.scrollBounceBehavior(.basedOnSize)
            }
        }
        .buttonStyle(.plain).presentationBackground(Color.canvas)
    }

    private var appleMetadata: some View {
        let displayed = player.pendingTrack ?? player.current
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayed?.title ?? "KlyMusic")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Color.playerPrimary)
                    .lineLimit(1)
                if let artist = displayed?.artist, !artist.isEmpty, !player.isLiveStream {
                    Button {
                        Haptics.selection()
                        let target: AppNavigationTarget
                        if let artistID = displayed?.artistID, !artistID.isEmpty {
                            target = .artist(id: artistID, name: artist)
                        } else {
                            target = .query(title: artist, query: artist)
                        }
                        player.isPresented = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(220))
                            player.requestedNavigation = target
                        }
                    } label: {
                        Text(artist)
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(Color.playerSecondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(TrackRowButtonStyle())
                    .accessibilityIdentifier("player.openArtist")
                } else {
                    Text(displayed?.artist ?? "")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(Color.playerSecondary)
                        .lineLimit(1)
                }
                if player.pendingTrack != nil {
                    Text(L("Hazırlanıyor…"))
                        .font(.caption)
                        .foregroundStyle(Color.playerSecondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let displayed {
                HStack(spacing: 10) {
                    Button { Haptics.light(); library.toggleFavorite(displayed) } label: {
                        Image(systemName: library.isFavorite(displayed) ? "star.fill" : "star")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(library.isFavorite(displayed) ? Color.coral : Color.playerPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.playerPrimary.opacity(0.11), in: Circle())
                            .frame(width: 34, height: 44)
                            .contentShape(Rectangle())
                    }.accessibilityIdentifier("player.favorite")
                        .accessibilityLabel(library.isFavorite(displayed) ? L("Favorilerden çıkar") : L("Favorilere ekle"))
                    TrackMenu(track: displayed, pill: true, inNowPlayingSheet: true)
                }
            }
        }
    }

    private var appleTransport: some View {
        HStack(spacing: 48) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 56, height: 60)
                    .contentShape(Rectangle())
            }.accessibilityLabel("Önceki şarkı")
            Button { player.toggle() } label: {
                Group {
                    if player.isBuffering || waitingForFirstTrack {
                        ProgressView().tint(Color.playerPrimary)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 44, weight: .bold))
                            .offset(x: player.isPlaying ? 0 : 2)
                    }
                }
                .frame(width: 68, height: 62)
                .contentShape(Rectangle())
            }.accessibilityLabel(player.isPlaying ? L("Duraklat") : L("Çal"))
                .accessibilityIdentifier("player.playPause").accessibilityValue(player.isPlaying ? "playing" : "paused")
            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 56, height: 60)
                    .contentShape(Rectangle())
            }.accessibilityLabel("Sonraki şarkı")
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(Color.playerPrimary)
    }

    private var appleTools: some View {
        HStack(spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                    showQueue = false
                    showLyrics.toggle()
                }
                if showLyrics { player.loadLyrics() }
            } label: {
                Image(systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(showLyrics ? Color.playerPrimary : Color.playerSecondary)
                    .frame(width: 38, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.playerPrimary.opacity(showLyrics ? 0.14 : 0))
                    )
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
            }.accessibilityLabel("Şarkı sözleri").accessibilityIdentifier("lyrics.toggle").accessibilityValue(showLyrics ? "visible" : "hidden")
            AirPlayControl()
                .frame(width: 46, height: 46)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("AirPlay")
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                    showLyrics = false
                    showQueue.toggle()
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(showQueue ? Color.playerPrimary : Color.playerSecondary)
                    .frame(width: 38, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.playerPrimary.opacity(showQueue ? 0.14 : 0))
                    )
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
            }.accessibilityLabel("Çalma sırası").accessibilityIdentifier("player.queue").accessibilityValue(showQueue ? "visible" : "hidden")
        }
    }

}

private struct ApplePlaybackTimeline: View {
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    @AppStorage("dolbyAtmosMode") private var dolbyAtmosMode = "auto"
    @State private var scrubbing = false
    @State private var scrub = 0.0
    private var value: Double { scrubbing ? scrub : clock.position }
    private var isOfflineTrack: Bool {
        guard let current = player.pendingTrack ?? player.current else { return false }
        return library.localURL(current.id) != nil
    }

    var body: some View {
        VStack(spacing: 3) {
            if player.isLiveStream {
                Capsule().fill(Color.playerPrimary.opacity(0.28))
                    .overlay(Capsule().fill(Color.coral.opacity(0.65)))
                    .frame(height: 5)
                    .frame(height: 22)
                    .accessibilityElement()
                    .accessibilityLabel(L("CANLI YAYIN"))
                    .accessibilityIdentifier("player.scrubber")
                HStack(spacing: 6) {
                    Circle().fill(Color.coral).frame(width: 6, height: 6)
                    Text(L("CANLI YAYIN"))
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                }
                .foregroundStyle(Color.playerSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                GeometryReader { geometry in
                    let fraction = max(0, min(1, value / max(1, clock.duration)))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.playerPrimary.opacity(0.18))
                        Capsule().fill(Color.playerPrimary.opacity(scrubbing ? 0.96 : 0.72))
                            .frame(width: fraction * geometry.size.width)
                    }.frame(height: scrubbing ? 9 : 5).frame(height: 22)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .animation(.easeOut(duration: 0.14), value: scrubbing)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                            scrubbing = true
                            scrub = min(max(0, event.location.x / max(1, geometry.size.width)), 1) * max(0, clock.duration)
                        }.onEnded { _ in Haptics.light(); player.seek(scrub); scrubbing = false })
                }.frame(height: 22)
                    .accessibilityElement().accessibilityLabel("Oynatma konumu")
                    .accessibilityValue(Track.time(value)).accessibilityIdentifier("player.scrubber")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: player.seek(clock.position + 5)
                        case .decrement: player.seek(clock.position - 5)
                        @unknown default: break
                        }
                    }
                ZStack {
                    HStack(spacing: 0) {
                        Text(Track.time(value))
                            .accessibilityIdentifier("player.elapsed")
                            .accessibilityValue(String(Int(clock.position)))
                        Spacer(minLength: 0)
                        Text("−" + Track.time(max(0, clock.duration - value)))
                    }
                    HStack(spacing: 6) {
                        if dolbyAtmosMode != "off" {
                            DolbyAtmosBadge(color: .playerSecondary)
                        }
                        if isOfflineTrack {
                            if dolbyAtmosMode != "off" {
                                Text("·")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.playerSecondary)
                                    .accessibilityHidden(true)
                            }
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(L("Çevrimdışı"))
                                    .font(.system(size: 10.5, weight: .semibold))
                            }
                            .foregroundStyle(Color.playerSecondary)
                        }
                    }
                }.font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(Color.playerSecondary)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("player.timeline")
    }
}

private final class SystemVolumeObserver: ObservableObject {
    @Published var volume: Double = 0.68
    private var token: NSKeyValueObservation?
    weak var bridgeSlider: UISlider?

    init() {
        let session = AVAudioSession.sharedInstance()
        let initial = Double(session.outputVolume)
        #if targetEnvironment(simulator)
        volume = initial > 0.01 ? initial : 0.68
        #else
        volume = initial
        #endif
        token = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let updated = change.newValue else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                #if targetEnvironment(simulator)
                if updated > 0.01 { self.volume = Double(updated) }
                #else
                self.volume = Double(updated)
                #endif
            }
        }
    }

    func setVolume(_ target: Double) {
        let clamped = min(1.0, max(0.0, target))
        volume = clamped
        bridgeSlider?.setValue(Float(clamped), animated: false)
    }
}

private struct AppleVolumeBar: View {
    @StateObject private var observer = SystemVolumeObserver()
    @State private var dragging = false
    @State private var bridgeSlider: UISlider?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.playerSecondary)
                .frame(width: 15, alignment: .leading)
                .accessibilityHidden(true)

            GeometryReader { geometry in
                let width = max(1, geometry.size.width)
                let fillWidth = max(0, min(1, observer.volume)) * width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.playerPrimary.opacity(0.18))
                    Capsule().fill(Color.playerPrimary.opacity(dragging ? 0.96 : 0.72))
                        .frame(width: fillWidth)
                }
                .frame(height: dragging ? 9 : 5)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.14), value: dragging)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { event in
                            dragging = true
                            observer.bridgeSlider = bridgeSlider
                            observer.setVolume(event.location.x / width)
                        }
                        .onEnded { _ in dragging = false }
                )
            }
            .frame(height: 24)
            .background {
                VolumeControl(slider: $bridgeSlider)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.playerSecondary)
                .frame(width: 18, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Ses seviyesi"))
        .accessibilityValue("\(Int(observer.volume * 100))%")
    }
}

struct LyricsView: View {
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var clock: PlaybackClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var following = true
    @State private var sharedLyricItem: SharedLyricPayload?
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
                            LazyVStack(alignment: .leading, spacing: 26) {
                                ForEach(lines) { line in
                                    VStack(alignment: .leading, spacing: 14) {
                                        if following && active >= 0 && line.id == active + 1 && isInstrumentalGap(before: line) {
                                            InstrumentalInterludeDots(isPlaying: player.isPlaying)
                                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                        }
                                        Button {
                                            following = true
                                            Haptics.selection()
                                            player.seek(line.time)
                                            scroll(to: line.id, proxy: proxy)
                                        } label: {
                                            AnimatedLyricLine(
                                                text: line.text,
                                                isActive: line.id == active,
                                                isPast: line.id < active,
                                                distance: active >= 0 ? abs(line.id - active) : 0,
                                                depthBlur: following && !reduceMotion && !voiceOver && active >= 0,
                                                progress: progress(for: line)
                                            )
                                        }.buttonStyle(LyricLineButtonStyle())
                                            .contextMenu {
                                                Button {
                                                    following = true
                                                    Haptics.selection()
                                                    player.seek(line.time)
                                                    scroll(to: line.id, proxy: proxy)
                                                } label: {
                                                    Label(L("Bu satırdan çal"), systemImage: "play.fill")
                                                }
                                                if let track = player.current ?? player.pendingTrack {
                                                    Button {
                                                        Haptics.light()
                                                        sharedLyricItem = makeLyricPayload(for: track, around: line)
                                                    } label: {
                                                        Label(L("Sözleri Paylaş…"), systemImage: "square.and.arrow.up")
                                                    }
                                                }
                                            }
                                            .accessibilityIdentifier("lyrics.line.\(line.id)")
                                            .accessibilityLabel(line.text)
                                            .accessibilityHint(L("Bu satırdan çal"))
                                            .accessibilityAddTraits(line.id == active ? .isSelected : [])
                                    }
                                    .id(line.id)
                                }
                            }.padding(.vertical, 76).padding(.horizontal, 4)
                        }
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: 0.08),
                                    .init(color: .black, location: 0.90),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .accessibilityIdentifier("lyrics.scroll")
                        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in following = false })
                        .onAppear { proxy.scrollTo(max(0, active), anchor: UnitPoint(x: 0.5, y: 0.38)) }
                        .onChange(of: active) { _, id in
                            guard following, !voiceOver, id >= 0 else { return }
                            scroll(to: id, proxy: proxy)
                        }
                        if !player.isLiveStream {
                            HStack(spacing: 8) {
                                Button {
                                    Haptics.selection()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        player.singModeEnabled.toggle()
                                    }
                                } label: {
                                    Image(systemName: player.singModeEnabled ? "music.mic.circle.fill" : "music.mic")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(player.singModeEnabled ? .white : Color.playerPrimary)
                                        .frame(width: 34, height: 34)
                                        .background(
                                            Circle().fill(player.singModeEnabled ? Color.coral : Color.playerPrimary.opacity(0.14))
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("Sing Vokal Ayarı"))
                                .accessibilityIdentifier("lyrics.singToggle")
                                .accessibilityValue(player.singModeEnabled ? "on" : "off")

                                if player.singModeEnabled {
                                    Slider(value: $player.singVocalLevel, in: 0...1)
                                        .tint(Color.coral)
                                        .frame(width: 108)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.32), in: Capsule())
                                        .accessibilityLabel(L("Vokal Düzeyi"))
                                        .accessibilityIdentifier("lyrics.singSlider")
                                }
                                Spacer(minLength: 8)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 6)
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
                ScrollView(showsIndicators: false) {
                    Text(plain).font(.title2.weight(.semibold)).foregroundStyle(Color.playerPrimary)
                        .lineSpacing(12).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
                }
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.08),
                            .init(color: .black, location: 0.90),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .transition(.opacity)
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
        .sheet(item: $sharedLyricItem) { payload in LyricShareSheet(payload: payload) }
    }

    private func makeLyricPayload(for track: Track, around line: LyricLine) -> SharedLyricPayload {
        guard let idx = lines.firstIndex(where: { $0.id == line.id }) else {
            return SharedLyricPayload(track: track, candidateLines: [line.text], selectedIndices: [0])
        }
        let lower = max(0, idx - 1)
        let upper = min(lines.count - 1, idx + 3)
        let window = Array(lines[lower...upper].map(\.text))
        let initialOffset = idx - lower
        var selected: Set<Int> = [initialOffset]
        if initialOffset + 1 < window.count { selected.insert(initialOffset + 1) }
        return SharedLyricPayload(track: track, candidateLines: window, selectedIndices: selected)
    }

    private func isInstrumentalGap(before line: LyricLine) -> Bool {
        guard let index = lines.firstIndex(where: { $0.id == line.id }), index > 0 else { return false }
        let prevTime = lines[index - 1].time
        return (line.time - prevTime) >= 7.0 && clock.position >= prevTime + 2.5 && clock.position < line.time - 0.6
    }

    // LRCLIB supplies line timestamps, not word timings. Sweep only within the real line interval.
    private func progress(for line: LyricLine) -> Double {
        guard line.id == active else { return line.id < active ? 1 : 0 }
        let end = lines.first(where: { $0.time > line.time })?.time ?? clock.duration
        guard end > line.time else { return 1 }
        return min(1, max(0, (clock.position - line.time) / (end - line.time)))
    }

    private func scroll(to id: Int, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.86)) {
            proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.38))
        }
    }
}

private struct LyricLineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0, anchor: .leading)
            .opacity(configuration.isPressed ? 0.84 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct InterludeDotMetrics {
    let scales: [CGFloat]
    let offsets: [CGFloat]
    let opacities: [Double]

    static func compute(at date: Date, isPlaying: Bool, reduceMotion: Bool) -> InterludeDotMetrics {
        guard isPlaying && !reduceMotion else {
            return InterludeDotMetrics(scales: [0.92, 1.0, 0.92], offsets: [0, 0, 0], opacities: [0.55, 0.75, 0.55])
        }
        let t: Double = date.timeIntervalSinceReferenceDate * 3.8
        var scales: [CGFloat] = []
        var offsets: [CGFloat] = []
        var opacities: [Double] = []
        for idx in 0..<3 {
            let raw: Double = Foundation.sin(t - Double(idx) * 0.85)
            let wave: Double = 0.5 + 0.5 * raw
            scales.append(CGFloat(0.78 + 0.38 * wave))
            offsets.append(CGFloat(-3.5 * wave))
            opacities.append(0.38 + 0.62 * wave)
        }
        return InterludeDotMetrics(scales: scales, offsets: offsets, opacities: opacities)
    }
}

private struct InstrumentalInterludeDots: View {
    var isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying || reduceMotion)) { timeline in
            let metrics = InterludeDotMetrics.compute(at: timeline.date, isPlaying: isPlaying, reduceMotion: reduceMotion)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.playerPrimary.opacity(metrics.opacities[index]))
                        .frame(width: 9, height: 9)
                        .scaleEffect(metrics.scales[index])
                        .offset(y: metrics.offsets[index])
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.playerPrimary.opacity(0.08), in: Capsule())
        .accessibilityHidden(true)
    }
}

private struct LyricVisualState {
    let baseOpacity: Double
    let blurRadius: CGFloat
    let scale: CGFloat
    let yOffset: CGFloat
    let sweepProgress: Double
    let sweepTail: Double
    let sweepColorAtTail: Color

    static func compute(isActive: Bool, isPast: Bool, distance: Int, depthBlur: Bool, progress: Double, reduceMotion: Bool) -> LyricVisualState {
        let baseOpacity: Double
        if isActive {
            baseOpacity = 0.42
        } else if !depthBlur {
            baseOpacity = 0.84
        } else if distance <= 1 {
            baseOpacity = isPast ? 0.50 : 0.62
        } else if distance == 2 {
            baseOpacity = isPast ? 0.36 : 0.46
        } else {
            baseOpacity = 0.28
        }

        let blurRadius: CGFloat = (!depthBlur || isActive) ? 0 : min(2.4, CGFloat(distance) * 0.72)
        let scale: CGFloat = (isActive || reduceMotion) ? 1.0 : 0.93
        let yOffset: CGFloat = (isActive && !reduceMotion) ? -2.0 : 0.0
        let p: Double = reduceMotion ? 1.0 : min(1.0, max(0.0, progress))
        let tail: Double = min(1.0, p + 0.18)
        let tailColor: Color = p >= 0.985 ? .black : .clear
        return LyricVisualState(
            baseOpacity: baseOpacity,
            blurRadius: blurRadius,
            scale: scale,
            yOffset: yOffset,
            sweepProgress: p,
            sweepTail: tail,
            sweepColorAtTail: tailColor
        )
    }
}

private struct AnimatedLyricLine: View {
    var text: String
    var isActive: Bool
    var isPast: Bool
    var distance: Int
    var depthBlur: Bool
    var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var textSize = 31.0

    private var label: some View {
        Text(text).font(.system(size: textSize, weight: .bold))
            .lineSpacing(4).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        let state = LyricVisualState.compute(
            isActive: isActive,
            isPast: isPast,
            distance: distance,
            depthBlur: depthBlur,
            progress: progress,
            reduceMotion: reduceMotion
        )
        label
            .foregroundStyle(Color.playerPrimary.opacity(state.baseOpacity))
            .overlay(alignment: .leading) {
                if isActive {
                    label.foregroundStyle(Color.playerPrimary)
                        .shadow(color: Color.white.opacity(0.32), radius: 11, y: 1)
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0.0),
                                    .init(color: .black, location: state.sweepProgress),
                                    .init(color: state.sweepColorAtTail, location: state.sweepTail)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                        .animation(reduceMotion ? nil : .linear(duration: 0.22), value: progress)
                        .accessibilityHidden(true)
                }
            }
            .blur(radius: state.blurRadius)
            .scaleEffect(state.scale, anchor: .leading)
            .offset(y: state.yOffset)
            .animation(reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.74), value: isActive)
            .contentShape(Rectangle()).accessibilityHidden(true)
    }
}

struct QueueView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            AlbumBackdrop(artwork: nil, isPlaying: false)
            InlineQueuePanel(showQueue: nil, onDismiss: { dismiss() })
                .padding(.top, 12)
        }
        .presentationBackground(Color.canvas)
        .presentationDragIndicator(.visible)
    }
}

struct InlineQueuePanel: View {
    var showQueue: Binding<Bool>?
    var onDismiss: (() -> Void)? = nil
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    @AppStorage("infiniteAutoplay") private var infiniteAutoplay = true
    @State private var showHistory = false
    @State private var confirmClear = false

    private var sleepBadgeText: String? {
        if let rem = player.sleepRemainingSeconds, rem > 0 {
            return String(format: "%d:%02d", rem / 60, rem % 60)
        }
        if player.sleepAtEnd {
            return L("Şarkı bitince")
        }
        return nil
    }

    var body: some View {
        let currentTrack = player.pendingTrack ?? player.current
        let upcoming = player.upcomingTracks
        let history: [Track] = {
            if !player.historyTracks.isEmpty { return Array(player.historyTracks.reversed()) }
            return Array(library.recent.filter { $0.id != currentTrack?.id }.prefix(10))
        }()
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(L("Çalma sırası"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.playerPrimary)
                if let sleepBadgeText {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.fill").font(.system(size: 10))
                        Text(sleepBadgeText).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    }
                    .foregroundStyle(Color.coral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.coral.opacity(0.14), in: Capsule())
                    .accessibilityIdentifier("queue.sleepBadge")
                }
                Spacer(minLength: 0)
                Menu {
                    Menu {
                        Button {
                            player.setSleep(minutes: nil)
                        } label: {
                            if player.sleepUntil == nil && !player.sleepAtEnd {
                                Label(L("Kapalı"), systemImage: "checkmark")
                            } else {
                                Text(L("Kapalı"))
                            }
                        }
                        Button {
                            player.setSleepAtEnd()
                        } label: {
                            if player.sleepAtEnd {
                                Label(L("Şarkı bitince"), systemImage: "checkmark")
                            } else {
                                Text(L("Şarkı bitince"))
                            }
                        }
                        ForEach([15, 30, 60], id: \.self) { minutes in
                            let label = String(format: L("%lld dakika"), Int64(minutes))
                            Button {
                                player.setSleep(minutes: minutes)
                            } label: {
                                if let rem = player.sleepRemainingSeconds,
                                   rem <= minutes * 60,
                                   rem > (minutes == 15 ? 0 : (minutes == 30 ? 15 * 60 : 30 * 60)) {
                                    Label(label, systemImage: "checkmark")
                                } else {
                                    Text(label)
                                }
                            }
                        }
                    } label: { Label(L("Uyku zamanlayıcısı"), systemImage: "moon") }
                    if !upcoming.isEmpty {
                        Section {
                            Button(role: .destructive) { confirmClear = true } label: { Label(L("Sırayı temizle"), systemImage: "trash") }
                                .accessibilityIdentifier("queue.clear")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.playerPrimary)
                        .frame(width: 34, height: 34)
                        .background(Color.playerPrimary.opacity(0.12), in: Circle())
                        .contentShape(Circle())
                }
                .accessibilityLabel(L("Sıra seçenekleri")).accessibilityIdentifier("queue.options")

                if onDismiss != nil || showQueue != nil {
                    Button {
                        Haptics.selection()
                        if let onDismiss { onDismiss() }
                        else { showQueue?.wrappedValue = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.playerPrimary)
                            .frame(width: 34, height: 34)
                            .background(Color.playerPrimary.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel(L("Kapat"))
                }
            }
            .padding(.horizontal, 4)

            List {
                if showHistory {
                    Section {
                        if history.isEmpty {
                            Text(L("Henüz çalınan şarkı yok"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(history) { track in
                                Button {
                                    Haptics.selection()
                                    if player.historyTracks.contains(where: { $0.id == track.id }) {
                                        player.playFromHistory(id: track.id)
                                    } else {
                                        player.play(track)
                                    }
                                } label: {
                                    HStack(spacing: 13) {
                                        queueArtwork(track)
                                        queueMetadata(track)
                                    }.padding(.vertical, 6).contentShape(Rectangle())
                                }.buttonStyle(TrackRowButtonStyle())
                                    .accessibilityIdentifier("queue.history.\(track.id)")
                            }
                        }
                    } header: {
                        Text(L("Geçmiş")).font(.subheadline.weight(.semibold)).foregroundStyle(Color.playerSecondary).textCase(nil)
                    }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                if let current = currentTrack {
                    Section {
                        HStack(spacing: 13) {
                            queueArtwork(current)
                            queueMetadata(current)
                            Spacer(minLength: 8)
                            if player.pendingTrack != nil {
                                ProgressView().controlSize(.small)
                            } else if player.isPlaying {
                                NowPlayingBars(isPlaying: true, color: .coral, size: 15)
                            } else {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 16)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 0.5)
                        )
                        .padding(.vertical, 2)
                        .accessibilityIdentifier("queue.current")
                    } header: {
                        Text("Şimdi çalıyor").font(.subheadline.weight(.semibold)).foregroundStyle(Color.playerSecondary).textCase(nil)
                    }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                Section {
                    if upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Sıra boş")).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            Text(L("Şarkı menüsünden sıraya ekleyebilirsin.")).font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 16)
                        .accessibilityIdentifier("queue.empty")
                    } else {
                        ForEach(upcoming) { track in
                            VStack(spacing: 0) {
                                Button { player.playUpcoming(id: track.id) } label: {
                                    HStack(spacing: 13) {
                                        queueArtwork(track)
                                        queueMetadata(track)
                                    }.padding(.vertical, 8).contentShape(Rectangle())
                                }.buttonStyle(TrackRowButtonStyle())
                                    .accessibilityLabel("\(track.title), \(track.artist)")
                                    .accessibilityHint(L("Çal")).accessibilityIdentifier("queue.track.\(track.id)")
                                    .contextMenu {
                                        Button { player.playNext(track) } label: { Label("Sıradaki çal", systemImage: "text.line.first.and.arrowtriangle.forward") }
                                        Button(role: .destructive) { player.removeUpcoming(id: track.id) } label: { Label("Sıradan kaldır", systemImage: "minus.circle") }
                                    }
                                Divider().overlay(Color.primary.opacity(0.08)).padding(.leading, 61)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Haptics.light()
                                    player.removeUpcoming(id: track.id)
                                } label: {
                                    Label(L("Sıradan kaldır"), systemImage: "minus.circle")
                                }
                            }
                        }.onMove { offsets, destination in
                            player.moveUpcoming(from: offsets, to: destination, snapshot: upcoming)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(L("Sıradaki")).font(.headline).foregroundStyle(.primary)
                        if !upcoming.isEmpty { Text("\(upcoming.count)").font(.subheadline).foregroundStyle(.secondary) }
                        Spacer(minLength: 0)
                        Button {
                            Haptics.selection()
                            withAnimation(.easeInOut(duration: 0.2)) { showHistory.toggle() }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(showHistory ? Color.white : Color.playerSecondary)
                                .frame(width: 34, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(showHistory ? Color.coral : Color.primary.opacity(0.08))
                                )
                                .frame(width: 36, height: 38)
                                .contentShape(Rectangle())
                        }.accessibilityLabel(L("Geçmiş")).accessibilityIdentifier("queue.historyToggle")
                        Button { Haptics.selection(); player.toggleShuffle() } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(player.shuffle ? Color.white : Color.playerSecondary)
                                .frame(width: 34, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(player.shuffle ? Color.coral : Color.primary.opacity(0.08))
                                )
                                .frame(width: 36, height: 38)
                                .contentShape(Rectangle())
                        }.accessibilityLabel(L("Karıştır")).accessibilityValue(player.shuffle ? L("Açık") : L("Kapalı"))
                        Button { Haptics.selection(); player.cycleRepeat() } label: {
                            Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(player.repeatMode == .off ? Color.playerSecondary : Color.white)
                                .frame(width: 34, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(player.repeatMode == .off ? Color.primary.opacity(0.08) : Color.coral)
                                )
                                .frame(width: 36, height: 38)
                                .contentShape(Rectangle())
                        }.accessibilityLabel(L("Tekrarlama")).accessibilityValue(player.repeatMode == .off ? L("Kapalı") : (player.repeatMode == .one ? L("Bir Şarkı") : L("Tümü")))
                        Button {
                            Haptics.selection()
                            infiniteAutoplay.toggle()
                            if infiniteAutoplay { player.prepareNext() }
                        } label: {
                            Image(systemName: "infinity")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(infiniteAutoplay ? Color.white : Color.playerSecondary)
                                .frame(width: 34, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(infiniteAutoplay ? Color.coral : Color.primary.opacity(0.08))
                                )
                                .frame(width: 36, height: 38)
                                .contentShape(Rectangle())
                        }.accessibilityLabel(L("Otomatik Çal")).accessibilityIdentifier("queue.autoplayToggle")
                    }.textCase(nil)
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 2))
            }
            .listStyle(.plain).listSectionSpacing(14).scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .confirmationDialog(L("Sıradaki şarkılar kaldırılsın mı?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L("Sırayı temizle"), role: .destructive) { player.clearUpcoming() }
            Button(L("Vazgeç"), role: .cancel) { }
        } message: { Text(L("Çalan şarkı devam eder.")) }
    }

    private func queueArtwork(_ track: Track) -> some View {
        Artwork(url: track.artwork, radius: 7).frame(width: 48, height: 48)
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
    @Binding var slider: UISlider?

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.tintColor = UIColor(Color.playerSecondary)
        view.showsRouteButton = false
        DispatchQueue.main.async {
            slider = view.subviews.compactMap { $0 as? UISlider }.first
        }
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        view.tintColor = UIColor(Color.playerSecondary)
        if slider == nil {
            DispatchQueue.main.async {
                slider = view.subviews.compactMap { $0 as? UISlider }.first
            }
        }
    }
}

struct SharedLyricPayload: Identifiable {
    let id = UUID()
    let track: Track
    let candidateLines: [String]
    let selectedIndices: Set<Int>
}

private struct LyricShareSheet: View {
    let payload: SharedLyricPayload
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int>
    @State private var coverImage: UIImage?
    @State private var palette = ArtworkPalette.fallback
    @State private var shareImage: UIImage?

    init(payload: SharedLyricPayload) {
        self.payload = payload
        _selected = State(initialValue: payload.selectedIndices)
    }

    private var activeLines: [String] {
        selected.sorted().compactMap { payload.candidateLines.indices.contains($0) ? payload.candidateLines[$0] : nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    LyricShareCardView(track: payload.track, lines: activeLines, cover: coverImage, palette: palette)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.32), radius: 20, y: 10)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Satır seç (en fazla 4)"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                        ForEach(Array(payload.candidateLines.enumerated()), id: \.offset) { idx, text in
                            let on = selected.contains(idx)
                            Button {
                                Haptics.selection()
                                if on {
                                    if selected.count > 1 { selected.remove(idx) }
                                } else if selected.count < 4 {
                                    selected.insert(idx)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(on ? Color.coral : .secondary)
                                    Text(text)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Color.musicElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                        }
                    }

                    Button {
                        Haptics.light()
                        renderAndShare()
                    } label: {
                        Label(L("Kartı Paylaş"), systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.coral, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(CardButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.pageBackground)
            .navigationTitle(L("Şarkı Sözü Kartı"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Vazgeç")) { dismiss() }.foregroundStyle(Color.coral)
                }
            }
            .task {
                if let url = ArtworkRequest.sized(payload.track.artworkURL, pixels: 480),
                   let img = await ArtworkCache.shared.image(url, fallback: payload.track.artworkURL, maxPixels: 480) {
                    coverImage = img
                    if let p = await ArtworkCache.shared.palette(img) { palette = p }
                }
            }
            .sheet(item: Binding(
                get: { shareImage.map { IdentifiableImage(image: $0) } },
                set: { if $0 == nil { shareImage = nil } }
            )) { item in
                ActivityView(items: [item.image, "\(payload.track.title) — \(payload.track.artist)"])
            }
        }
    }

    @MainActor private func renderAndShare() {
        let card = LyricShareCardView(track: payload.track, lines: activeLines, cover: coverImage, palette: palette)
            .frame(width: 360)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        if let rendered = renderer.uiImage {
            shareImage = rendered
        }
    }
}

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct LyricShareCardView: View {
    let track: Track
    let lines: [String]
    let cover: UIImage?
    let palette: ArtworkPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Group {
                    if let cover {
                        Image(uiImage: cover).resizable().scaledToFill()
                    } else {
                        ZStack { Color.white.opacity(0.14); Image(systemName: "music.note").foregroundStyle(.white) }
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.headline.bold()).foregroundStyle(.white).lineLimit(1)
                    Text(track.artist).font(.subheadline).foregroundStyle(.white.opacity(0.84)).lineLimit(1)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .lineSpacing(3)
                }
            }
            .padding(.vertical, 8)

            HStack {
                Image(systemName: "music.note").font(.caption.bold())
                Text("KlyMusic").font(.caption.weight(.bold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.82))
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [palette.top.color, palette.left.color, palette.bottom.color],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
