# Binary Card Scanner iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an iOS app that scans a stacked deck of product cards from the side, reads 6 vertical bars per card as 6-bit binary, converts to decimal, and announces results in Chinese via text-to-speech.

**Architecture:** AVFoundation delivers camera frames → user taps Broadcast button → CardDetector crops guide-zone frame and runs pixel-column analysis to locate 6 bar columns and N card rows → ScanViewModel holds results → SpeechService reads numbers aloud in Chinese.

**Tech Stack:** Swift 5.9, SwiftUI, AVFoundation, AVSpeechSynthesizer, XCTest (unit tests on CardDetector), iOS 16+, Xcode 15+

---

## File Map

| File | Responsibility |
|------|---------------|
| `BinaryCardScanner/App/BinaryCardScannerApp.swift` | App entry point |
| `BinaryCardScanner/Camera/CameraManager.swift` | AVCaptureSession; publishes `CVPixelBuffer` frames |
| `BinaryCardScanner/Detection/PixelBuffer+Analysis.swift` | Low-level pixel access helpers (luminance at point, column dark-ratio) |
| `BinaryCardScanner/Detection/CardDetector.swift` | Core algorithm: find 6 columns → find card rows → read bits → return `[Int]` |
| `BinaryCardScanner/Speech/SpeechService.swift` | Wraps AVSpeechSynthesizer; speaks a list of numbers in Chinese |
| `BinaryCardScanner/ViewModel/ScanViewModel.swift` | ObservableObject; holds detected card values; triggers speech |
| `BinaryCardScanner/Views/CameraPreviewView.swift` | UIViewRepresentable wrapping AVCaptureVideoPreviewLayer |
| `BinaryCardScanner/Views/ScanOverlayView.swift` | SwiftUI overlay: guide rectangle + results list |
| `BinaryCardScanner/Views/ContentView.swift` | Root view composing camera + overlay + button |
| `BinaryCardScannerTests/CardDetectorTests.swift` | XCTest unit tests for CardDetector using synthetic images |

---

## Task 1: Xcode Project Scaffold

**Files:**
- Create: `BinaryCardScanner/App/BinaryCardScannerApp.swift`
- Modify: `BinaryCardScanner/Info.plist` (camera permission)

- [ ] **Step 1: Create Xcode project**

  In Xcode: File → New → Project → iOS → App  
  - Product Name: `BinaryCardScanner`  
  - Interface: SwiftUI  
  - Language: Swift  
  - Include Tests: ✓  
  - Minimum Deployment: iOS 16.0  

- [ ] **Step 2: Add camera permission to Info.plist**

  Add these two keys to `BinaryCardScanner/Info.plist`:
  ```xml
  <key>NSCameraUsageDescription</key>
  <string>需要访问相机来扫描卡片侧面的二进制标记</string>
  ```

- [ ] **Step 3: Replace generated App entry point**

  `BinaryCardScanner/App/BinaryCardScannerApp.swift`:
  ```swift
  import SwiftUI

  @main
  struct BinaryCardScannerApp: App {
      var body: some Scene {
          WindowGroup {
              ContentView()
          }
      }
  }
  ```

- [ ] **Step 4: Create stub ContentView so project builds**

  `BinaryCardScanner/Views/ContentView.swift`:
  ```swift
  import SwiftUI

  struct ContentView: View {
      var body: some View {
          Text("Binary Card Scanner")
      }
  }
  ```

- [ ] **Step 5: Build and verify**

  Cmd+B → Build Succeeded, no warnings about missing keys.

- [ ] **Step 6: Commit**
  ```bash
  git add .
  git commit -m "feat: scaffold BinaryCardScanner iOS project"
  ```

---

## Task 2: PixelBuffer Analysis Helpers

**Files:**
- Create: `BinaryCardScanner/Detection/PixelBuffer+Analysis.swift`
- Create: `BinaryCardScannerTests/CardDetectorTests.swift` (stub)

These are pure functions with no UIKit/AVFoundation dependencies — easy to unit test.

