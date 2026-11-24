import Foundation
import ActivityKit
import SwiftUI
import UIKit

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    private var activity: Activity<KlyMusicActivityAttributes>?
    private var cachedVisuals: (key: String, thumbnailBase64: String?, r: Double, g: Double, b: Double)?
    private var loadingArtworkKey: String?
    private var artworkTask: Task<Void, Never>?
    private var lastSyncSignature: SyncSignature?
    private var lastSyncDate: Date = .distantPast
    private var lastSyncedElapsed: Double = 0
    private var lastSyncedWasPlaying: Bool = false

    private struct SyncSignature: Equatable {
        let trackID: String
        let title: String
        let artist: String
        let album: String
        let isPlaying: Bool
        let isDolbyAtmos: Bool
        let isFavorite: Bool
        let trailingStyle: String
        let durationBucket: Int
        let visualsKey: String?
    }

    private init() {}

    func sync(player: MusicPlayer, force: Bool = false) {
        let enabled = UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled, let track = player.current else {
            endAllActivities()
            return
        }

        let artworkKey = track.id + "|" + (track.artwork ?? "")
        if cachedVisuals?.key != artworkKey {
            loadVisualsIfNeeded(for: track, artworkKey: artworkKey, player: player)
        }

        let visuals = cachedVisuals?.key == artworkKey ? cachedVisuals : nil
        let fallback = ArtworkPalette.fallback.top
        let duration = (player.duration.isFinite && player.duration > 0)
            ? player.duration
            : ((track.duration.isFinite && track.duration > 0) ? track.duration : 0)
        let elapsed = (player.position.isFinite && player.position >= 0)
            ? (duration > 0 ? min(player.position, duration) : player.position)
            : 0
        let isDolbyAtmos = UserDefaults.standard.string(forKey: "dolbyAtmosMode") != "off"
        let isFavorite = player.library?.isFavorite(track) ?? false
        let rawStyle = UserDefaults.standard.string(forKey: "islandTrailingStyle") ?? "waveform"
        let trailingStyle = rawStyle == "timer" ? "timer" : "waveform"

        let signature = SyncSignature(
            trackID: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            isPlaying: player.isPlaying,
            isDolbyAtmos: isDolbyAtmos,
            isFavorite: isFavorite,
            trailingStyle: trailingStyle,
            durationBucket: Int(duration.rounded()),
            visualsKey: visuals == nil ? nil : artworkKey
        )

        let now = Date()
        let timeSinceLastPush = now.timeIntervalSince(lastSyncDate)
        let expectedElapsed = lastSyncedWasPlaying ? (lastSyncedElapsed + timeSinceLastPush) : lastSyncedElapsed
        let elapsedJumped = abs(elapsed - expectedElapsed) > 1.8

        if activity == nil {
            activity = Activity<KlyMusicActivityAttributes>.activities.first { $0.attributes.trackID == track.id }
        }
        let matchesActiveTrack = activity?.attributes.trackID == track.id

        if !force && matchesActiveTrack && signature == lastSyncSignature && !elapsedJumped && timeSinceLastPush < 4.0 {
            return
        }

        let state = KlyMusicActivityAttributes.ContentState(
            title: track.title,
            artist: track.artist,
            album: track.album,
            isPlaying: player.isPlaying,
            isDolbyAtmos: isDolbyAtmos,
            isFavorite: isFavorite,
            trailingStyle: trailingStyle,
            elapsed: elapsed,
            duration: duration,
            updatedAt: now,
            accentR: visuals?.r ?? fallback.r,
            accentG: visuals?.g ?? fallback.g,
            accentB: visuals?.b ?? fallback.b,
            thumbnailBase64: visuals?.thumbnailBase64
        )

        lastSyncSignature = signature
        lastSyncDate = now
        lastSyncedElapsed = elapsed
        lastSyncedWasPlaying = player.isPlaying

        let staleSeconds = player.isPlaying ? max(30.0, (duration - elapsed) + 15.0) : 3600.0
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(staleSeconds))

        if let currentActivity = activity, currentActivity.attributes.trackID == track.id {
            Task {
                await currentActivity.update(content)
            }
            return
        }

        let previousActivity = activity
        activity = nil
        Task {
            if let previousActivity {
                await previousActivity.end(nil, dismissalPolicy: .immediate)
            }
            for existing in Activity<KlyMusicActivityAttributes>.activities where existing.attributes.trackID != track.id {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
        }

        do {
            activity = try Activity<KlyMusicActivityAttributes>.request(
                attributes: KlyMusicActivityAttributes(trackID: track.id),
                content: content,
                pushType: nil
            )
        } catch {
            // Simulator or system Live Activity restrictions are ignored cleanly.
        }
    }

    private func loadVisualsIfNeeded(for track: Track, artworkKey: String, player: MusicPlayer) {
        guard loadingArtworkKey != artworkKey else { return }
        artworkTask?.cancel()
        loadingArtworkKey = artworkKey
        let artworkURL = track.artworkURL
        let trackID = track.id
        artworkTask = Task { [weak self, weak player] in
            let sized = ArtworkRequest.sized(artworkURL, pixels: 160)
            let image = await ArtworkCache.shared.image(sized, fallback: artworkURL, maxPixels: 160)
            guard !Task.isCancelled else { return }
            let palette: ArtworkPalette?
            if let image {
                palette = await ArtworkCache.shared.palette(image)
            } else {
                palette = nil
            }
            guard !Task.isCancelled else { return }
            let thumb = image.flatMap { KlyMusicActivityAttributes.makeThumbnailBase64(from: $0) }
            let swatch = palette?.top ?? ArtworkPalette.fallback.top
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.loadingArtworkKey = nil
                guard let player,
                      let current = player.current,
                      current.id == trackID,
                      (current.id + "|" + (current.artwork ?? "")) == artworkKey else { return }
                self.cachedVisuals = (artworkKey, thumb, swatch.r, swatch.g, swatch.b)
                self.sync(player: player, force: true)
            }
        }
    }

    private func endAllActivities() {
        artworkTask?.cancel()
        artworkTask = nil
        loadingArtworkKey = nil
        lastSyncSignature = nil
        lastSyncDate = .distantPast
        let previousActivity = activity
        activity = nil
        let remaining = Activity<KlyMusicActivityAttributes>.activities
        guard previousActivity != nil || !remaining.isEmpty else { return }
        Task {
            if let previousActivity {
                await previousActivity.end(nil, dismissalPolicy: .immediate)
            }
            for existing in remaining {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

struct InAppDynamicIslandOverlay: View {
    @AppStorage("inAppIslandEnabled") private var enabled = false
    @AppStorage("dolbyAtmosMode") private var dolbyAtmosMode = "auto"
    @AppStorage("islandTrailingStyle") private var trailingStyle = "waveform"
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var clock: PlaybackClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var accentColor: Color = ArtworkPalette.fallback.top.color

    private var activeTrack: Track? { player.current ?? player.pendingTrack }

    var body: some View {
        Group {
            if enabled, let track = activeTrack {
                ZStack(alignment: .top) {
                    if expanded {
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84)) {
                                    expanded = false
                                }
                            }
                        expandedCard(for: track)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                            .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                    } else {
                        compactCapsule(for: track)
                            .padding(.top, 4)
                            .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: expanded ? .infinity : nil, alignment: .top)
                .task(id: track.artwork) {
                    let url = ArtworkRequest.sized(track.artworkURL, pixels: 160)
                    if let image = await ArtworkCache.shared.image(url, fallback: track.artworkURL, maxPixels: 160),
                       let palette = await ArtworkCache.shared.palette(image),
                       !Task.isCancelled {
                        accentColor = palette.top.color
                    } else if !Task.isCancelled {
                        accentColor = ArtworkPalette.fallback.top.color
                    }
                }
            }
        }
        .onChange(of: enabled) { _, isEnabled in
            if !isEnabled { expanded = false }
        }
        .onChange(of: activeTrack == nil) { _, isEmpty in
            if isEmpty { expanded = false }
        }
    }

    private func compactCapsule(for track: Track) -> some View {
        let remaining = max(0.0, clock.duration - clock.position)
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82)) {
                expanded = true
            }
        } label: {
            HStack(spacing: 14) {
                Artwork(url: track.artwork, radius: 6)
                    .frame(width: 22, height: 22)
                Spacer(minLength: 32)
                if trailingStyle == "timer" {
                    Text(Track.time(remaining))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.coral)
                } else {
                    NowPlayingBars(isPlaying: player.isPlaying, color: .coral, size: 12)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .fixedSize(horizontal: true, vertical: false)
            .background(Color.black, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.32), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Oynatıcıyı aç"))
        .accessibilityIdentifier("player.inAppIsland")
    }

    private func expandedCard(for track: Track) -> some View {
        let safeDuration = max(1.0, clock.duration.isFinite ? clock.duration : 0.0)
        let clampedPosition = min(max(0.0, clock.position.isFinite ? clock.position : 0.0), safeDuration)
        let fraction = min(1.0, max(0.0, clampedPosition / safeDuration))
        let remaining = max(0.0, (clock.duration.isFinite ? clock.duration : 0.0) - clampedPosition)
        let favorite = library.isFavorite(track)

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    expanded = false
                    player.isPresented = true
                } label: {
                    HStack(spacing: 12) {
                        Artwork(url: track.artwork, radius: 12)
                            .frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.74))
                                .lineLimit(1)
                            if dolbyAtmosMode != "off" {
                                DolbyAtmosBadge(color: .white.opacity(0.72))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .trailing, spacing: 6) {
                    NowPlayingBars(isPlaying: player.isPlaying, color: .coral, size: 14)
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84)) {
                            expanded = false
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                            .frame(width: 26, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Kapat"))
                }
            }

            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Color.white.opacity(0.88))
                            .frame(width: fraction * geometry.size.width)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(Track.time(clampedPosition))
                    Spacer()
                    Text("−" + Track.time(remaining))
                }
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.72))
            }

            HStack(spacing: 0) {
                Button {
                    library.toggleFavorite(track)
                    LiveActivityManager.shared.sync(player: player)
                } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(favorite ? Color.coral : .white.opacity(0.85))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favorite ? L("Favorilerden çıkar") : L("Favorilere ekle"))

                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Önceki şarkı"))

                Button { player.toggle() } label: {
                    Group {
                        if player.isBuffering || (player.current == nil && player.pendingTrack != nil) {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? L("Duraklat") : L("Çal"))

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Sonraki şarkı"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.28), Color.black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .background(Color.black, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.inAppIsland")
    }
}
