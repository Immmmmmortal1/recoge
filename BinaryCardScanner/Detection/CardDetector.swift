import CoreGraphics
import Foundation

enum CardDetector {

    static let darkThreshold: UInt8 = 80
    static let columnDarkRatioMin: Double = 0.08
    static let longBarRatio: Double = 0.60
    static let shortBarRatio: Double = 0.35
    /// Bits encoded vertically along each card's blue side strip (top = MSB, long bar = 1).
    static let bitsPerCard = 6

    enum ScanFailure: Equatable {
        case noFrame
        case notCardScene
        case noBarColumns
        case irregularColumns
        case noCardRows
        case ambiguousPattern
    }

    struct ScanOutcome: Equatable {
        /// One decoded value per card (per blue column), in left-to-right order.
        let cards: [Int]
        let failure: ScanFailure?
        let userMessage: String

        /// Distinct card identities (how many kinds of cards are in frame).
        var kinds: [Int] {
            var seen = Set<Int>()
            return cards.filter { seen.insert($0).inserted }
        }

        static func success(_ cards: [Int]) -> ScanOutcome {
            var seen = Set<Int>()
            let kindCount = cards.filter { seen.insert($0).inserted }.count
            return ScanOutcome(
                cards: cards,
                failure: nil,
                userMessage: "识别到 \(cards.count) 张卡片，共 \(kindCount) 种"
            )
        }

        static func failure(_ reason: ScanFailure) -> ScanOutcome {
            ScanOutcome(cards: [], failure: reason, userMessage: message(for: reason))
        }

        private static func message(for reason: ScanFailure) -> String {
            switch reason {
            case .noFrame:
                return "无法获取图像"
            case .notCardScene:
                return "请将卡片蓝色条码区对准黄框"
            case .noBarColumns, .irregularColumns:
                return "未识别到 6 条竖条码，请对准卡片侧边"
            case .noCardRows:
                return "未检测到卡片层，请调整距离"
            case .ambiguousPattern:
                return "条码不清晰，请保持稳定后重试"
            }
        }
    }

    // MARK: - Public API

    static func scan(colorFrame: CGImage?, grayFrame: CGImage?) -> ScanOutcome {
        guard let grayFrame else { return .failure(.noFrame) }
        guard let cards = detect(in: grayFrame, colorFrame: colorFrame), !cards.isEmpty else {
            return .failure(.noBarColumns)
        }
        return .success(cards)
    }

    /// Each blue strip is one card. Decode its `bitsPerCard` long/short pills (top = MSB, long = 1).
    /// Returns one value per strip, left-to-right.
    ///
    /// Color frames are decoded by tracing each strip along its actual (possibly tilted) direction,
    /// using the cyan strip background that stays continuous even when the card is held at an angle.
    /// Gray-only frames fall back to straight vertical decoding.
    static func detect(in image: CGImage, colorFrame: CGImage? = nil) -> [Int]? {
        // Primary path: vertical column decode on the guide crop (matches design spec).
        if let values = detectGray(image), !values.isEmpty {
            return values
        }
        // Fallback when gray fails: trace tilted cyan strips on the color frame.
        if let colorFrame, let bmp = Bitmap(colorFrame), bmp.bpp >= 3 {
            return detectColor(bmp)
        }
        return nil
    }

    private static func detectGray(_ image: CGImage) -> [Int]? {
        guard let columns = findBarColumns(in: image) else { return nil }
        var values: [Int] = []
        for x in columns {
            guard let value = readColumnValue(in: image, columnX: x) else { return nil }
            values.append(value)
        }
        return values.isEmpty ? nil : values
    }

    // MARK: - Tilt-robust color pipeline

    /// Direct pixel access. Handles 1-channel gray and BGRA color buffers.
    struct Bitmap {
        let ptr: UnsafePointer<UInt8>
        let data: CFData
        let bpr: Int
        let bpp: Int
        let w: Int
        let h: Int

