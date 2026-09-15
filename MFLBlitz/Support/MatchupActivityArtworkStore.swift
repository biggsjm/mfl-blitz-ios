import Foundation
import UIKit

/// Bounded logo thumbnails travel in the ActivityKit payload. Image reads retain
/// the cookie-free transport and run outside score refreshes; no shared disk cache.
actor MatchupActivityArtworkStore {
    static let shared = MatchupActivityArtworkStore()

    static let maximumLogoBytes = 900

    func prepare(urls: [URL]) async -> MatchupActivityAttributes.Artwork? {
        guard let source = await TeamArtworkLoader.shared.image(for: urls), !Task.isCancelled else { return nil }
        return Self.makeArtwork(from: source)
    }

    static func makeArtwork(from source: CGImage) -> MatchupActivityAttributes.Artwork? {
        let color = palette(source)
        for dimension in [64, 48, 40, 36] {
            guard let image = thumbnail(source, dimension: dimension, background: color),
                  let png = ActivityLogoPNG.encode(image), png.count <= maximumLogoBytes else { continue }
            return .init(imageData: png, red: color.0, green: color.1, blue: color.2)
        }
        for dimension in [80, 64, 48, 40, 32, 24, 16, 12] {
            guard let image = thumbnail(source, dimension: dimension, background: color) else { continue }
            let uiImage = UIImage(cgImage: image)
            if let png = uiImage.pngData(), png.count <= maximumLogoBytes {
                return .init(imageData: png, red: color.0, green: color.1, blue: color.2)
            }
            for quality in [0.55, 0.35, 0.18, 0.08] {
                if let jpeg = uiImage.jpegData(compressionQuality: quality), jpeg.count <= maximumLogoBytes {
                    return .init(imageData: jpeg, red: color.0, green: color.1, blue: color.2)
                }
            }
        }
        return .init(imageData: nil, red: color.0, green: color.1, blue: color.2)
    }

    private static func thumbnail(_ image: CGImage, dimension: Int, background: (Double, Double, Double)) -> CGImage? {
        let ratio = min(1, Double(dimension) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * ratio)), height = max(1, Int(Double(image.height) * ratio))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(red: background.0, green: background.1, blue: background.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func palette(_ image: CGImage) -> (Double, Double, Double) {
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let sampled = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 16, bitsPerComponent: 8,
                bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return true
        }
        guard sampled else { return (0.10, 0.34, 0.57) }
        // Choose one dominant hue, weighting saturated team colors above skin,
        // grass highlights and gray/white photo backgrounds. Never average hues.
        var weights = [Double](repeating: 0, count: 12)
        for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] > 200 {
            let r = Double(pixels[offset]) / 255, g = Double(pixels[offset + 1]) / 255, b = Double(pixels[offset + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b), delta = high - low
            guard high > 0.18, delta > 0.08 else { continue }
            let saturation = delta / high
            guard saturation > 0.35 else { continue }
            let hue: Double
            if high == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) / 6 }
            else if high == g { hue = ((b - r) / delta + 2) / 6 }
            else { hue = ((r - g) / delta + 4) / 6 }
            let normalized = hue < 0 ? hue + 1 : hue
            let bucket = Int((normalized * 12).rounded()) % 12
            weights[bucket] += saturation * saturation
        }
        guard let dominant = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[dominant] > 0 else {
            return (0.04, 0.30, 0.70)
        }
        let color = UIColor(hue: Double(dominant) / 12, saturation: 0.90, brightness: 0.82, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        var rgb = [Double(r), Double(g), Double(b)]
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        // Keep white secondary text legible even over yellow or pale source art.
        while 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2]) > 0.16 {
            rgb = rgb.map { $0 * 0.95 }
        }
        return (rgb[0], rgb[1], rgb[2])
    }
}
