import CoreGraphics
import Foundation
import zlib

/// A small indexed PNG keeps logo edges sharper than a heavily compressed JPEG.
/// At 36 pixels, even uncompressible 16-color data fits the activity's logo budget.
enum ActivityLogoPNG {
    static func encode(_ image: CGImage) -> Data? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= 80, height <= 80 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let pixels = stride(from: 0, to: bytes.count, by: 4).map { [Int(bytes[$0]), Int(bytes[$0 + 1]), Int(bytes[$0 + 2])] }
        func spread(_ group: [[Int]]) -> (channel: Int, range: Int) {
            let ranges: [(channel: Int, range: Int)] = (0..<3).map { channel in
                let values = group.map { $0[channel] }
                let maximum = values.max() ?? 0
                let minimum = values.min() ?? 0
                return (channel, maximum - minimum)
            }
            return ranges.max(by: { $0.range < $1.range }) ?? (0, 0)
        }
        var groups = [pixels]
        while groups.count < 16 {
            guard let index = groups.indices.filter({ groups[$0].count > 1 && spread(groups[$0]).range > 0 })
                .max(by: { spread(groups[$0]).range * groups[$0].count < spread(groups[$1]).range * groups[$1].count }) else { break }
            let group = groups.remove(at: index)
            let channel = spread(group).channel
            let sorted = group.sorted { $0[channel] < $1[channel] }
            groups.append(Array(sorted.prefix(sorted.count / 2)))
            groups.append(Array(sorted.suffix(sorted.count - sorted.count / 2)))
        }
        let palette = groups.map { group in (0..<3).map { channel in group.reduce(0) { $0 + $1[channel] } / group.count } }
        func distance(_ pixel: [Int], _ color: [Int]) -> Int {
            var total = 0
            for channel in 0..<3 {
                let difference = pixel[channel] - color[channel]
                total += difference * difference
            }
            return total
        }
        let indexes: [Int] = pixels.map { pixel in
            palette.indices.min { left, right in
                distance(pixel, palette[left]) < distance(pixel, palette[right])
            } ?? 0
        }
        var rows = [UInt8]()
        for y in 0..<height {
            rows.append(0) // PNG row filter: none.
            for x in stride(from: 0, to: width, by: 2) {
                let high = indexes[y * width + x]
                let low = x + 1 < width ? indexes[y * width + x + 1] : 0
                rows.append(UInt8(high << 4 | low))
            }
        }
        var size = compressBound(uLong(rows.count))
        var compressed = [UInt8](repeating: 0, count: Int(size))
        guard compress2(&compressed, &size, rows, uLong(rows.count), Z_BEST_COMPRESSION) == Z_OK else { return nil }
        func word(_ number: UInt32) -> Data {
            Data([UInt8(truncatingIfNeeded: number >> 24), UInt8(truncatingIfNeeded: number >> 16),
                  UInt8(truncatingIfNeeded: number >> 8), UInt8(truncatingIfNeeded: number)])
        }
        func chunk(_ type: String, _ data: Data) -> Data {
            let body = Data(type.utf8) + data
            let checksum = body.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(body.count)) }
            return word(UInt32(data.count)) + body + word(UInt32(checksum))
        }
        return Data([137, 80, 78, 71, 13, 10, 26, 10])
            + chunk("IHDR", word(UInt32(width)) + word(UInt32(height)) + Data([4, 3, 0, 0, 0]))
            + chunk("PLTE", Data(palette.flatMap { $0.map(UInt8.init) }))
            + chunk("IDAT", Data(compressed.prefix(Int(size))))
            + chunk("IEND", Data())
    }
}