- [ ] **Step 1: Write failing tests first**

  `BinaryCardScannerTests/CardDetectorTests.swift`:
  ```swift
  import XCTest
  @testable import BinaryCardScanner

  final class CardDetectorTests: XCTestCase {

      // Helper: create a CGImage filled with a solid color
      func solidImage(width: Int, height: Int, gray: UInt8) -> CGImage {
          let bytesPerPixel = 1
          var pixels = [UInt8](repeating: gray, count: width * height)
          let colorSpace = CGColorSpaceCreateDeviceGray()
          let ctx = CGContext(data: &pixels,
                              width: width, height: height,
                              bitsPerComponent: 8,
                              bytesPerRow: width * bytesPerPixel,
                              space: colorSpace,
                              bitmapInfo: 0)!
          return ctx.makeImage()!
      }

      // Helper: create image with a vertical dark bar at given x range
      func imageWithDarkBar(width: Int, height: Int,
                             barX: ClosedRange<Int>, barHeight: Int) -> CGImage {
          let bytesPerPixel = 1
          var pixels = [UInt8](repeating: 220, count: width * height) // light bg
          let barTop = (height - barHeight) / 2
          for y in barTop..<(barTop + barHeight) {
              for x in barX {
                  pixels[y * width + x] = 30 // dark bar
              }
          }
          let colorSpace = CGColorSpaceCreateDeviceGray()
          let ctx = CGContext(data: &pixels,
                              width: width, height: height,
                              bitsPerComponent: 8,
                              bytesPerRow: width * bytesPerPixel,
                              space: colorSpace,
                              bitmapInfo: 0)!
          return ctx.makeImage()!
      }

      func test_darkRatioInColumn_allDark() {
          let img = solidImage(width: 10, height: 100, gray: 30)
          let ratio = img.darkRatioInColumn(x: 5, threshold: 80)
          XCTAssertEqual(ratio, 1.0, accuracy: 0.01)
      }

      func test_darkRatioInColumn_allLight() {
          let img = solidImage(width: 10, height: 100, gray: 220)
          let ratio = img.darkRatioInColumn(x: 5, threshold: 80)
          XCTAssertEqual(ratio, 0.0, accuracy: 0.01)
      }

      func test_longestDarkSegmentInColumn_returnsBarHeight() {
          // Dark bar occupies center 40 rows of a 100-row column
          let img = imageWithDarkBar(width: 10, height: 100, barX: 3...6, barHeight: 40)
          let segLen = img.longestDarkSegmentInColumn(x: 5, threshold: 80)
          XCTAssertEqual(segLen, 40)
      }
  }
  ```

- [ ] **Step 2: Run tests — expect compile error (functions not defined yet)**

  Cmd+U → Build Failure: `'darkRatioInColumn' not found`

- [ ] **Step 3: Implement pixel helpers**

  `BinaryCardScanner/Detection/PixelBuffer+Analysis.swift`:
  ```swift
  import CoreGraphics
  import Foundation

  extension CGImage {

      /// Ratio of pixels in column `x` with luminance < `threshold` (0–255).
      func darkRatioInColumn(x: Int, threshold: UInt8 = 80) -> Double {
          guard x >= 0, x < width else { return 0 }
          guard let data = dataProvider?.data,
                let ptr = CFDataGetBytePtr(data) else { return 0 }

          let bytesPerRow = bytesPerRow
          let bytesPerPixel = bitsPerPixel / 8
          var darkCount = 0
          for y in 0..<height {
              let offset = y * bytesPerRow + x * bytesPerPixel
              // Use red channel as luminance proxy (works for grayscale and RGB)
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

          let bytesPerRow = bytesPerRow
          let bytesPerPixel = bitsPerPixel / 8
          var maxLen = 0, curLen = 0
          for y in 0..<height {
              let offset = y * bytesPerRow + x * bytesPerPixel
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

      /// Returns the y-ranges of all dark segments in column `x`, each as a `Range<Int>`.
      func darkSegmentsInColumn(x: Int, threshold: UInt8 = 80,
                                 minLength: Int = 3) -> [Range<Int>] {
          guard x >= 0, x < width else { return [] }
          guard let data = dataProvider?.data,
                let ptr = CFDataGetBytePtr(data) else { return [] }

          let bytesPerRow = bytesPerRow
          let bytesPerPixel = bitsPerPixel / 8
          var segments: [Range<Int>] = []
          var segStart: Int? = nil
          for y in 0..<height {
              let offset = y * bytesPerRow + x * bytesPerPixel
              let lum = ptr[offset]
              let isDark = lum < threshold
              if isDark && segStart == nil {
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
  ```

