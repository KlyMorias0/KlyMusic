import SwiftUI
import ImageIO
import CryptoKit

actor ArtworkCache {
    static let shared = ArtworkCache()
    private let memory = NSCache<NSString, UIImage>()
    private var pending: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config)
    }()
    private var directory: URL {
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Artwork")
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }
    init() { memory.totalCostLimit = 48 * 1024 * 1024; memory.countLimit = 140 }
    func image(_ url: URL?, fallback: URL? = nil, maxPixels: Int = 960) async -> UIImage? {
        guard let url else { return nil }
        let decodeMax = max(240, min(1200, maxPixels))
        let cacheKey = "\(url.absoluteString)#\(decodeMax)"
        if let image = memory.object(forKey: cacheKey as NSString) { return image }
        if let task = pending[cacheKey] { return await task.value }
        let task = Task { await self.fetch(url, fallback: fallback, decodeMax: decodeMax) }
        pending[cacheKey] = task
        let image = await task.value
        pending[cacheKey] = nil
        if let image { memory.setObject(image, forKey: cacheKey as NSString, cost: Int(image.size.width * image.size.height * 4)) }
        return image
    }
    private func fetch(_ url: URL, fallback: URL?, decodeMax: Int) async -> UIImage? {
        let name = MusicFiles.filename(url.absoluteString)
        let pinned = MusicFiles.root.appendingPathComponent(name + ".art")
        let local = directory.appendingPathComponent(name)
        var data = (try? Data(contentsOf: pinned)) ?? (try? Data(contentsOf: local))
        if data == nil, let host = url.host?.lowercased(), host.hasSuffix(".mzstatic.com") {
            for candidatePixels in [960, 640, 600, 480, 320] where candidatePixels >= decodeMax {
                if let variant = ArtworkRequest.variant(url, exactPixels: candidatePixels) {
                    let variantName = MusicFiles.filename(variant.absoluteString)
                    if let reused = (try? Data(contentsOf: MusicFiles.root.appendingPathComponent(variantName + ".art")))
                        ?? (try? Data(contentsOf: directory.appendingPathComponent(variantName))) {
                        data = reused
                        break
                    }
                }
            }
        }
        if data == nil, let fallback {
            let fallbackName = MusicFiles.filename(fallback.absoluteString)
            data = (try? Data(contentsOf: MusicFiles.root.appendingPathComponent(fallbackName + ".art")))
                ?? (try? Data(contentsOf: directory.appendingPathComponent(fallbackName)))
        }
        if data == nil {
            do {
                var request = URLRequest(url: url); request.timeoutInterval = 12
                let (bytes, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count < 15_000_000 else { return nil }
                data = bytes
                try? bytes.write(to: local, options: .atomic)
                trim()
            } catch { return nil }
        }
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: decodeMax,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
    func palette(_ image: UIImage) -> ArtworkPalette? { ArtworkPalette.extract(image) }

    func pin(_ url: URL?) async {
        guard let url else { return }
        _ = await image(url)
        let name = MusicFiles.filename(url.absoluteString)
        let source = directory.appendingPathComponent(name)
        let target = MusicFiles.root.appendingPathComponent(name + ".art")
        if !FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.copyItem(at: source, to: target) }
    }
    private func trim() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]), files.count > 350 else { return }
        let oldest = files.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for file in oldest.prefix(files.count - 300) { try? FileManager.default.removeItem(at: file) }
    }
}

