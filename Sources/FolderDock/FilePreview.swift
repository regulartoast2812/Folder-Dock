import AppKit
import QuickLookThumbnailing
import SwiftUI

struct FilePreview: View {
    let url: URL
    let size: CGFloat
    @StateObject private var loader: ThumbnailLoader

    init(url: URL, size: CGFloat, modificationDate: Date? = nil) {
        self.url = url
        self.size = size
        _loader = StateObject(wrappedValue: ThumbnailLoader(
            url: url,
            size: size,
            modificationDate: modificationDate
        ))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                FileIcon(url: url, size: size)
            }
        }
        .frame(width: size, height: size)
    }
}

@MainActor
final class ThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    init(url: URL, size: CGFloat, modificationDate: Date?) {
        let key = ThumbnailCache.key(for: url, size: size, modificationDate: modificationDate)
        if let cachedImage = ThumbnailCache.images.object(forKey: key as NSString) {
            image = cachedImage
            return
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            // `size` is already in points; multiplying it by scale here requested a
            // 4×-larger image on Retina displays and made video previews needlessly slow.
            size: NSSize(width: size, height: size),
            scale: scale,
            representationTypes: .lowQualityThumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            guard let image = thumbnail?.nsImage else { return }
            DispatchQueue.main.async {
                ThumbnailCache.images.setObject(image, forKey: key as NSString, cost: Int(size * size * scale * scale * 4))
                self?.image = image
            }
        }
    }
}

@MainActor
private enum ThumbnailCache {
    static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static func key(for url: URL, size: CGFloat, modificationDate: Date?) -> String {
        let modified = modificationDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(url.path)|\(modified)|\(size)"
    }
}
