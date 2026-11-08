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
    func image(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        let key = url.absoluteString
        if let image = memory.object(forKey: key as NSString) { return image }
        if let task = pending[key] { return await task.value }
        let task = Task { await self.fetch(url) }
        pending[key] = task
        let image = await task.value
        pending[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4)) }
        return image
    }
    private func fetch(_ url: URL) async -> UIImage? {
        let name = MusicFiles.filename(url.absoluteString)
        let pinned = MusicFiles.root.appendingPathComponent(name + ".art")
        let local = directory.appendingPathComponent(name)
        var data = (try? Data(contentsOf: pinned)) ?? (try? Data(contentsOf: local))
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

struct Artwork: View {
    var url: String?
    var radius: CGFloat = 12
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.musicSurface
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note").font(.system(size: min(geometry.size.width, geometry.size.height) * 0.3, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: url) {
            image = nil
            let loaded = await ArtworkCache.shared.image(url.flatMap(URL.init(string:)))
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .accessibilityHidden(true)
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
