import SwiftUI

private enum CameraPermissionState {
    case pending
    case granted
    case denied
}

struct ContentView: View {
    @State private var permission: CameraPermissionState = .pending

    var body: some View {
        Group {
            switch permission {
            case .pending:
                CameraStartupView(message: "正在请求相机权限…")
            case .denied:
                PermissionDeniedView()
            case .granted:
                ScannerView()
            }
        }
        .onAppear {
            CameraManager.requestPermission { granted in
                permission = granted ? .granted : .denied
            }
        }
    }
}

private struct CameraStartupView: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                Text(message)
                    .foregroundColor(.white)
                    .font(.body)
            }
        }
    }
}

private struct ScannerView: View {
    @StateObject private var camera: CameraManager
    @StateObject private var viewModel: ScanViewModel

    init() {
        let camera = CameraManager()
        _camera = StateObject(wrappedValue: camera)
        _viewModel = StateObject(wrappedValue: ScanViewModel(camera: camera))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.isSessionReady {
                CameraPreviewView(camera: camera, session: camera.session)
                    .ignoresSafeArea()
                    .opacity(camera.isPreviewActive ? 1 : 0)
            }

            ScanOverlayView(
                detectedCards: viewModel.detectedCards,
                statusMessage: overlayStatusMessage,
                debugFrame: viewModel.debugFrame
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
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .allowsHitTesting(false),
                    alignment: .bottom
                )
            }

            if !camera.isPreviewActive {
                CameraStartupView(
                    message: startupMessage
                )
            }
        }
        .onAppear { camera.start() }
        .onChange(of: camera.isSessionReady) { ready in
            if ready { camera.start() }
        }
        .onDisappear { camera.stop() }
    }

    private var startupMessage: String {
        if let setupError = camera.setupError {
            return setupError
        }
        if camera.isSessionReady && !camera.isPreviewActive {
            return "正在打开相机镜头…"
        }
        return "正在启动相机…"
    }

    private var overlayStatusMessage: String {
        if let setupError = camera.setupError {
            return setupError
        }
        if !camera.isPreviewActive {
            return startupMessage
        }
        return viewModel.statusMessage
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
            Text("请在 设置 → 卡片扫描 中开启相机访问权限")
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