        init?(_ image: CGImage) {
            guard let provider = image.dataProvider,
                  let data = provider.data,
                  let ptr = CFDataGetBytePtr(data) else { return nil }
            self.data = data
            self.ptr = ptr
            self.bpr = image.bytesPerRow
            self.bpp = max(1, image.bitsPerPixel / 8)
            self.w = image.width
            self.h = image.height
        }

        @inline(__always) func lum(_ x: Int, _ y: Int) -> Int {
            let o = y * bpr + x * bpp
            if bpp == 1 { return Int(ptr[o]) }
            let b = Int(ptr[o]), g = Int(ptr[o + 1]), r = Int(ptr[o + 2])
            return (77 * r + 150 * g + 29 * b) >> 8
        }

        @inline(__always) func isCyan(_ x: Int, _ y: Int) -> Bool {
            guard bpp >= 3 else { return false }
            let o = y * bpr + x * bpp
            let b = Int(ptr[o]), r = Int(ptr[o + 2])
            return b > r + 25
        }

        @inline(__always) func isDark(_ x: Int, _ y: Int) -> Bool {
            lum(x, y) < 90
        }

        /// A strip pixel: either a dark pill or the cyan strip background (i.e. not white paper).
        @inline(__always) func isStrip(_ x: Int, _ y: Int) -> Bool {
            isDark(x, y) || isCyan(x, y)
        }
    }

    private struct StripSeed { let center: Int; let halfWidth: Int }

    private static func detectColor(_ bmp: Bitmap) -> [Int]? {
        let seeds = findStripSeeds(bmp)
        guard !seeds.isEmpty, seeds.count <= 40 else { return nil }

        var values: [Int] = []
        for seed in seeds {
            let points = traceStrip(bmp, seed: seed)
            guard let value = decodeTrace(bmp, points: points) else { return nil }
            values.append(value)
        }
        return values.isEmpty ? nil : values
    }

    /// Strips are found in a thin horizontal band at mid-height. Tilt drift across a thin band is
    /// negligible, and a color strip is "non-paper" at every row (pill or cyan), so strips separate cleanly.
    private static func findStripSeeds(_ bmp: Bitmap) -> [StripSeed] {
        let yc = bmp.h / 2
        let bandHalf = max(2, bmp.h / 50)
        let yLo = max(0, yc - bandHalf)
        let yHi = min(bmp.h - 1, yc + bandHalf)
        let bandRows = yHi - yLo + 1

        var counts = [Int](repeating: 0, count: bmp.w)
        for x in 0..<bmp.w {
            var c = 0
            for y in yLo...yHi where bmp.isStrip(x, y) { c += 1 }
            counts[x] = c
        }
        counts = smooth(counts, radius: max(1, bmp.w / 80))

        let minCount = max(2, bandRows / 2)
        var seeds: [StripSeed] = []
        var runStart: Int? = nil
        for x in 0..<bmp.w {
            if counts[x] >= minCount {
                if runStart == nil { runStart = x }
            } else if let s = runStart {
                seeds.append(StripSeed(center: (s + x - 1) / 2, halfWidth: max(2, (x - 1 - s) / 2)))
                runStart = nil
            }
        }
        if let s = runStart {
            seeds.append(StripSeed(center: (s + bmp.w - 1) / 2, halfWidth: max(2, (bmp.w - 1 - s) / 2)))
        }
        return seeds
    }

    /// Follows a strip up and down from its mid-height seed, recentring on the strip at every row.
    private static func traceStrip(_ bmp: Bitmap, seed: StripSeed) -> [(y: Int, x: Int)] {
        let win = seed.halfWidth + max(3, bmp.w / 40)
        var points: [(y: Int, x: Int)] = []

        func walk(from yStart: Int, step: Int) {
            var x = seed.center
            var miss = 0
            var y = yStart
            while y >= 0 && y < bmp.h {
                if let cx = stripCentroid(bmp, y: y, x: x, win: win) {
                    x = cx
                    points.append((y, x))
                    miss = 0
                } else {
                    miss += 1
                    if miss > 5 { break }
                }
                y += step
            }
        }
        walk(from: bmp.h / 2, step: -1)
        walk(from: bmp.h / 2 + 1, step: 1)
        return points.sorted { $0.y < $1.y }
    }

