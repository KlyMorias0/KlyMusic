import WidgetKit
import SwiftUI
import ActivityKit
import UIKit

private let klyCoral = Color(red: 250.0 / 255.0, green: 35.0 / 255.0, blue: 59.0 / 255.0)

private enum WidgetLinks {
    static let open = URL(string: "klymusic://player/open")!
    static let toggle = URL(string: "klymusic://player/toggle")!
    static let next = URL(string: "klymusic://player/next")!
    static let previous = URL(string: "klymusic://player/previous")!
    static let favorite = URL(string: "klymusic://player/favorite")!
}

private struct ActivityRenderMetrics {
    let title: String
    let artist: String
    let isPlaying: Bool
    let isDolbyAtmos: Bool
    let isFavorite: Bool
    let trailingStyle: String
    let accentColor: Color
    let thumbnailImage: UIImage?
    let fraction: Double
    let canAutoTick: Bool
    let timerRange: ClosedRange<Date>
    let elapsedText: String
    let remainingText: String
    let compactRemainingText: String

    init(state: KlyMusicActivityAttributes.ContentState) {
        let trimmedTitle = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmedTitle.isEmpty ? "KlyMusic" : trimmedTitle
        artist = state.artist
        isPlaying = state.isPlaying
        isDolbyAtmos = state.isDolbyAtmos
        isFavorite = state.isFavorite
        trailingStyle = state.trailingStyle == "timer" ? "timer" : "waveform"

        let r = min(1.0, max(0.0, state.accentR.isFinite ? state.accentR : 0.98))
        let g = min(1.0, max(0.0, state.accentG.isFinite ? state.accentG : 0.14))
        let b = min(1.0, max(0.0, state.accentB.isFinite ? state.accentB : 0.23))
        accentColor = Color(red: r, green: g, blue: b)

        if let base64 = state.thumbnailBase64, let data = Data(base64Encoded: base64) {
            thumbnailImage = UIImage(data: data)
        } else {
            thumbnailImage = nil
        }

        let safeDuration = (state.duration.isFinite && state.duration > 0) ? state.duration : 0.0
        let rawElapsed = (state.elapsed.isFinite && state.elapsed >= 0) ? state.elapsed : 0.0
        let safeElapsed = safeDuration > 0 ? min(rawElapsed, safeDuration) : rawElapsed
        let remaining = max(0.0, safeDuration - safeElapsed)

        fraction = safeDuration > 0 ? min(1.0, max(0.0, safeElapsed / safeDuration)) : 0.0
        canAutoTick = state.isPlaying && safeDuration > 0 && remaining > 0.5

        let anchor = state.updatedAt
        let start = anchor.addingTimeInterval(-safeElapsed)
        let end = anchor.addingTimeInterval(max(1.0, remaining))
        if start < end {
            timerRange = start...end
        } else {
            timerRange = anchor...anchor.addingTimeInterval(1.0)
        }

        elapsedText = Self.formatTime(safeElapsed)
        remainingText = "−" + Self.formatTime(remaining)
        compactRemainingText = Self.formatTime(remaining)
    }

    private static func formatTime(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? max(0, Int(seconds)) : 0
        return String(format: "%d:%02d", safe / 60, safe % 60)
    }
}

private struct WidgetDolbyDoubleDMark: Shape {
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

private struct WidgetWaveformIcon: View {
    let isPlaying: Bool
    let color: Color
    let barHeights: [CGFloat]

    init(isPlaying: Bool, color: Color, height: CGFloat = 14) {
        self.isPlaying = isPlaying
        self.color = color
        let ratios: [CGFloat] = isPlaying ? [0.50, 0.95, 0.65, 0.85] : [0.35, 0.48, 0.35, 0.42]
        self.barHeights = ratios.map { max(3, height * $0) }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 2.2, height: barHeights[index])
            }
        }
    }
}

private struct WidgetArtworkView: View {
    let image: UIImage?
    let size: CGFloat
    let cornerRadius: CGFloat
    let iconSize: CGFloat

    init(image: UIImage?, size: CGFloat, cornerRadius: CGFloat) {
        self.image = image
        self.size = size
        self.cornerRadius = cornerRadius
        self.iconSize = size * 0.44
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [klyCoral, klyCoral.opacity(0.62)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
    }
}

private struct WidgetProgressBar: View {
    let metrics: ActivityRenderMetrics

    var body: some View {
        if metrics.canAutoTick {
            ProgressView(timerInterval: metrics.timerRange, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .labelsHidden()
            .progressViewStyle(.linear)
            .tint(Color.white.opacity(0.92))
        } else {
            ProgressView(value: metrics.fraction, total: 1.0)
                .labelsHidden()
                .progressViewStyle(.linear)
                .tint(Color.white.opacity(0.84))
        }
    }
}

private struct WidgetTimeRow: View {
    let metrics: ActivityRenderMetrics

