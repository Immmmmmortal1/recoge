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

    // MARK: - Synthetic image builder (vertical-column card model)

    /// Builds an image where each card is one vertical column of `bitsPerCard` long/short pills.
    /// `cards[i]` is that column's bits, top-to-bottom, MSB first (1 = long pill, 0 = short pill).
    func makeSyntheticColumnImage(cards: [[Int]],
                                  imageHeight: Int = 240,
                                  columnPitch: Int = 28,
                                  barWidth: Int = 10,
                                  sideMargin: Int = 16) -> CGImage {
        let numCards = max(1, cards.count)
        let width = sideMargin * 2 + numCards * columnPitch
        var pixels = [UInt8](repeating: 220, count: width * imageHeight)

        let slotH = imageHeight / CardDetector.bitsPerCard
        let longLen = Int(Double(slotH) * 0.72)
        let shortLen = Int(Double(slotH) * 0.30)

        for (cardIdx, bits) in cards.enumerated() {
            let cx = sideMargin + cardIdx * columnPitch + columnPitch / 2
            for (bitIdx, bit) in bits.enumerated() {
                let slotTop = bitIdx * slotH
                let barLen = bit == 1 ? longLen : shortLen
                let yTop = slotTop + (slotH - barLen) / 2
                for y in yTop..<(yTop + barLen) {
                    for dx in -(barWidth / 2)..<(barWidth / 2) {
                        let x = cx + dx
                        guard x >= 0, x < width, y >= 0, y < imageHeight else { continue }
                        pixels[y * width + x] = 25
                    }
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: &pixels,
                            width: width, height: imageHeight,
                            bitsPerComponent: 8, bytesPerRow: width,
                            space: colorSpace, bitmapInfo: 0)!
        return ctx.makeImage()!
    }

    // MARK: - findBarColumns (variable count)

    func test_findBarColumns_findsAllColumns() {
        let img = makeSyntheticColumnImage(cards: [
            [1,0,1,0,1,0],
            [1,1,1,1,1,1],
            [0,0,0,0,0,0],
            [1,0,1,1,0,1]
        ])
        let cols = CardDetector.findBarColumns(in: img)!
        XCTAssertEqual(cols.count, 4)
        XCTAssertEqual(cols, cols.sorted())
    }

    // MARK: - decodeColumnBits

    func test_decodeColumnBits_topIsMSB_longIsOne() {
        let img = makeSyntheticColumnImage(cards: [[1,0,1,0,1,0]])
        let cols = CardDetector.findBarColumns(in: img)!
        let bits = CardDetector.decodeColumnBits(in: img, columnX: cols[0])
        XCTAssertEqual(bits, [1,0,1,0,1,0])
    }

    // MARK: - detect (end-to-end, one value per column)

    func test_detect_singleCard_knownValue() {
        // 101010 top-to-bottom = 42
        let img = makeSyntheticColumnImage(cards: [[1,0,1,0,1,0]])
        XCTAssertEqual(CardDetector.detect(in: img)!, [42])
    }

    func test_detect_singleCard_allZeros() {
        let img = makeSyntheticColumnImage(cards: [[0,0,0,0,0,0]])
        XCTAssertEqual(CardDetector.detect(in: img)!, [0])
    }

    func test_detect_singleCard_allOnes() {
        let img = makeSyntheticColumnImage(cards: [[1,1,1,1,1,1]])
        XCTAssertEqual(CardDetector.detect(in: img)!, [63])
    }

    func test_detect_multipleCards_leftToRight() {
        // 010011 = 19, 000001 = 1, 111111 = 63
        let img = makeSyntheticColumnImage(cards: [
            [0,1,0,0,1,1],
            [0,0,0,0,0,1],
            [1,1,1,1,1,1]
        ])
        XCTAssertEqual(CardDetector.detect(in: img)!, [19, 1, 63])
    }

    func test_detect_countsDistinctKinds() {
        // Three cards, two kinds: 42 appears twice, 21 once.
        let img = makeSyntheticColumnImage(cards: [
            [1,0,1,0,1,0], // 42
            [0,1,0,1,0,1], // 21
            [1,0,1,0,1,0]  // 42
        ])
        let outcome = CardDetector.scan(colorFrame: nil, grayFrame: img)
        XCTAssertEqual(outcome.cards, [42, 21, 42])
        XCTAssertEqual(outcome.kinds, [42, 21])
    }

    func test_detect_emptyImage_returnsNil() {
        let img = solidGrayImage(width: 160, height: 240, gray: 220)
        XCTAssertNil(CardDetector.detect(in: img))
    }

    // MARK: - Color builder (BGRA: cyan strips + dark pills, optionally tilted)

    /// Builds a BGRA image of cyan strips with dark long/short pills. `tilt` shifts each strip's x
    /// by `tilt` px per row, simulating a card held at an angle.
    func makeColorColumnImage(cards: [[Int]],
                              tilt: Double = 0,
                              imageHeight: Int = 360,
                              columnPitch: Int = 40,
                              barWidth: Int = 14,
                              sideMargin: Int = 30) -> CGImage {
        let numCards = max(1, cards.count)
        let width = sideMargin * 2 + numCards * columnPitch + Int(abs(tilt) * Double(imageHeight))
        var px = [UInt8](repeating: 0, count: width * imageHeight * 4)
        // Paper white everywhere.
        for i in 0..<(width * imageHeight) {
            px[i * 4 + 0] = 235; px[i * 4 + 1] = 235; px[i * 4 + 2] = 235; px[i * 4 + 3] = 255
        }
        func set(_ x: Int, _ y: Int, _ b: UInt8, _ g: UInt8, _ r: UInt8) {
            guard x >= 0, x < width, y >= 0, y < imageHeight else { return }
            let o = (y * width + x) * 4
            px[o] = b; px[o + 1] = g; px[o + 2] = r; px[o + 3] = 255
        }

        // Real printed cards: long pills nearly fill the slot, short pills ~half, gaps are small.
        let slotH = imageHeight / CardDetector.bitsPerCard
        let longLen = Int(Double(slotH) * 0.85)
        let shortLen = Int(Double(slotH) * 0.45)
        let baseX = sideMargin + Int(abs(tilt) * Double(imageHeight)) / 2

        for (cardIdx, bits) in cards.enumerated() {
            let cx0 = baseX + cardIdx * columnPitch + columnPitch / 2
            for y in 0..<imageHeight {
                let cx = cx0 + Int((Double(y) - Double(imageHeight) / 2) * tilt)
                // Strip background = cyan across the bar width.
                for dx in -(barWidth / 2)..<(barWidth / 2) { set(cx + dx, y, 230, 200, 70) }
                // Pill (dark) if this row is inside the slot's pill.
                let slot = y / slotH
                guard slot < CardDetector.bitsPerCard else { continue }
                let slotCenter = slot * slotH + slotH / 2
                let pillLen = bits[slot] == 1 ? longLen : shortLen
                if abs(y - slotCenter) <= pillLen / 2 {
                    for dx in -(barWidth / 2)..<(barWidth / 2) { set(cx + dx, y, 20, 20, 20) }
                }
            }
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let ctx = CGContext(data: &px, width: width, height: imageHeight,
                            bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: cs, bitmapInfo: info)!
        return ctx.makeImage()!
    }

    func test_detectColor_straightStrips() {
        let img = makeColorColumnImage(cards: [
            [1,0,1,1,0,0], // 44
            [0,0,1,1,1,0], // 14
            [1,0,0,0,0,1]  // 33
        ])
        XCTAssertEqual(CardDetector.detect(in: img, colorFrame: img), [44, 14, 33])
    }

    func test_detectColor_tiltedStrips() {
        // Same values, but the whole card is tilted (0.2 px x-shift per row ~ 11°).
        let img = makeColorColumnImage(cards: [
            [1,0,1,1,0,0], // 44
            [1,1,0,0,1,0], // 50
            [1,0,1,0,1,0]  // 42
        ], tilt: 0.2)
        XCTAssertEqual(CardDetector.detect(in: img, colorFrame: img), [44, 50, 42])
    }

    func test_detectColor_allLongAndAllShort() {
        // The device bug: small gaps made every pill merge/read as long (63). Lock both extremes.
        let img = makeColorColumnImage(cards: [
            [1,1,1,1,1,1], // 63 all long
            [0,0,0,0,0,0], // 0  all short
            [1,0,1,1,0,0]  // 44 mixed
        ])
        XCTAssertEqual(CardDetector.detect(in: img, colorFrame: img), [63, 0, 44])
    }

    func test_detectColor_sampleCardSixValues() {
        // The six values from the reference truth table, decoded from a tilted color frame.
        let img = makeColorColumnImage(cards: [
            [1,0,1,1,0,0], // 44
            [0,0,1,1,1,0], // 14
            [1,0,0,0,0,1], // 33
            [1,1,0,0,1,0], // 50
            [0,1,1,1,0,0], // 28
            [1,0,1,0,1,0]  // 42
        ], tilt: 0.12)
        XCTAssertEqual(CardDetector.detect(in: img, colorFrame: img), [44, 14, 33, 50, 28, 42])
    }
}
