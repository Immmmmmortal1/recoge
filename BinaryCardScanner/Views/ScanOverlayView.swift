import SwiftUI

struct ScanOverlayView: View {
    let detectedCards: [Int]
    let statusMessage: String
    var debugFrame: CGImage? = nil

    var body: some View {
        GeometryReader { geo in
            let guideRect = GuideZone.rect(in: geo.size)

            ZStack {
                Color.black.opacity(0.45)
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .frame(width: guideRect.width, height: guideRect.height)
                                    .position(x: guideRect.midX, y: guideRect.midY)
                                    .blendMode(.destinationOut)
                            )
                    )

                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.yellow, lineWidth: 2.5)
                    .frame(width: guideRect.width, height: guideRect.height)
                    .position(x: guideRect.midX, y: guideRect.midY)

                VStack(spacing: 10) {
                    Text(statusMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(8)
                        .padding(.top, max(8, guideRect.minY - 52))

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
                                    .padding(8)
                                    .background(Color.black.opacity(0.72))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        .frame(maxWidth: guideRect.width + 40)
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)

                if let debugFrame {
                    VStack {
                        Spacer()
                        HStack {
                            VStack(spacing: 2) {
                                Text("检测器输入")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                Image(decorative: debugFrame, scale: 1, orientation: .up)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 120, maxHeight: 200)
                                    .border(Color.yellow, width: 1)
                            }
                            Spacer()
                        }
                        .padding(.leading, 12)
                        .padding(.bottom, 130)
                    }
                }
            }
        }
    }
}
