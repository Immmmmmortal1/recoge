import CoreGraphics

/// Scan guide in UI-normalized coordinates (0–1, origin top-left).
/// Tall, centered ROI for a card side: six vertical bars, multiple stacked cards along Y.
enum GuideZone {
    /// ~44% width × ~58% height — matches physical card-side aspect in portrait.
    static let normalizedRect = CGRect(x: 0.28, y: 0.16, width: 0.44, height: 0.58)

    static func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: size.width * normalizedRect.minX,
            y: size.height * normalizedRect.minY,
            width: size.width * normalizedRect.width,
            height: size.height * normalizedRect.height
        )
    }
}