- [ ] **Step 4: Run tests — expect pass**

  Cmd+U → All tests PASS

- [ ] **Step 5: Commit**
  ```bash
  git add BinaryCardScanner/Detection/PixelBuffer+Analysis.swift \
          BinaryCardScannerTests/CardDetectorTests.swift
  git commit -m "feat: add CGImage pixel analysis helpers with tests"
  ```

---

## Task 3: CardDetector — Core Algorithm

**Files:**
- Create: `BinaryCardScanner/Detection/CardDetector.swift`
- Modify: `BinaryCardScannerTests/CardDetectorTests.swift` (add detector tests)

- [ ] **Step 1: Write failing tests for column detection**

  Append to `CardDetectorTests.swift`:
  ```swift
  // MARK: - Column detection

  func test_findBarColumns_finds6Columns() {
      // Create 100×200 image with 6 dark vertical bars, light background
      let width = 120, height = 200
      let bytesPerPixel = 1
      var pixels = [UInt8](repeating: 220, count: width * height)
      // Place 6 bars at x = 10,30,50,70,90,110 each 4px wide, full height
      let barCenters = [10, 30, 50, 70, 90, 110]
      for cx in barCenters {
          for x in (cx-2)...(cx+2) {
              for y in 0..<height {
                  pixels[y * width + x] = 30
              }
          }
      }
      let colorSpace = CGColorSpaceCreateDeviceGray()
      let ctx = CGContext(data: &pixels, width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: width,
                          space: colorSpace, bitmapInfo: 0)!
      let img = ctx.makeImage()!

      let columns = CardDetector.findBarColumns(in: img)
      XCTAssertEqual(columns.count, 6)
      // Centers should be close to expected
      for (idx, expected) in barCenters.enumerated() {
          XCTAssertEqual(columns[idx], expected, accuracy: 3)
      }
  }

  func test_detect_synthetic3Cards() {
      // Build a 120×90 image: 3 cards × 30px each, 6 bars per card
      // Card 0: 101010 = 42, Card 1: 000001 = 1, Card 2: 111111 = 63
      let cardBinaries: [[Int]] = [[1,0,1,0,1,0],[0,0,0,0,0,1],[1,1,1,1,1,1]]
      let img = makeSyntheticImage(cardBinaries: cardBinaries,
                                   cardHeight: 30, barWidth: 6, imageWidth: 120)
      let results = CardDetector.detect(in: img)
      XCTAssertEqual(results, [42, 1, 63])
  }

  // Helper used by multiple tests
  func makeSyntheticImage(cardBinaries: [[Int]],
                           cardHeight: Int, barWidth: Int,
                           imageWidth: Int) -> CGImage {
      let numCards = cardBinaries.count
      let height = numCards * cardHeight
      var pixels = [UInt8](repeating: 220, count: imageWidth * height)

      // Bar column centers: evenly spaced within imageWidth
      let numBars = 6
      let step = imageWidth / (numBars * 2)
      let barCenters = (0..<numBars).map { i in step + i * (imageWidth / numBars) }

      for (cardIdx, bits) in cardBinaries.enumerated() {
          let yTop = cardIdx * cardHeight
          let longHeight = Int(Double(cardHeight) * 0.75)  // bit=1
          let shortHeight = Int(Double(cardHeight) * 0.25) // bit=0
          for (bitIdx, bit) in bits.enumerated() {
              let cx = barCenters[bitIdx]
              let barH = bit == 1 ? longHeight : shortHeight
              let yBarTop = yTop + (cardHeight - barH) / 2
              for y in yBarTop..<(yBarTop + barH) {
                  for x in max(0, cx - barWidth/2)..<min(imageWidth, cx + barWidth/2) {
                      pixels[y * imageWidth + x] = 30
                  }
              }
          }
      }

      let colorSpace = CGColorSpaceCreateDeviceGray()
      let ctx = CGContext(data: &pixels, width: imageWidth, height: height,
                          bitsPerComponent: 8, bytesPerRow: imageWidth,
                          space: colorSpace, bitmapInfo: 0)!
      return ctx.makeImage()!
  }
  ```

- [ ] **Step 2: Run tests — expect compile error**

  Cmd+U → Build Failure: `CardDetector` not found

