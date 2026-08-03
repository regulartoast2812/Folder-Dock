import AppKit
import QuickLookThumbnailing
import SwiftUI

struct FilePreview: View {
    let url: URL
    let size: CGFloat
    @StateObject private var loader: ThumbnailLoader

    init(url: URL, size: CGFloat) {
        self.url = url
        self.size = size
        _loader = StateObject(wrappedValue: ThumbnailLoader(url: url, size: size))
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

    init(url: URL, size: CGFloat) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: NSSize(width: size * scale, height: size * scale),
            scale: scale,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            guard let image = thumbnail?.nsImage else { return }
            DispatchQueue.main.async {
                self?.image = image
            }
        }
    }
}
