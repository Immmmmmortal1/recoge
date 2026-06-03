import CoreGraphics
import Foundation

extension CGImage {

    /// Ratio of pixels in column `x` with luminance < `threshold` (0–255).
    func darkRatioInColumn(x: Int, threshold: UInt8 = 80) -> Double {
        guard x >= 0, x < width else { return 0 }
        guard let data = dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0 }

        let bpr = bytesPerRow
        let bpp = bitsPerPixel / 8
        var darkCount = 0
        for y in 0..<height {
            let offset = y * bpr + x * bpp
            let lum = ptr[offset]
            if lum < threshold { darkCount += 1 }
        }
        return Double(darkCount) / Double(height)
    }

    /// Length (in pixels) of the longest consecutive dark segment in column `x`.
    func longestDarkSegmentInColumn(x: Int, threshold: UInt8 = 80) -> Int {
        guard x >= 0, x < width else { return 0 }
        guard let data = dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0 }

        let bpr = bytesPerRow
        let bpp = bitsPerPixel / 8
        var maxLen = 0, curLen = 0
        for y in 0..<height {
            let offset = y * bpr + x * bpp
            let lum = ptr[offset]
            if lum < threshold {
                curLen += 1
                maxLen = max(maxLen, curLen)
            } else {
                curLen = 0
            }
        }
        return maxLen
    }

    /// All dark segments in column `x` as y-ranges, filtered by `minLength`.
    func darkSegmentsInColumn(x: Int, threshold: UInt8 = 80,
                               minLength: Int = 3) -> [Range<Int>] {
        guard x >= 0, x < width else { return [] }
        guard let data = dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return [] }

        let bpr = bytesPerRow
        let bpp = bitsPerPixel / 8
        var segments: [Range<Int>] = []
        var segStart: Int? = nil

        for y in 0..<height {
            let offset = y * bpr + x * bpp
            let isDark = ptr[offset] < threshold
            if isDark, segStart == nil {
                segStart = y
            } else if !isDark, let start = segStart {
                if y - start >= minLength {
                    segments.append(start..<y)
                }
                segStart = nil
            }
        }
        if let start = segStart, height - start >= minLength {
            segments.append(start..<height)
        }
        return segments
    }
}