- [ ] **Step 3: Implement CardDetector**

  `BinaryCardScanner/Detection/CardDetector.swift`:
  ```swift
  import CoreGraphics
  import Foundation

  enum CardDetector {

      static let darkThreshold: UInt8 = 80
      static let columnDarkRatioMin: Double = 0.15
      static let longBarRatio: Double = 0.60   // > this → bit 1
      static let shortBarRatio: Double = 0.35  // < this → bit 0

      // MARK: - Public API

      /// Analyse a CGImage (the cropped guide-zone frame) and return decimal
      /// values for each detected card, ordered top-to-bottom.
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
          // Compute dark ratio for every x column
          var candidates: [(x: Int, ratio: Double)] = []
          for x in 0..<width {
              let ratio = image.darkRatioInColumn(x: x, threshold: darkThreshold)
              if ratio >= columnDarkRatioMin {
                  candidates.append((x, ratio))
              }
          }
          // Group consecutive x positions into clusters; take each cluster's midpoint
          let clusters = groupConsecutive(candidates.map { $0.x })
          return clusters.map { cluster in cluster.reduce(0, +) / cluster.count }
      }

      // MARK: - Step 2: Find card row boundaries using one reference column

      static func findCardRows(in image: CGImage,
                                referenceColumn col: Int) -> [Range<Int>] {
          let minBarHeight = max(4, image.height / 40)
          return image.darkSegmentsInColumn(x: col,
                                            threshold: darkThreshold,
                                            minLength: minBarHeight)
      }

      // MARK: - Step 3: Read 6 bits from a card row

      /// Returns decimal value (0–63) or nil if any bit is ambiguous.
      static func readBits(in image: CGImage,
                            cardRow: Range<Int>,
                            barColumns: [Int]) -> Int? {
          let bandHeight = cardRow.count
          guard bandHeight > 0 else { return nil }

          var bits = [Int]()
          for col in barColumns {
              // Count dark pixels within this card's row range at this column
              let barHeight = darkHeightInRowRange(image: image,
                                                   x: col,
                                                   yRange: cardRow)
              let ratio = Double(barHeight) / Double(bandHeight)
              if ratio > longBarRatio {
                  bits.append(1)
              } else if ratio < shortBarRatio {
                  bits.append(0)
              } else {
                  return nil  // ambiguous — skip card
              }
          }
          // MSB first (leftmost column = bit5)
          return bits.enumerated().reduce(0) { acc, pair in
              acc | (pair.element << (5 - pair.offset))
          }
      }

      // MARK: - Helpers

      /// Longest consecutive dark segment within a row range in a single column.
      private static func darkHeightInRowRange(image: CGImage,
                                               x: Int,
                                               yRange: Range<Int>) -> Int {
          guard let data = image.dataProvider?.data,
                let ptr = CFDataGetBytePtr(data) else { return 0 }
          let bytesPerRow = image.bytesPerRow
          let bytesPerPixel = image.bitsPerPixel / 8
          var maxLen = 0, curLen = 0
          for y in yRange {
              let lum = ptr[y * bytesPerRow + x * bytesPerPixel]
              if lum < darkThreshold {
                  curLen += 1
                  maxLen = max(maxLen, curLen)
              } else {
                  curLen = 0
              }
          }
          return maxLen
      }

      /// Group a sorted list of integers into runs of consecutive values.
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
  ```

- [ ] **Step 4: Run tests — expect pass**

  Cmd+U → All tests PASS

- [ ] **Step 5: Commit**
  ```bash
  git add BinaryCardScanner/Detection/CardDetector.swift \
          BinaryCardScannerTests/CardDetectorTests.swift
  git commit -m "feat: implement CardDetector with pixel-column binary analysis"
  ```

---

## Task 4: CameraManager

**Files:**
- Create: `BinaryCardScanner/Camera/CameraManager.swift`

