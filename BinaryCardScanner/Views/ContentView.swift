import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var cameraPermissionGranted = false

    var body: some View {
        Group {
            if cameraPermissionGranted {
                ScannerView(camera: camera)
            } else {
                PermissionDeniedView()
            }
        }
        .onAppear {
            CameraManager.requestPermission { granted in
                cameraPermissionGranted = granted
            }
        }
    }
}

private struct ScannerView: View {
    @ObservedObject var camera: CameraManager
    @StateObject private var viewModel: ScanViewModel

    init(camera: CameraManager) {
        self.camera = camera
        _viewModel = StateObject(wrappedValue: ScanViewModel(camera: camera))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundColor(.gray)
            Text("需要相机权限")
                .font(.title2.bold())
            Text("请在 设置 → BinaryCardScanner 中开启相机访问权限")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("前往设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
