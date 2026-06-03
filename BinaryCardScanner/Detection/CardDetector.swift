import CoreGraphics
import Foundation

enum CardDetector {

    static let darkThreshold: UInt8 = 80
    static let columnDarkRatioMin: Double = 0.15
    static let longBarRatio: Double = 0.60
    static let shortBarRatio: Double = 0.35

    // MARK: - Public API

    /// Analyse a grayscale CGImage (the cropped guide-zone frame).
    /// Returns decimal values for each detected card, ordered top-to-bottom.
    static func detect(in image: CGImage) -> [Int] {
        let columns = findBarColumns(in: image)
        guard columns.count == 6 else { return [] }

        let cardRows = findCardRows(in: image, referenceColumn: columns[0])
        guard !cardRows.isEmpty else { return [] }

        return cardRows.compactMap { row in
            readBits(in: image, cardRow: row, barColumns: columns)
        }
    }

    // MARK: - Step 1: Find 6 bar column centers

    static func findBarColumns(in image: CGImage) -> [Int] {
        let width = image.width
        var candidateXs: [Int] = []
        for x in 0..<width {
            let ratio = image.darkRatioInColumn(x: x, threshold: darkThreshold)
            if ratio >= columnDarkRatioMin {
                candidateXs.append(x)
            }
        }
        let clusters = groupConsecutive(candidateXs)
        return clusters.map { cluster in cluster.reduce(0, +) / cluster.count }
    }

    // MARK: - Step 2: Find card row boundaries

    /// Scans ALL 6 bar columns, clusters their dark-segment Y-centers to count
    /// cards, then returns equal-height horizontal bands (one per card).
    /// This is robust even when all bars are short (bit = 0) because the
    /// denominator in readBits is always the full card height, not the bar height.
    static func findCardRows(in image: CGImage,
                              referenceColumn col: Int) -> [Range<Int>] {
        let allColumns = findBarColumns(in: image)
        guard !allColumns.isEmpty else { return [] }

        let minLen = max(2, image.height / 60)
        var centers: [Int] = []
        for x in allColumns {
            let segs = image.darkSegmentsInColumn(x: x,
                                                   threshold: darkThreshold,
                                                   minLength: minLen)
            centers += segs.map { ($0.lowerBound + $0.upperBound) / 2 }
        }
        guard !centers.isEmpty else { return [] }

        // Cluster by Y proximity: same-card segments across 6 columns will
        // have nearly identical centers; different cards are cardHeight apart.
        centers.sort()
        let proximityThreshold = max(5, image.height / 10)
        var clusters: [[Int]] = [[centers[0]]]
        for c in centers.dropFirst() {
            if abs(c - clusters[clusters.count - 1].last!) <= proximityThreshold {
                clusters[clusters.count - 1].append(c)
            } else {
                clusters.append([c])
            }
        }

        // Divide image into numCards equal-height bands (top-to-bottom).
        let numCards = clusters.count
        let cardHeight = image.height / numCards
        return (0..<numCards).map { i in
            let yStart = i * cardHeight
            let yEnd = (i == numCards - 1) ? image.height : (i + 1) * cardHeight
            return yStart..<yEnd
        }
    }

    // MARK: - Step 3: Read 6 bits from a card row

    static func readBits(in image: CGImage,
                          cardRow: Range<Int>,
                          barColumns: [Int]) -> Int? {
        let bandHeight = cardRow.count
        guard bandHeight > 0 else { return nil }

        var bits = [Int]()
        for col in barColumns {
            let barHeight = darkHeightInRowRange(image: image,
                                                 x: col,
                                                 yRange: cardRow)
            let ratio = Double(barHeight) / Double(bandHeight)
            if ratio > longBarRatio {
                bits.append(1)
            } else if ratio < shortBarRatio {
                bits.append(0)
            } else {
                return nil  // ambiguous
            }
        }
        // MSB first (leftmost column = bit5)
        return bits.enumerated().reduce(0) { acc, pair in
            acc | (pair.element << (5 - pair.offset))
        }
    }

    // MARK: - Private helpers

    private static func darkHeightInRowRange(image: CGImage,
                                              x: Int,
                                              yRange: Range<Int>) -> Int {
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0 }
        let bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        var maxLen = 0, curLen = 0
        for y in yRange {
            let lum = ptr[y * bpr + x * bpp]
            if lum < darkThreshold {
                curLen += 1
                maxLen = max(maxLen, curLen)
            } else {
                curLen = 0
            }
        }
        return maxLen
    }

    private static func groupConsecutive(_ values: [Int]) -> [[Int]] {
        guard !values.isEmpty else { return [] }
        var groups: [[Int]] = [[values[0]]]
        for v in values.dropFirst() {
            if v == groups[groups.count - 1].last! + 1 {
                groups[groups.count - 1].append(v)
            } else {
                groups.append([v])
            }
        }
        return groups
    }
}
