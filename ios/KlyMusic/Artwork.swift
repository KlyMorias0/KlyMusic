import SwiftUI
import ImageIO
import CryptoKit

actor ArtworkCache {
    static let shared = ArtworkCache()
    private let memory = NSCache<NSString, UIImage>()
    private var pending: [String: Task<UIImage?, Never>] = [:]
    private var directory: URL {
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Artwork")
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }
    init() { memory.totalCostLimit = 48 * 1024 * 1024; memory.countLimit = 120 }
    func image(_ url: URL?, fallback: URL? = nil) async -> UIImage? {
        guard let url else { return nil }
        let key = url.absoluteString
        if let image = memory.object(forKey: key as NSString) { return image }
        if let task = pending[key] { return await task.value }
        let task = Task { await self.fetch(url, fallback: fallback) }
        pending[key] = task
        let image = await task.value
        pending[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4)) }
        return image
    }
    private func fetch(_ url: URL, fallback: URL?) async -> UIImage? {
        let name = MusicFiles.filename(url.absoluteString)
        let pinned = MusicFiles.root.appendingPathComponent(name + ".art")
        let local = directory.appendingPathComponent(name)
        var data = (try? Data(contentsOf: pinned)) ?? (try? Data(contentsOf: local))
        if data == nil, let fallback {
            let fallbackName = MusicFiles.filename(fallback.absoluteString)
            data = (try? Data(contentsOf: MusicFiles.root.appendingPathComponent(fallbackName + ".art")))
                ?? (try? Data(contentsOf: directory.appendingPathComponent(fallbackName)))
        }
        if data == nil {
            do {
                var request = URLRequest(url: url); request.timeoutInterval = 15
                let (bytes, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count < 15_000_000 else { return nil }
                data = bytes
                try? bytes.write(to: local, options: .atomic)
                trim()
            } catch { return nil }
        }
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200,
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
    static func sized(_ url: URL?, pixels: Int) -> URL? {
        guard let url, let host = url.host?.lowercased(), host.hasSuffix(".mzstatic.com") else { return url }
        let size = [160, 320, 640, 960].first(where: { $0 >= pixels }) ?? 960
        let value = url.absoluteString.replacingOccurrences(of: #"/\d+x\d+(bb)?\."#, with: "/\(size)x\(size)bb.", options: .regularExpression)
        return URL(string: value) ?? url
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
                let loaded = await ArtworkCache.shared.image(requested, fallback: url.flatMap(URL.init(string:)))
                guard !Task.isCancelled else { return }
                image = loaded
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
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
    static let fallback = ArtworkPalette(left: .init(r: 0.38, g: 0.23, b: 0.23), right: .init(r: 0.25, g: 0.19, b: 0.33))
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
        func swatch(_ first: Int, _ end: Int) -> Swatch {
            var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
            for y in 0..<side { for x in first..<end {
                let i = (y * side + x) * 4
                let r = Double(bytes[i]) / 255, g = Double(bytes[i + 1]) / 255, b = Double(bytes[i + 2]) / 255
                let high = max(r, max(g, b)), low = min(r, min(g, b))
                guard high > 0.12, low < 0.88 else { continue }
                let saturation = (high - low) / max(0.01, high)
                let weight = 0.12 + saturation * saturation * 3
                red += r * weight; green += g * weight; blue += b * weight; total += weight
            }}
            guard total > 0 else { return .init(r: 0.24, g: 0.24, b: 0.24) }
            red /= total; green /= total; blue /= total
            let lift = max(1, 0.65 / max(0.05, max(red, max(green, blue))))
            return .init(r: min(1, red * lift), g: min(1, green * lift), b: min(1, blue * lift))
        }
        return .init(left: swatch(0, side / 2), right: swatch(side / 2, side))
    }
}

struct AlbumBackdrop: View {
    var artwork: String?
    @State private var palette = ArtworkPalette.fallback
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.canvas
                Ellipse().fill(palette.left.color.opacity(scheme == .dark ? 0.58 : 0.18))
                    .frame(width: geometry.size.width * 1.1, height: geometry.size.height * 0.8)
                    .blur(radius: 75).position(x: 0, y: geometry.size.height * 0.3)
                Ellipse().fill(palette.right.color.opacity(scheme == .dark ? 0.52 : 0.16))
                    .frame(width: geometry.size.width, height: geometry.size.height * 0.9)
                    .blur(radius: 80).position(x: geometry.size.width, y: geometry.size.height * 0.8)
            }.animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: palette)
        }.ignoresSafeArea().allowsHitTesting(false)
            .task(id: artwork) {
                let url = ArtworkRequest.sized(artwork.flatMap(URL.init(string:)), pixels: 640)
                if let image = await ArtworkCache.shared.image(url, fallback: artwork.flatMap(URL.init(string:))), let colors = await ArtworkCache.shared.palette(image), !Task.isCancelled { palette = colors }
                else if !Task.isCancelled { palette = .fallback }
            }
    }
}

extension Color {
    static let coral = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.91, green: 0.49, blue: 0.45, alpha: 1) : UIColor(red: 0.73, green: 0.27, blue: 0.24, alpha: 1)
    })
    static let musicBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
    static let musicSurface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.035, alpha: 1) : UIColor(white: 0.97, alpha: 1) })
    static let musicElevated = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.93, alpha: 1) })
    static let musicAccent = Color(red: 1, green: 0.176, blue: 0.333)
    static let playerBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.075, green: 0.08, blue: 0.09, alpha: 1) : UIColor(red: 0.965, green: 0.96, blue: 0.95, alpha: 1) })
    static let playerSurface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.12, green: 0.128, blue: 0.14, alpha: 1) : UIColor(red: 0.925, green: 0.92, blue: 0.91, alpha: 1) })
    static let playerPrimary = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.91, green: 0.92, blue: 0.935, alpha: 1) : UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1) })
    static let playerSecondary = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.59, green: 0.61, blue: 0.64, alpha: 1) : UIColor(red: 0.42, green: 0.43, blue: 0.45, alpha: 1) })
    static let ink = Color(red: 0.075, green: 0.08, blue: 0.11)
}
