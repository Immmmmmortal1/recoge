import XCTest
@testable import BinaryCardScanner

final class CardDetectorTests: XCTestCase {

    // MARK: - Helpers

    func solidGrayImage(width: Int, height: Int, gray: UInt8) -> CGImage {
        var pixels = [UInt8](repeating: gray, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: &pixels,
                            width: width, height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: width,
                            space: colorSpace,
                            bitmapInfo: 0)!
        return ctx.makeImage()!
    }

    func imageWithDarkBar(width: Int, height: Int,
                          barX: ClosedRange<Int>, barHeight: Int) -> CGImage {
        var pixels = [UInt8](repeating: 220, count: width * height)
        let barTop = (height - barHeight) / 2
        for y in barTop..<(barTop + barHeight) {
            for x in barX {
                guard x < width else { continue }
                pixels[y * width + x] = 30
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: &pixels,
                            width: width, height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: width,
                            space: colorSpace,
                            bitmapInfo: 0)!
        return ctx.makeImage()!
    }

    // MARK: - darkRatioInColumn

    func test_darkRatioInColumn_allDark() {
        let img = solidGrayImage(width: 10, height: 100, gray: 30)
        let ratio = img.darkRatioInColumn(x: 5, threshold: 80)
        XCTAssertEqual(ratio, 1.0, accuracy: 0.01)
    }

    func test_darkRatioInColumn_allLight() {
        let img = solidGrayImage(width: 10, height: 100, gray: 220)
        let ratio = img.darkRatioInColumn(x: 5, threshold: 80)
        XCTAssertEqual(ratio, 0.0, accuracy: 0.01)
    }

    func test_darkRatioInColumn_halfDark() {
        // Top half dark, bottom half light
        let width = 10, height = 100
        var pixels = [UInt8](repeating: 220, count: width * height)
        for y in 0..<50 {
            for x in 0..<width {
                pixels[y * width + x] = 30
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: &pixels, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width,
                            space: colorSpace, bitmapInfo: 0)!
        let img = ctx.makeImage()!
        let ratio = img.darkRatioInColumn(x: 5, threshold: 80)
        XCTAssertEqual(ratio, 0.5, accuracy: 0.02)
    }

    func test_darkRatioInColumn_outOfBounds_returnsZero() {
        let img = solidGrayImage(width: 10, height: 100, gray: 30)
        let ratio = img.darkRatioInColumn(x: 100, threshold: 80)
        XCTAssertEqual(ratio, 0.0)
    }

    // MARK: - longestDarkSegmentInColumn

    func test_longestDarkSegment_returnsBarHeight() {
        let img = imageWithDarkBar(width: 10, height: 100, barX: 3...6, barHeight: 40)
        let segLen = img.longestDarkSegmentInColumn(x: 5, threshold: 80)
        XCTAssertEqual(segLen, 40)
    }

    func test_longestDarkSegment_allLight_returnsZero() {
        let img = solidGrayImage(width: 10, height: 100, gray: 220)
        let segLen = img.longestDarkSegmentInColumn(x: 5, threshold: 80)
        XCTAssertEqual(segLen, 0)
    }

    func test_longestDarkSegment_picksBigger_ofTwoSegments() {
        // Two separate bars: heights 20 and 40
        let width = 10, height = 100
        var pixels = [UInt8](repeating: 220, count: width * height)
        // Bar 1: rows 5–24 (height 20)
        for y in 5..<25 { for x in 0..<width { pixels[y * width + x] = 30 } }
        // Bar 2: rows 50–89 (height 40)
        for y in 50..<90 { for x in 0..<width { pixels[y * width + x] = 30 } }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: &pixels, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width,
                            space: colorSpace, bitmapInfo: 0)!
        let img = ctx.makeImage()!
        let segLen = img.longestDarkSegmentInColumn(x: 5, threshold: 80)
        XCTAssertEqual(segLen, 40)
    }

    // MARK: - darkSegmentsInColumn

    func test_darkSegments_twoSegments() {
        let width = 10, height = 100
        var pixels = [UInt8](repeating: 220, count: width * height)
        // Seg 1: rows 10–29
        for y in 10..<30 { for x in 0..<width { pixels[y * width + x] = 30 } }
        // Seg 2: rows 60–79
        for y in 60..<80 { for x in 0..<width { pixels[y * width + x] = 30 } }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: &pixels, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width,
                            space: colorSpace, bitmapInfo: 0)!
        let img = ctx.makeImage()!
        let segs = img.darkSegmentsInColumn(x: 5, threshold: 80, minLength: 3)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0], 10..<30)
        XCTAssertEqual(segs[1], 60..<80)
    }

    func test_darkSegments_noiseTooShort_filtered() {
        let width = 10, height = 100
        var pixels = [UInt8](repeating: 220, count: width * height)
        // Only 2 dark pixels — below minLength=3
        pixels[50 * width + 5] = 30
        pixels[51 * width + 5] = 30
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: &pixels, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width,
                            space: colorSpace, bitmapInfo: 0)!
        let img = ctx.makeImage()!
        let segs = img.darkSegmentsInColumn(x: 5, threshold: 80, minLength: 3)
        XCTAssertEqual(segs.count, 0)
    }

    // MARK: - Synthetic image builder (used by CardDetector tests)

    func makeSyntheticCardImage(cardBinaries: [[Int]],
                                cardHeight: Int = 30,
                                barWidth: Int = 6,
                                imageWidth: Int = 120) -> CGImage {
        let numCards = cardBinaries.count
        let height = numCards * cardHeight
        var pixels = [UInt8](repeating: 220, count: imageWidth * height)

        let numBars = 6
        // Bar centers at 1/12, 3/12, 5/12, 7/12, 9/12, 11/12 of imageWidth
        let barCenters = (0..<numBars).map { i in
            imageWidth * (2 * i + 1) / (numBars * 2)
        }

        for (cardIdx, bits) in cardBinaries.enumerated() {
            let yTop = cardIdx * cardHeight
            let longH = Int(Double(cardHeight) * 0.75)
            let shortH = Int(Double(cardHeight) * 0.20)
            for (bitIdx, bit) in bits.enumerated() {
                let cx = barCenters[bitIdx]
                let barH = bit == 1 ? longH : shortH
                let yBarTop = yTop + (cardHeight - barH) / 2
                for y in yBarTop..<(yBarTop + barH) {
                    for dx in -(barWidth/2)..<(barWidth/2) {
                        let x = cx + dx
                        guard x >= 0, x < imageWidth else { continue }
                        pixels[y * imageWidth + x] = 25
                    }
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: &pixels,
                            width: imageWidth, height: height,
                            bitsPerComponent: 8, bytesPerRow: imageWidth,
                            space: colorSpace, bitmapInfo: 0)!
        return ctx.makeImage()!
    }

    // MARK: - findBarColumns

    func test_findBarColumns_finds6Columns() {
        // Single-card image with 6 full-height bars
        let width = 120, height = 30
        var pixels = [UInt8](repeating: 220, count: width * height)
        let barCenters = (0..<6).map { i in width * (2 * i + 1) / 12 }
        for cx in barCenters {
            for x in max(0, cx-3)..<min(width, cx+3) {
                for y in 0..<height { pixels[y * width + x] = 25 }
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: &pixels, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width,
                            space: colorSpace, bitmapInfo: 0)!
        let img = ctx.makeImage()!

        let cols = CardDetector.findBarColumns(in: img)
        XCTAssertEqual(cols.count, 6)
        for (idx, expected) in barCenters.enumerated() {
            XCTAssertEqual(cols[idx], expected, accuracy: 4)
        }
    }

    // MARK: - detect (end-to-end)

    func test_detect_singleCard_knownValue() {
        // 101010 = 42
        let img = makeSyntheticCardImage(cardBinaries: [[1,0,1,0,1,0]])
        let results = CardDetector.detect(in: img)
        XCTAssertEqual(results, [42])
    }

    func test_detect_singleCard_allZeros() {
        // 000000 = 0
        let img = makeSyntheticCardImage(cardBinaries: [[0,0,0,0,0,0]])
        let results = CardDetector.detect(in: img)
        XCTAssertEqual(results, [0])
    }

    func test_detect_singleCard_allOnes() {
        // 111111 = 63
        let img = makeSyntheticCardImage(cardBinaries: [[1,1,1,1,1,1]])
        let results = CardDetector.detect(in: img)
        XCTAssertEqual(results, [63])
    }

    func test_detect_threeCards() {
        // Card 0: 010011 = 19
        // Card 1: 000001 = 1
        // Card 2: 111111 = 63
        let img = makeSyntheticCardImage(cardBinaries: [
            [0,1,0,0,1,1],
            [0,0,0,0,0,1],
            [1,1,1,1,1,1]
        ])
        let results = CardDetector.detect(in: img)
        XCTAssertEqual(results, [19, 1, 63])
    }

    func test_detect_emptyImage_returnsEmpty() {
        // All-light image — no bars → no columns → empty
        let img = solidGrayImage(width: 120, height: 90, gray: 220)
        let results = CardDetector.detect(in: img)
        XCTAssertEqual(results, [])
    }
}