- [ ] **Step 1: Implement CameraManager**

  `BinaryCardScanner/Camera/CameraManager.swift`:
  ```swift
  import AVFoundation
  import CoreImage
  import UIKit

  final class CameraManager: NSObject, ObservableObject {

      let session = AVCaptureSession()
      private let videoOutput = AVCaptureVideoDataOutput()
      private let sessionQueue = DispatchQueue(label: "camera.session")

      /// Latest frame delivered from the camera. Updated on main thread.
      @Published var latestFrame: CVPixelBuffer?

      /// Rect (in preview-layer coordinates, 0–1) that defines the scan guide zone.
      /// The detector crops to this region before analysis.
      var guideNormalizedRect = CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8)

      override init() {
          super.init()
          setupSession()
      }

      private func setupSession() {
          sessionQueue.async { [weak self] in
              guard let self else { return }
              self.session.beginConfiguration()
              self.session.sessionPreset = .hd1280x720

              guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                          for: .video,
                                                          position: .back),
                    let input = try? AVCaptureDeviceInput(device: device),
                    self.session.canAddInput(input) else {
                  self.session.commitConfiguration()
                  return
              }
              self.session.addInput(input)

              self.videoOutput.setSampleBufferDelegate(self,
                  queue: DispatchQueue(label: "camera.frames"))
              self.videoOutput.videoSettings = [
                  kCVPixelBufferPixelFormatTypeKey as String:
                      kCVPixelFormatType_32BGRA
              ]
              if self.session.canAddOutput(self.videoOutput) {
                  self.session.addOutput(self.videoOutput)
              }
              self.session.commitConfiguration()
          }
      }

      func start() {
          sessionQueue.async { [weak self] in
              self?.session.startRunning()
          }
      }

      func stop() {
          sessionQueue.async { [weak self] in
              self?.session.stopRunning()
          }
      }

      /// Capture a single frame cropped to the guide zone as a CGImage.
      func captureGuidedFrame() -> CGImage? {
          guard let pixelBuffer = latestFrame else { return nil }
          let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
          let fullSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                height: CVPixelBufferGetHeight(pixelBuffer))
          let cropRect = CGRect(
              x: guideNormalizedRect.minX * fullSize.width,
              y: guideNormalizedRect.minY * fullSize.height,
              width: guideNormalizedRect.width * fullSize.width,
              height: guideNormalizedRect.height * fullSize.height
          )
          let cropped = ciImage.cropped(to: cropRect)
          // Convert to grayscale CGImage for analysis
          let grayFilter = CIFilter.colorControls()
          grayFilter.inputImage = cropped
          grayFilter.saturation = 0
          guard let output = grayFilter.outputImage else { return nil }
          return CIContext().createCGImage(output, from: output.extent)
      }
  }

  extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
      func captureOutput(_ output: AVCaptureOutput,
                         didOutput sampleBuffer: CMSampleBuffer,
                         from connection: AVCaptureConnection) {
          guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
          DispatchQueue.main.async { [weak self] in
              self?.latestFrame = buf
          }
      }
  }
  ```

- [ ] **Step 2: Build and verify**

  Cmd+B → Build Succeeded

- [ ] **Step 3: Commit**
  ```bash
  git add BinaryCardScanner/Camera/CameraManager.swift
  git commit -m "feat: add CameraManager with AVFoundation frame capture"
  ```

---

## Task 5: SpeechService

**Files:**
- Create: `BinaryCardScanner/Speech/SpeechService.swift`

- [ ] **Step 1: Implement SpeechService**

  `BinaryCardScanner/Speech/SpeechService.swift`:
  ```swift
  import AVFoundation

  final class SpeechService: NSObject {

      private let synthesizer = AVSpeechSynthesizer()

      /// Speak a list of decimal integers in Chinese, pausing between each.
      /// Example: [5, 12, 3] → "五，十二，三"
      func speak(_ numbers: [Int]) {
          synthesizer.stopSpeaking(at: .immediate)
          guard !numbers.isEmpty else { return }

          // Join with Chinese comma pause
          let text = numbers.map { String($0) }.joined(separator: "，")
          let utterance = AVSpeechUtterance(string: text)
          utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
          utterance.rate = 0.45   // slightly slower than default for clarity
          utterance.pitchMultiplier = 1.0
          synthesizer.speak(utterance)
      }

      func stop() {
          synthesizer.stopSpeaking(at: .immediate)
      }
  }
  ```

- [ ] **Step 2: Build and verify**

  Cmd+B → Build Succeeded

- [ ] **Step 3: Commit**
  ```bash
  git add BinaryCardScanner/Speech/SpeechService.swift
  git commit -m "feat: add SpeechService for Chinese number announcement"
  ```

---

## Task 6: ScanViewModel

**Files:**
- Create: `BinaryCardScanner/ViewModel/ScanViewModel.swift`

