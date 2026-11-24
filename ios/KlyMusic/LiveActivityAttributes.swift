import Foundation
import ActivityKit
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 16.2, *)
public struct KlyMusicActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        public var artist: String
        public var album: String
        public var isPlaying: Bool
        public var isDolbyAtmos: Bool
        public var isFavorite: Bool
        public var trailingStyle: String
        public var elapsed: Double
        public var duration: Double
        public var updatedAt: Date
        public var accentR: Double
        public var accentG: Double
        public var accentB: Double
        public var thumbnailBase64: String?

        public init(
            title: String,
            artist: String,
            album: String,
            isPlaying: Bool,
            isDolbyAtmos: Bool,
            isFavorite: Bool,
            trailingStyle: String,
            elapsed: Double,
            duration: Double,
            updatedAt: Date,
            accentR: Double,
            accentG: Double,
            accentB: Double,
            thumbnailBase64: String? = nil
        ) {
            self.title = title
            self.artist = artist
            self.album = album
            self.isPlaying = isPlaying
            self.isDolbyAtmos = isDolbyAtmos
            self.isFavorite = isFavorite
            self.trailingStyle = trailingStyle
            self.elapsed = elapsed
            self.duration = duration
            self.updatedAt = updatedAt
            self.accentR = accentR
            self.accentG = accentG
            self.accentB = accentB
            self.thumbnailBase64 = thumbnailBase64
        }
    }

    public var trackID: String

    public init(trackID: String) {
        self.trackID = trackID
    }

    #if canImport(UIKit)
    public static func makeThumbnailBase64(from image: UIImage) -> String? {
        let targetSize = CGSize(width: 44, height: 44)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { _ in
            let width = image.size.width
            let height = image.size.height
            if width > 0, height > 0, width != height {
                let scale = max(targetSize.width / width, targetSize.height / height)
                let drawSize = CGSize(width: width * scale, height: height * scale)
                let origin = CGPoint(
                    x: (targetSize.width - drawSize.width) * 0.5,
                    y: (targetSize.height - drawSize.height) * 0.5
                )
                image.draw(in: CGRect(origin: origin, size: drawSize))
            } else {
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }
        guard var data = rendered.jpegData(compressionQuality: 0.40) else { return nil }
        if data.count > 2200 {
            guard let compact = rendered.jpegData(compressionQuality: 0.25) else { return nil }
            data = compact
        }
        guard data.count <= 2400 else { return nil }
        return data.base64EncodedString()
    }
    #endif
}