    private static func stripCentroid(_ bmp: Bitmap, y: Int, x: Int, win: Int) -> Int? {
        let lo = max(0, x - win)
        let hi = min(bmp.w - 1, x + win)
        guard lo <= hi else { return nil }
        var sum = 0, count = 0
        for xi in lo...hi where bmp.isStrip(xi, y) {
            sum += xi
            count += 1
        }
        return count >= max(2, win / 2) ? sum / count : nil
    }

    /// 1D barcode style: find dark pill segments along the strip, then classify long vs short by height.
    private static func decodeTrace(_ bmp: Bitmap, points: [(y: Int, x: Int)]) -> Int? {
        guard points.count >= bitsPerCard * 2 else { return nil }

        let darks = points.map { darkMajority(bmp, x: $0.x, y: $0.y) }
        let noiseLen = max(2, points.count / 40)
        let mergeGap = max(1, points.count / 150)

        var segs: [(lo: Int, hi: Int)] = []
        var start: Int? = nil
        for i in 0..<darks.count {
            if darks[i] {
                if start == nil { start = i }
            } else if let s = start {
                if i - s >= noiseLen { segs.append((s, i - 1)) }
                start = nil
            }
        }
        if let s = start, darks.count - s >= noiseLen { segs.append((s, darks.count - 1)) }

        var merged: [(lo: Int, hi: Int)] = []
        for seg in segs {
            if let last = merged.last, seg.lo - last.hi <= mergeGap {
                merged[merged.count - 1] = (last.lo, seg.hi)
            } else {
                merged.append(seg)
            }
        }
        guard !merged.isEmpty else { return nil }

        let bits: [Int]
        if merged.count == bitsPerCard {
            bits = classifyPillLengths(merged)
        } else {
            bits = sampleTraceSlots(darks: darks, segments: merged)
            guard bits.count == bitsPerCard else { return nil }
        }

        return bits.enumerated().reduce(0) { acc, pair in
            acc | (pair.element << (bitsPerCard - 1 - pair.offset))
        }
    }

    /// Standard 1D decode: split pill band into equal slots; long pill fills ≥60% of slot (design spec).
    private static func sampleTraceSlots(darks: [Bool], segments: [(lo: Int, hi: Int)]) -> [Int] {
        guard let top = segments.first?.lo, let bottom = segments.last?.hi, bottom > top else { return [] }
        let span = bottom - top + 1
        guard span >= bitsPerCard else { return [] }
        let slot = Double(span) / Double(bitsPerCard)
        var bits: [Int] = []
        for i in 0..<bitsPerCard {
            let sLo = top + Int(Double(i) * slot)
            let sHi = min(bottom, top + Int(Double(i + 1) * slot) - 1)
            guard sHi >= sLo else { return [] }
            let darkCount = (sLo...sHi).reduce(0) { $0 + (darks[$1] ? 1 : 0) }
            bits.append(Double(darkCount) >= slot * longBarRatio ? 1 : 0)
        }
        return bits
    }

    /// Classifies exactly `bitsPerCard` pills as long(1)/short(0) by segment height clusters.
    private static func classifyPillLengths(_ segs: [(lo: Int, hi: Int)]) -> [Int] {
        let lengths = segs.map { $0.hi - $0.lo + 1 }
        let sorted = lengths.sorted()
        var bestGap = 0
        var splitValue = 0
        for i in 1..<sorted.count {
            let gap = sorted[i] - sorted[i - 1]
            if gap > bestGap {
                bestGap = gap
                splitValue = (sorted[i] + sorted[i - 1]) / 2
            }
        }
        let range = sorted.last! - sorted.first!
        if range > 0, bestGap >= max(8, Int(Double(range) * 0.35)) {
            return lengths.map { $0 >= splitValue ? 1 : 0 }
        }
        let avg = Double(lengths.reduce(0, +)) / Double(lengths.count)
        let centers = segs.map { ($0.lo + $0.hi) / 2 }
        let pitch = Double(centers.last! - centers.first!) / Double(max(1, segs.count - 1))
        let allLong = avg >= pitch * 0.65
        return lengths.map { _ in allLong ? 1 : 0 }
    }