- [ ] **Step 1: Implement ScanViewModel**

  `BinaryCardScanner/ViewModel/ScanViewModel.swift`:
  ```swift
  import Foundation
  import Combine

  final class ScanViewModel: ObservableObject {

      @Published var detectedCards: [Int] = []
      @Published var statusMessage: String = "将卡片侧边对准扫描框"

      private let camera: CameraManager
      private let speech = SpeechService()

      init(camera: CameraManager) {
          self.camera = camera
      }

      /// Called when user taps the Broadcast button.
      func scanAndBroadcast() {
          guard let frame = camera.captureGuidedFrame() else {
              statusMessage = "无法获取图像"
              return
          }
          let results = CardDetector.detect(in: frame)
          if results.isEmpty {
              statusMessage = "未检测到卡片"
              detectedCards = []
          } else {
              detectedCards = results
              statusMessage = "检测到 \(results.count) 张卡片"
              speech.speak(results)
          }
      }
  }
  ```

- [ ] **Step 2: Build and verify**

  Cmd+B → Build Succeeded

- [ ] **Step 3: Commit**
  ```bash
  git add BinaryCardScanner/ViewModel/ScanViewModel.swift
  git commit -m "feat: add ScanViewModel connecting camera, detector, and speech"
  ```

---

## Task 7: Camera Preview & Overlay Views

**Files:**
- Create: `BinaryCardScanner/Views/CameraPreviewView.swift`
- Create: `BinaryCardScanner/Views/ScanOverlayView.swift`

- [ ] **Step 1: Implement CameraPreviewView**

  `BinaryCardScanner/Views/CameraPreviewView.swift`:
  ```swift
  import SwiftUI
  import AVFoundation

  struct CameraPreviewView: UIViewRepresentable {
      let session: AVCaptureSession

      func makeUIView(context: Context) -> PreviewUIView {
          let view = PreviewUIView()
          view.session = session
          return view
      }

      func updateUIView(_ uiView: PreviewUIView, context: Context) {}
  }

  final class PreviewUIView: UIView {
      override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
      var previewLayer: AVCaptureVideoPreviewLayer {
          layer as! AVCaptureVideoPreviewLayer
      }
      var session: AVCaptureSession? {
          didSet { previewLayer.session = session }
      }
      override init(frame: CGRect) {
          super.init(frame: frame)
          previewLayer.videoGravity = .resizeAspectFill
      }
      required init?(coder: NSCoder) { fatalError() }
  }
  ```

- [ ] **Step 2: Implement ScanOverlayView**

  `BinaryCardScanner/Views/ScanOverlayView.swift`:
  ```swift
  import SwiftUI

  struct ScanOverlayView: View {
      let detectedCards: [Int]
      let statusMessage: String

      var body: some View {
          GeometryReader { geo in
              // Guide rectangle (matches CameraManager.guideNormalizedRect: 25%,10%,50%,80%)
              let guideRect = CGRect(
                  x: geo.size.width * 0.25,
                  y: geo.size.height * 0.10,
                  width: geo.size.width * 0.50,
                  height: geo.size.height * 0.80
              )
              ZStack(alignment: .topLeading) {
                  // Semi-transparent dimming outside guide
                  Color.black.opacity(0.4)
                      .mask(
                          Rectangle()
                              .overlay(
                                  RoundedRectangle(cornerRadius: 8)
                                      .frame(width: guideRect.width,
                                             height: guideRect.height)
                                      .offset(x: guideRect.minX,
                                              y: guideRect.minY)
                                      .blendMode(.destinationOut)
                              )
                      )

                  // Guide border
                  RoundedRectangle(cornerRadius: 8)
                      .stroke(Color.yellow, lineWidth: 2)
                      .frame(width: guideRect.width, height: guideRect.height)
                      .offset(x: guideRect.minX, y: guideRect.minY)

                  // Status + results at bottom
                  VStack(spacing: 4) {
                      Text(statusMessage)
                          .font(.caption)
                          .foregroundColor(.white)
                          .padding(.horizontal, 8)
                          .background(Color.black.opacity(0.5))
                          .cornerRadius(4)

                      if !detectedCards.isEmpty {
                          ScrollView(.horizontal, showsIndicators: false) {
                              HStack(spacing: 12) {
                                  ForEach(Array(detectedCards.enumerated()), id: \.offset) { idx, val in
                                      VStack(spacing: 2) {
                                          Text("No.\(idx + 1)")
                                              .font(.caption2)
                                              .foregroundColor(.gray)
                                          Text("\(val)")
                                              .font(.title3.bold())
                                              .foregroundColor(.white)
                                      }
                                      .padding(6)
                                      .background(Color.black.opacity(0.6))
                                      .cornerRadius(6)
                                  }
                              }
                              .padding(.horizontal, 12)
                          }
                      }
                  }
                  .frame(maxWidth: .infinity)
                  .offset(y: geo.size.height - 120)
              }
          }
      }
  }
  ```