enum ArtworkRequest {
    static let buckets = [160, 200, 320, 480, 640, 960]
    static func variant(_ url: URL?, exactPixels size: Int) -> URL? {
        guard let url, let host = url.host?.lowercased(), host.hasSuffix(".mzstatic.com") else { return url }
        let value = url.absoluteString.replacingOccurrences(of: #"/\d+x\d+(bb)?\."#, with: "/\(size)x\(size)bb.", options: .regularExpression)
        return URL(string: value) ?? url
    }
    static func sized(_ url: URL?, pixels: Int) -> URL? {
        guard let url, let host = url.host?.lowercased(), host.hasSuffix(".mzstatic.com") else { return url }
        let size = buckets.first(where: { $0 >= pixels }) ?? 960
        return variant(url, exactPixels: size)
    }
}

struct Artwork: View {
    var url: String?
    var radius: CGFloat = 12
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            let pixels = min(PlaybackPreferences.savesData() ? 640 : 960, max(160, Int(geometry.size.width * scale)))
            let requested = ArtworkRequest.sized(url.flatMap(URL.init(string:)), pixels: pixels)
            ZStack {
                Color.musicSurface
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else {
                    Image(systemName: "music.note").font(.system(size: min(geometry.size.width, geometry.size.height) * 0.3, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            .task(id: requested) {
                let loaded = await ArtworkCache.shared.image(requested, fallback: url.flatMap(URL.init(string:)), maxPixels: pixels)
                guard !Task.isCancelled else { return }
                image = loaded
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            if radius > 0 {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ArtworkPalette: Equatable, Sendable {
    struct Swatch: Equatable, Sendable {
        var r: Double; var g: Double; var b: Double
        var color: Color { Color(red: r, green: g, blue: b) }
    }
    var left: Swatch
    var right: Swatch
    var top: Swatch
    var bottom: Swatch
    static let fallback = ArtworkPalette(
        left: .init(r: 0.38, g: 0.23, b: 0.23),
        right: .init(r: 0.25, g: 0.19, b: 0.33),
        top: .init(r: 0.42, g: 0.20, b: 0.28),
        bottom: .init(r: 0.18, g: 0.14, b: 0.26)
    )
    static func extract(_ image: UIImage) -> ArtworkPalette? {
        guard let cg = image.cgImage else { return nil }
        let side = 24
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))); return true
        }
        guard drawn else { return nil }
        func swatch(_ xRange: Range<Int>, _ yRange: Range<Int>) -> Swatch {
            var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
            for y in yRange { for x in xRange {
                let i = (y * side + x) * 4
                let r = Double(bytes[i]) / 255, g = Double(bytes[i + 1]) / 255, b = Double(bytes[i + 2]) / 255
                let high = max(r, max(g, b)), low = min(r, min(g, b))
                guard high > 0.12, low < 0.88 else { continue }
                let saturation = (high - low) / max(0.01, high)
                let weight = 0.12 + saturation * saturation * 3.2
                red += r * weight; green += g * weight; blue += b * weight; total += weight
            }}
            guard total > 0 else { return .init(r: 0.24, g: 0.24, b: 0.24) }
            red /= total; green /= total; blue /= total
            let lift = max(1, 0.68 / max(0.05, max(red, max(green, blue))))
            return .init(r: min(1, red * lift), g: min(1, green * lift), b: min(1, blue * lift))
        }
        return .init(
            left: swatch(0..<(side / 2), 0..<side),
            right: swatch((side / 2)..<side, 0..<side),
            top: swatch(0..<side, 0..<(side / 2)),
            bottom: swatch(0..<side, (side / 2)..<side)
        )
    }
}

struct AlbumBackdrop: View {
    var artwork: String?
    var isPlaying: Bool = false
    @State private var palette = ArtworkPalette.fallback
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isPlaying || reduceMotion)) { timeline in
            let t = isPlaying && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate * 0.22 : 0.0
            let driftX = CGFloat(sin(t)) * 34
            let driftY = CGFloat(cos(t * 0.85)) * 28
            GeometryReader { geometry in
                let w = geometry.size.width
                let h = geometry.size.height
                ZStack {
                    Color.canvas
                    Ellipse().fill(palette.top.color.opacity(scheme == .dark ? 0.56 : 0.20))
                        .frame(width: w * 1.15, height: h * 0.72)
                        .blur(radius: 85)
                        .position(x: w * 0.38 + driftX, y: h * 0.16 + driftY * 0.5)
                    Ellipse().fill(palette.left.color.opacity(scheme == .dark ? 0.54 : 0.18))
                        .frame(width: w * 1.1, height: h * 0.8)
                        .blur(radius: 80)
                        .position(x: -w * 0.04 - driftX * 0.6, y: h * 0.44 - driftY)
                    Ellipse().fill(palette.right.color.opacity(scheme == .dark ? 0.50 : 0.16))
                        .frame(width: w * 1.05, height: h * 0.85)
                        .blur(radius: 85)
                        .position(x: w * 0.96 + driftX * 0.5, y: h * 0.66 + driftY)
                    Ellipse().fill(palette.bottom.color.opacity(scheme == .dark ? 0.46 : 0.14))
                        .frame(width: w * 1.2, height: h * 0.68)
                        .blur(radius: 90)
                        .position(x: w * 0.45 - driftX, y: h * 0.92 - driftY * 0.5)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.75), value: palette)
            }
        }
        .ignoresSafeArea().allowsHitTesting(false)
        .task(id: artwork) {
            let url = ArtworkRequest.sized(artwork.flatMap(URL.init(string:)), pixels: 480)
            if let image = await ArtworkCache.shared.image(url, fallback: artwork.flatMap(URL.init(string:)), maxPixels: 320),
               let colors = await ArtworkCache.shared.palette(image), !Task.isCancelled {
                palette = colors
            } else if !Task.isCancelled {
                palette = .fallback
            }
        }
    }
}

extension Color {
    static let coral = Color(red: 250.0 / 255.0, green: 35.0 / 255.0, blue: 59.0 / 255.0)
    static let musicBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
    static let musicSurface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.035, alpha: 1) : UIColor(white: 0.97, alpha: 1) })
    static let musicElevated = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.93, alpha: 1) })
    static let musicAccent = coral
    static let playerBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.075, green: 0.08, blue: 0.09, alpha: 1) : UIColor(red: 0.965, green: 0.96, blue: 0.95, alpha: 1) })
    static let playerSurface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.12, green: 0.128, blue: 0.14, alpha: 1) : UIColor(red: 0.925, green: 0.92, blue: 0.91, alpha: 1) })
    static let playerPrimary = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.91, green: 0.92, blue: 0.935, alpha: 1) : UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1) })
    static let playerSecondary = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.59, green: 0.61, blue: 0.64, alpha: 1) : UIColor(red: 0.42, green: 0.43, blue: 0.45, alpha: 1) })
    static let ink = Color(red: 0.075, green: 0.08, blue: 0.11)
}