    private static func darkMajority(_ bmp: Bitmap, x: Int, y: Int) -> Bool {
        let lo = max(0, x - 2)
        let hi = min(bmp.w - 1, x + 2)
        var dark = 0, total = 0
        for xi in lo...hi {
            total += 1
            if bmp.isDark(xi, y) { dark += 1 }
        }
        return total > 0 && dark * 2 >= total
    }

    // MARK: - Step 1: Find the card columns (one blue strip per card)

    /// Locates every card column. Count is variable: each evenly-spaced blue strip is one card.
    static func findBarColumns(in image: CGImage, colorFrame: CGImage? = nil) -> [Int]? {
        var candidates: [[Int]] = []
        if let colorFrame {
            candidates.append(findColumnPeaks(in: columnBlueScores(in: colorFrame), imageWidth: image.width))
        }
        candidates.append(findColumnPeaks(in: columnDarkCounts(in: image, threshold: darkThreshold),
                                          imageWidth: image.width))

        for cols in candidates where !cols.isEmpty {
            if columnsAreValid(cols, image: image) {
                return cols
            }
        }
        return nil
    }

    /// Variable-count column finder: each contiguous run above threshold is one column (its centroid).
    /// Run-based (not local-maxima) so a wide, flat-topped bar yields exactly one column, not several.
    private static func findColumnPeaks(in profile: [Int], imageWidth: Int) -> [Int] {
        guard profile.count >= 3, let maxVal = profile.max(), maxVal > 0 else { return [] }
        let minValue = max(2, maxVal * 3 / 10)

        var runs: [(lo: Int, hi: Int)] = []
        var start: Int? = nil
        for x in 0..<profile.count {
            if profile[x] >= minValue {
                if start == nil { start = x }
            } else if let s = start {
                runs.append((s, x - 1))
                start = nil
            }
        }
        if let s = start { runs.append((s, profile.count - 1)) }

        let centers = runs.map { ($0.lo + $0.hi) / 2 }
        let minDistance = max(3, imageWidth / 60)
        var merged: [Int] = []
        for c in centers.sorted() {
            if let last = merged.last, c - last < minDistance {
                merged[merged.count - 1] = (last + c) / 2
            } else {
                merged.append(c)
            }
        }
        return merged
    }