- [ ] **Step 3: Build and verify**

  Cmd+B → Build Succeeded

- [ ] **Step 4: Commit**
  ```bash
  git add BinaryCardScanner/Views/CameraPreviewView.swift \
          BinaryCardScanner/Views/ScanOverlayView.swift
  git commit -m "feat: add camera preview and scan overlay views"
  ```

---

## Task 8: ContentView Integration

**Files:**
- Modify: `BinaryCardScanner/Views/ContentView.swift`

- [ ] **Step 1: Implement ContentView**

  `BinaryCardScanner/Views/ContentView.swift`:
  ```swift
  import SwiftUI

  struct ContentView: View {
      @StateObject private var camera = CameraManager()
      @StateObject private var viewModel: ScanViewModel

      init() {
          let cam = CameraManager()
          _camera = StateObject(wrappedValue: cam)
          _viewModel = StateObject(wrappedValue: ScanViewModel(camera: cam))
      }

      var body: some View {
          ZStack {
              // Full-screen camera preview
              CameraPreviewView(session: camera.session)
                  .ignoresSafeArea()

              // Guide overlay + results
              ScanOverlayView(
                  detectedCards: viewModel.detectedCards,
                  statusMessage: viewModel.statusMessage
              )
              .ignoresSafeArea()

              // Broadcast button anchored to bottom
              VStack {
                  Spacer()
                  Button {
                      viewModel.scanAndBroadcast()
                  } label: {
                      HStack(spacing: 8) {
                          Image(systemName: "speaker.wave.2.fill")
                          Text("播  报")
                              .fontWeight(.semibold)
                      }
                      .foregroundColor(.white)
                      .padding(.horizontal, 40)
                      .padding(.vertical, 16)
                      .background(Color.blue)
                      .cornerRadius(30)
                      .shadow(radius: 6)
                  }
                  .padding(.bottom, 48)
              }
          }
          .onAppear { camera.start() }
          .onDisappear { camera.stop() }
      }
  }
  ```

- [ ] **Step 2: Fix StateObject double-init issue**

  The `init()` above creates `CameraManager` twice due to `@StateObject` usage pattern. Use this corrected pattern instead — replace the whole ContentView with:

  ```swift
  import SwiftUI

  struct ContentView: View {
      @StateObject private var camera = CameraManager()

      var body: some View {
          ContentInnerView(camera: camera)
              .onAppear { camera.start() }
              .onDisappear { camera.stop() }
      }
  }

  private struct ContentInnerView: View {
      @ObservedObject var camera: CameraManager
      @StateObject private var viewModel: ScanViewModel

      init(camera: CameraManager) {
          self.camera = camera
          _viewModel = StateObject(wrappedValue: ScanViewModel(camera: camera))
      }

      var body: some View {
          ZStack {
              CameraPreviewView(session: camera.session)
                  .ignoresSafeArea()

              ScanOverlayView(
                  detectedCards: viewModel.detectedCards,
                  statusMessage: viewModel.statusMessage
              )
              .ignoresSafeArea()

              VStack {
                  Spacer()
                  Button {
                      viewModel.scanAndBroadcast()
                  } label: {
                      HStack(spacing: 8) {
                          Image(systemName: "speaker.wave.2.fill")
                          Text("播  报")
                              .fontWeight(.semibold)
                      }
                      .foregroundColor(.white)
                      .padding(.horizontal, 40)
                      .padding(.vertical, 16)
                      .background(Color.blue)
                      .cornerRadius(30)
                      .shadow(radius: 6)
                  }
                  .padding(.bottom, 48)
              }
          }
      }
  }
  ```

- [ ] **Step 3: Build and run on simulator or device**

  Cmd+R → App launches, camera preview shows, button visible at bottom.  
  Note: camera requires a **real device** (simulator has no camera).

