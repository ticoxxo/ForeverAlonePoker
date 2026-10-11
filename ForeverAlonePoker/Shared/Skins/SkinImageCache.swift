import Foundation
import ImageIO
import UIKit

/// Decodes downloaded skin images off the main thread, downsampled to the
/// size cards are drawn at (a 750×1050 PNG costs ~3 MB decoded; a 360 px
/// thumbnail a tenth of that), and keeps them in memory.
actor SkinImageCache {
    static let shared = SkinImageCache()

    /// Tallest card on screen is ~88 pt; 360 px covers it at @3x with margin.
    static let cardPixelSize = 360

    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 160
    }

    func image(at url: URL, maxPixelSize: Int = SkinImageCache.cardPixelSize) -> UIImage? {
        let key = "\(url.path)#\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        let image = UIImage(cgImage: thumbnail)
        cache.setObject(image, forKey: key)
        return image
    }

    /// Warms the cache for a table (52 faces and the back) before it shows.
    func prefetch(_ urls: [URL]) {
        for url in urls { _ = image(at: url) }
    }

    /// Files were replaced (a newer version of a skin was installed).
    func removeAll() {
        cache.removeAllObjects()
    }
}