    private static func columnDarkCounts(in image: CGImage, threshold: UInt8) -> [Int] {
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return [] }
        let bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        var counts = [Int](repeating: 0, count: image.width)
        for x in 0..<image.width {
            for y in 0..<image.height {
                if ptr[y * bpr + x * bpp] < threshold {
                    counts[x] += 1
                }
            }
        }
        return smooth(counts, radius: max(1, image.width / 60))
    }

    private static func columnBlueScores(in image: CGImage) -> [Int] {
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return [] }
        let bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        var scores = [Int](repeating: 0, count: image.width)
        for x in 0..<image.width {
            var sum = 0
            for y in 0..<image.height {
                let o = y * bpr + x * bpp
                let b = Int(ptr[o])
                let g = Int(ptr[o + 1])
                let r = Int(ptr[o + 2])
                sum += max(0, b - max(r, g))
            }
            scores[x] = sum
        }
        return smooth(scores, radius: max(1, image.width / 50))
    }

    private static func smooth(_ values: [Int], radius: Int) -> [Int] {
        guard !values.isEmpty else { return [] }
        return values.indices.map { i in
            let lo = max(0, i - radius)
            let hi = min(values.count - 1, i + radius)
            let slice = values[lo...hi]
            return slice.reduce(0, +) / slice.count
        }
    }

    private static func columnStrength(image: CGImage, centerX: Int) -> Double {
        var sum = 0.0
        var n = 0.0
        for dx in -2...2 {
            let x = centerX + dx
            guard x >= 0, x < image.width else { continue }
            sum += image.darkRatioInColumn(x: x, threshold: darkThreshold)
            n += 1
        }
        return n > 0 ? sum / n : 0
    }

    /// Accepts any column count >= 1: spacing must be roughly uniform and each column must hold real pills.
    private static func columnsAreValid(_ columns: [Int], image: CGImage) -> Bool {
        guard !columns.isEmpty else { return false }

        if columns.count >= 2 {
            let spacings = zip(columns, columns.dropFirst()).map { $1 - $0 }
            guard let minSpace = spacings.min(), let maxSpace = spacings.max(), minSpace > 2 else {
                return false
            }
            if Double(maxSpace) > Double(minSpace) * 3.5 {
                return false
            }
        }

        let minSegLen = max(2, image.height / 150)
        for col in columns {
            if columnStrength(image: image, centerX: col) < columnDarkRatioMin {
                return false
            }
            // A real card column is a sequence of pills, not a single blob or stray line.
            if image.darkSegmentsInColumn(x: col, threshold: darkThreshold, minLength: minSegLen).count < 2 {
                return false
            }
        }
        return true
    }

    // MARK: - Step 2: Decode one card (one column) vertically

    /// Reads `bitsPerCard` long/short pills down a single blue column.
    /// Top pill is the most significant bit; a long pill is 1, a short pill is 0.
    static func readColumnValue(in image: CGImage, columnX x: Int) -> Int? {
        let bits = decodeColumnBits(in: image, columnX: x)
        guard bits.count == bitsPerCard else { return nil }
        return bits.enumerated().reduce(0) { acc, pair in
            acc | (pair.element << (bitsPerCard - 1 - pair.offset))
        }
    }

    /// Returns the per-bit long(1)/short(0) sequence top-to-bottom, or [] if the column is unreadable.
    static func decodeColumnBits(in image: CGImage, columnX x: Int) -> [Int] {
        let minLen = max(2, image.height / 150)
        let raw = image.darkSegmentsInColumn(x: x, threshold: darkThreshold, minLength: minLen)
        let segs = mergeCloseSegments(raw, maxGap: max(2, image.height / 150))

        if segs.count == bitsPerCard {
            let pillSegs = segs.map { (lo: $0.lowerBound, hi: $0.upperBound - 1) }
            return classifyPillLengths(pillSegs)
        }

        // Fallback: divide the pill band into equal slots and sample dark fill per slot.
        return sampleColumnSlots(in: image, columnX: x, segments: segs)
    }

    private static func sampleColumnSlots(in image: CGImage,
                                          columnX x: Int,
                                          segments: [Range<Int>]) -> [Int] {
        guard let first = segments.first, let last = segments.last else { return [] }
        let top = first.lowerBound
        let bottom = last.upperBound
        let span = bottom - top
        guard span > bitsPerCard else { return [] }

        let slot = Double(span) / Double(bitsPerCard)
        var bits: [Int] = []
        for i in 0..<bitsPerCard {
            let yStart = top + Int(Double(i) * slot)
            let yEnd = min(image.height, top + Int(Double(i + 1) * slot))
            guard yEnd > yStart else { return [] }
            let darkH = darkHeightInRowRange(image: image, x: x, yRange: yStart..<yEnd)
            bits.append(Double(darkH) >= slot * 0.5 ? 1 : 0)
        }
        return bits
    }

    /// Bridges sub-pixel splits in a single pill so each bit slot stays one segment.
    private static func mergeCloseSegments(_ segments: [Range<Int>], maxGap: Int) -> [Range<Int>] {
        guard let first = segments.first else { return [] }
        var merged: [Range<Int>] = [first]
        for seg in segments.dropFirst() {
            let last = merged[merged.count - 1]
            if seg.lowerBound - last.upperBound <= maxGap {
                merged[merged.count - 1] = last.lowerBound..<seg.upperBound
            } else {
                merged.append(seg)
            }
        }
        return merged
    }

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
}
