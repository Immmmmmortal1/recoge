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
}
