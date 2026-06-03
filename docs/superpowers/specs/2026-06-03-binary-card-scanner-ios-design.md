# Binary Card Scanner — iOS App Design Spec

**Date:** 2026-06-03  
**Status:** Approved

---

## Overview

An iOS app that uses the camera to scan a stack of physical product cards in real-time. Each card's side face contains 6 vertical black bars (long = 1, short = 0) encoding a unique 6-bit binary ID. The app detects all cards in frame simultaneously, converts each binary code to decimal, and announces the results via text-to-speech when the user taps the broadcast button.

---

## Product Context

- **Cards:** 20 unique product cards, each with a distinct 6-bit side marking (values 0–19 used out of 0–63 possible)
- **Cards per scan:** Variable, 1–20 cards at a time
- **Card arrangement:** Cards are stacked in a deck; camera is aimed at the side edge of the stack
- **Card side width:** approximately 1 cm per card
- **Visual encoding:** 6 vertical black bars on a blue background
  - Long bar = 1
  - Short bar = 0
  - Bars read left-to-right = MSB to LSB (bit5 … bit0)

---

## Card Side Design Requirements

To ensure reliable optical recognition, the physical card side should follow these guidelines:

| Property | Specification |
|----------|--------------|
| Background color | High-contrast (blue recommended, as in reference image) |
| Bar color | Black |
| Number of bars | 6 (fixed positions, evenly spaced) |
| Long bar height | ≥ 60% of card width (the 1 cm edge) |
| Short bar height | ≤ 35% of card width |
| Bar width | Uniform across all 6 positions |
| Gap between bars | At least 1 bar-width of spacing |

---

## App Features

### 1. Real-Time Camera Preview
- Full-screen camera view using `AVFoundation`
- Overlay shows a rectangular scan guide zone
- User aligns the side of the card stack with the guide zone

### 2. Card Detection & Binary Reading
- Triggered by tapping the "Broadcast" button
- Captures the current frame from the camera
- Locates 6 bar columns by finding X positions with high dark-pixel density (color-agnostic)
- Uses one reference column to find card row boundaries (alternating dark/light segments)
- For each card row, reads each of the 6 columns: bar height > 60% → 1, else → 0
- Outputs a list of decimal values, one per detected card

### 3. Voice Broadcast
- On button tap: reads all detected card IDs aloud in order
- Uses `AVSpeechSynthesizer` with Chinese locale (`zh-CN`)
- Example output: "五，十二，三，十九，八" (one number per card, top to bottom)
- Results also shown as text on screen

### 4. On-Screen Results
- Below the scan zone: list of detected card numbers (e.g. "No.1: 5  No.2: 12 ...")
- Updates each time the button is tapped

---

## Architecture

```
CardScannerApp (SwiftUI)
│
├── CameraManager (AVFoundation)
│     AVCaptureSession → CMSampleBuffer → CVPixelBuffer
│
├── ScanOverlayView (SwiftUI)
│     Draws the guide rectangle over camera preview
│
├── CardDetector (Swift class)
│     Input:  CVPixelBuffer cropped to guide zone
│     Steps:
│       1. Convert to grayscale CIImage
│       2. Horizontal scan → find blue-pixel row ranges (card bands)
│       3. For each band: sample 6 column positions
│       4. Per column: count consecutive dark pixels (bar height)
│       5. Compare to threshold → bit value
│       6. Assemble 6 bits → UInt8 decimal
│     Output: [Int]
│
├── ResultViewModel (ObservableObject)
│     Holds [Int] of detected card values
│     Triggers SpeechService on button tap
│
└── SpeechService (AVSpeechSynthesizer)
      Speaks each number in sequence
```

---

## Key Algorithms

### Design Invariant

> On any single vertical column (Y-axis) within the guide zone, there are **exactly N dark bar segments** where N equals the number of cards in the stack. The background color is irrelevant — only the dark bar pattern matters.

### Step 1 — Locate the 6 Bar Columns (X positions)

```
For each column x in guide zone image:
  dark_pixel_ratio = count(pixels where luminance < 80) / image_height
  If dark_pixel_ratio > threshold (e.g. 0.15):
    Mark x as "bar column candidate"

Group consecutive candidates → 6 column centers
(Exactly 6 groups expected; if not 6, report detection failure)
```

### Step 2 — Find Card Row Boundaries (Y positions)

```
Use any one of the 6 detected column centers.
Scan that column from top to bottom:
  Identify alternating "dark segments" (bar) and "light segments" (gap)
  Each dark segment → one card's row range [y_start, y_end]

Result: list of (y_start, y_end) tuples, one per card
```

### Step 3 — Read Bits (per card row, across all 6 columns)

```
For card row i with range [y_start, y_end]:
  band_height = y_end - y_start
  For each of the 6 column centers x_j:
    Count consecutive dark pixels within [y_start, y_end] at column x_j
    bar_height = count
    bit_j = (bar_height / band_height > 0.6) ? 1 : 0

  binary_string = bit_0 bit_1 bit_2 bit_3 bit_4 bit_5  // MSB to LSB, left to right
  decimal_value = Int(binary_string, radix: 2)
```

### Thresholds

| Parameter | Value | Notes |
|-----------|-------|-------|
| Dark pixel luminance | < 80 (0–255) | Adjust if bars are not pure black |
| Column candidate ratio | > 0.15 | Column has ≥15% dark pixels |
| Long bar threshold | > 60% of band height | Bit = 1 |
| Short bar threshold | < 35% of band height | Bit = 0 |
| Ambiguous zone | 35%–60% | Mark as `?`, skip |

---

## UI Layout

```
┌───────────────────────────┐
│                           │
│     [Camera Preview]      │
│                           │
│   ╔═══════════════════╗   │
│   ║  ← scan guide →   ║   │
│   ║  (align card      ║   │
│   ║   stack side)     ║   │
│   ╚═══════════════════╝   │
│                           │
│  Results:                 │
│  No.1: 5    No.2: 12     │
│  No.3: 3    No.4: 19     │
│                           │
│      [ 🔊  播  报 ]        │
└───────────────────────────┘
```

---

## File Structure

```
BinaryCardScanner/
├── App/
│   └── BinaryCardScannerApp.swift
├── Camera/
│   └── CameraManager.swift          // AVCaptureSession setup & frame delivery
├── Detection/
│   └── CardDetector.swift           // Core image analysis & binary decoding
├── Speech/
│   └── SpeechService.swift          // AVSpeechSynthesizer wrapper
├── ViewModel/
│   └── ScanViewModel.swift          // State: cards detected, trigger speech
└── Views/
    ├── ContentView.swift            // Root view
    ├── CameraPreviewView.swift      // UIViewRepresentable wrapping AVPreviewLayer
    └── ScanOverlayView.swift        // Guide rectangle + results overlay
```

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Camera permission denied | Show settings prompt |
| No cards detected in frame | Results area shows "未检测到卡片" |
| Partial detection (< expected cards) | Show what was found, broadcast those |
| Ambiguous bar height (near threshold) | Mark as `?`, skip in broadcast |

---

## Out of Scope

- Card database / product name lookup (only decimal numbers are announced)
- History / logging of previous scans
- Multiple scan modes (realtime auto-trigger is out; button-trigger only)
- Android version
