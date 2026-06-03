import SwiftUI

struct ScanOverlayView: View {
    let detectedCards: [Int]
    let statusMessage: String

    // Guide zone matches CameraManager.guideNormalizedRect
    private let guideX: CGFloat = 0.25
    private let guideY: CGFloat = 0.10
    private let guideW: CGFloat = 0.50
    private let guideH: CGFloat = 0.80

    var body: some View {
        GeometryReader { geo in
            let gRect = CGRect(
                x: geo.size.width  * guideX,
                y: geo.size.height * guideY,
                width:  geo.size.width  * guideW,
                height: geo.size.height * guideH
            )

            ZStack(alignment: .top) {
                // Dim outside guide zone
                Color.black.opacity(0.45)
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .frame(width: gRect.width, height: gRect.height)
                                    .offset(x: gRect.minX - geo.size.width / 2,
                                            y: gRect.minY - geo.size.height / 2)
                                    .blendMode(.destinationOut)
                            )
                    )

                // Guide border
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: gRect.width, height: gRect.height)
                    .position(x: gRect.midX, y: gRect.midY)

                // Status label
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(6)
                    .padding(.top, 12)

                // Results row
                if !detectedCards.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
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
                                .background(Color.black.opacity(0.65))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 56)
                    .padding(.top, geo.size.height - 150)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