    var body: some View {
        HStack(spacing: 0) {
            if metrics.canAutoTick {
                Text(timerInterval: metrics.timerRange, countsDown: false)
                    .multilineTextAlignment(.leading)
            } else {
                Text(metrics.elapsedText)
            }
            Spacer(minLength: 8)
            if metrics.canAutoTick {
                HStack(spacing: 0) {
                    Text("−")
                    Text(timerInterval: metrics.timerRange, countsDown: true)
                        .multilineTextAlignment(.trailing)
                }
            } else {
                Text(metrics.remainingText)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(Color.white.opacity(0.72))
    }
}

private struct WidgetControlsRow: View {
    let metrics: ActivityRenderMetrics

    var body: some View {
        HStack(spacing: 0) {
            Link(destination: WidgetLinks.favorite) {
                Image(systemName: metrics.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(metrics.isFavorite ? klyCoral : Color.white.opacity(0.82))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            Link(destination: WidgetLinks.previous) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            Link(destination: WidgetLinks.toggle) {
                Image(systemName: metrics.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            Link(destination: WidgetLinks.next) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let metrics: ActivityRenderMetrics

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                WidgetArtworkView(image: metrics.thumbnailImage, size: 54, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(metrics.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(metrics.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .lineLimit(1)
                    if metrics.isDolbyAtmos {
                        HStack(spacing: 4) {
                            WidgetDolbyDoubleDMark()
                                .fill(Color.white.opacity(0.75), style: FillStyle(eoFill: true))
                                .frame(width: 12, height: 8)
                            Text("Dolby Atmos")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                WidgetWaveformIcon(isPlaying: metrics.isPlaying, color: klyCoral, height: 16)
            }

            VStack(spacing: 4) {
                WidgetProgressBar(metrics: metrics)
                WidgetTimeRow(metrics: metrics)
            }

            WidgetControlsRow(metrics: metrics)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [
                    metrics.accentColor.opacity(0.32),
                    Color.black.opacity(0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .activityBackgroundTint(Color.black.opacity(0.76))
        .activitySystemActionForegroundColor(.white)
        .environment(\.colorScheme, .dark)
    }
}

@main
struct KlyMusicWidgetsBundle: WidgetBundle {
    var body: some Widget {
        KlyMusicLiveActivity()
    }
}

struct KlyMusicLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KlyMusicActivityAttributes.self) { context in
            let metrics = ActivityRenderMetrics(state: context.state)
            LockScreenLiveActivityView(metrics: metrics)
                .widgetURL(WidgetLinks.open)
        } dynamicIsland: { context in
            let metrics = ActivityRenderMetrics(state: context.state)
            return makeDynamicIsland(metrics: metrics)
        }
    }

    private func makeDynamicIsland(metrics: ActivityRenderMetrics) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                WidgetArtworkView(image: metrics.thumbnailImage, size: 54, cornerRadius: 12)
            }
            DynamicIslandExpandedRegion(.trailing) {
                HStack(spacing: 5) {
                    if metrics.isDolbyAtmos {
                        WidgetDolbyDoubleDMark()
                            .fill(Color.white.opacity(0.78), style: FillStyle(eoFill: true))
                            .frame(width: 12, height: 8)
                    }
                    WidgetWaveformIcon(isPlaying: metrics.isPlaying, color: klyCoral, height: 15)
                }
                .padding(.top, 4)
            }
            DynamicIslandExpandedRegion(.center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metrics.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(metrics.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.74))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(spacing: 8) {
                    VStack(spacing: 3) {
                        WidgetProgressBar(metrics: metrics)
                        WidgetTimeRow(metrics: metrics)
                    }
                    WidgetControlsRow(metrics: metrics)
                }
                .padding(.top, 4)
            }
        } compactLeading: {
            WidgetArtworkView(image: metrics.thumbnailImage, size: 22, cornerRadius: 6)
        } compactTrailing: {
            if metrics.trailingStyle == "timer" {
                if metrics.canAutoTick {
                    Text(timerInterval: metrics.timerRange, countsDown: true)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(klyCoral)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 44, alignment: .trailing)
                } else {
                    Text(metrics.compactRemainingText)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(klyCoral)
                }
            } else {
                WidgetWaveformIcon(isPlaying: metrics.isPlaying, color: klyCoral, height: 14)
            }
        } minimal: {
            WidgetArtworkView(image: metrics.thumbnailImage, size: 22, cornerRadius: 11)
        }
        .widgetURL(WidgetLinks.open)
        .keylineTint(metrics.accentColor)
    }
}