- [ ] **Step 4: Commit**
  ```bash
  git add BinaryCardScanner/Views/ContentView.swift
  git commit -m "feat: integrate ContentView with camera, overlay, and broadcast button"
  ```

---

## Task 9: Camera Permission Request & Polish

**Files:**
- Modify: `BinaryCardScanner/Camera/CameraManager.swift`
- Modify: `BinaryCardScanner/Views/ContentView.swift`

- [ ] **Step 1: Add permission check to CameraManager**

  Add this method to `CameraManager`:
  ```swift
  static func requestPermission(completion: @escaping (Bool) -> Void) {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized:
          completion(true)
      case .notDetermined:
          AVCaptureDevice.requestAccess(for: .video) { granted in
              DispatchQueue.main.async { completion(granted) }
          }
      default:
          completion(false)
      }
  }
  ```

- [ ] **Step 2: Add `cameraPermissionGranted` state to ContentView**

  Add `@State private var cameraPermissionGranted = false` to `ContentView` and replace `.onAppear`:
  ```swift
  .onAppear {
      CameraManager.requestPermission { granted in
          cameraPermissionGranted = granted
          if granted { camera.start() }
      }
  }
  ```

  Show a message if permission is denied by adding to ContentView's ZStack:
  ```swift
  if !cameraPermissionGranted {
      VStack(spacing: 16) {
          Image(systemName: "camera.fill")
              .font(.system(size: 48))
              .foregroundColor(.gray)
          Text("需要相机权限\n请在设置中开启")
              .multilineTextAlignment(.center)
              .foregroundColor(.white)
          Button("前往设置") {
              if let url = URL(string: UIApplication.openSettingsURLString) {
                  UIApplication.shared.open(url)
              }
          }
          .foregroundColor(.blue)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.black)
  }
  ```

- [ ] **Step 3: Build and run on real device, test permission flow**

  First launch → permission dialog appears → allow → camera starts.

- [ ] **Step 4: Commit**
  ```bash
  git add BinaryCardScanner/Camera/CameraManager.swift \
          BinaryCardScanner/Views/ContentView.swift
  git commit -m "feat: add camera permission request and denied-state UI"
  ```

---

## Task 10: On-Device Integration Test

- [ ] **Step 1: Print physical test card**

  Print or draw a test card with known encoding, e.g.:
  - Card A: `010011` (long/short/long/long/short/short from left) = decimal 19
  - Card B: `000001` = decimal 1

  Use dark ink on white/colored paper, 6 bars spaced evenly, long bar ≈ 2× short bar height.

- [ ] **Step 2: Stack cards and test**

  Run app on device, aim camera at card stack side, tap 播报.  
  Expected: app announces "十九，一" (or whatever your test cards encode).

- [ ] **Step 3: Adjust thresholds if needed**

  If detection is unreliable, tune these constants in `CardDetector.swift`:
  ```swift
  static let darkThreshold: UInt8 = 80        // raise if bars are gray, not pure black
  static let columnDarkRatioMin: Double = 0.15 // lower if bars are thin
  static let longBarRatio: Double = 0.60       // adjust to actual bar proportions
  static let shortBarRatio: Double = 0.35
  ```

- [ ] **Step 4: Final commit**
  ```bash
  git add .
  git commit -m "feat: binary card scanner app complete"
  ```

---

## Plan Self-Review

**Spec coverage check:**
- ✓ 20 cards, unique 6-bit IDs → CardDetector handles 0–63
- ✓ 6 vertical bars per card → findBarColumns returns 6 centers
- ✓ Long=1 / Short=0 → readBits threshold logic
- ✓ Variable 1–20 cards per scan → findCardRows returns dynamic list
- ✓ Color-agnostic detection → only luminance threshold used, no hue checks
- ✓ Button-triggered broadcast → scanAndBroadcast() on tap
- ✓ Chinese voice → AVSpeechSynthesisVoice(language: "zh-CN")
- ✓ Results shown on screen → ScanOverlayView results list
- ✓ Camera permission → Task 9
- ✓ "No cards detected" state → statusMessage handling

**Type consistency check:**
- `CardDetector.detect(in: CGImage) -> [Int]` used consistently in ViewModel and tests ✓
- `CameraManager.captureGuidedFrame() -> CGImage?` returns optional correctly handled ✓
- `SpeechService.speak([Int])` matches call site in ViewModel ✓
