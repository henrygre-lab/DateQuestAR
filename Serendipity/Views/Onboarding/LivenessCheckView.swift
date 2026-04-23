import SwiftUI
import AVFoundation
import Combine

// MARK: - LivenessCheckView

struct LivenessCheckView: View {
    @ObservedObject var livenessDetector: LivenessDetector
    var onComplete: (UIImage?) -> Void

    @StateObject private var camera = CameraManager()
    @State private var lastCapturedImage: UIImage?

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            // Dark overlay with circular cutout
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .mask {
                    Rectangle()
                        .ignoresSafeArea()
                        .overlay {
                            Circle()
                                .frame(width: 260, height: 260)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }

            VStack(spacing: DQ.Spacing.xxl) {
                // Cancel button
                HStack {
                    Button {
                        onComplete(nil)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DQ.Colors.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Cancel liveness check")
                    .padding(.leading, DQ.Spacing.lg)
                    .padding(.top, DQ.Spacing.xl)
                    Spacer()
                }

                Spacer()

                // Face frame ring
                ZStack {
                    // Progress ring
                    Circle()
                        .stroke(DQ.Colors.surfaceElevated, lineWidth: 4)
                        .frame(width: 264, height: 264)

                    Circle()
                        .trim(from: 0, to: progressValue)
                        .stroke(DQ.Colors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 264, height: 264)
                        .rotationEffect(.degrees(-90))
                        .animation(DQ.Anim.standard, value: progressValue)
                }

                Spacer()

                // Action prompt
                promptSection
                    .padding(.bottom, DQ.Spacing.huge)
            }
        }
        .onAppear {
            camera.onFrameCaptured = { image in
                lastCapturedImage = image
                Task {
                    await livenessDetector.processFrame(image)
                    checkCompletion()
                }
            }
            camera.startSession()
        }
        .onDisappear {
            camera.stopSession()
        }
    }

    // MARK: - Subviews

    private var promptSection: some View {
        VStack(spacing: DQ.Spacing.lg) {
            // Completed actions
            HStack(spacing: DQ.Spacing.md) {
                ForEach(livenessDetector.completedActions, id: \.rawValue) { action in
                    HStack(spacing: DQ.Spacing.xxxs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DQ.Colors.success)
                        Text(actionShortName(action))
                            .font(DQ.Typography.caption())
                            .foregroundStyle(DQ.Colors.textSecondary)
                    }
                }
            }

            // Current action prompt
            if case .prompting(let action) = livenessDetector.state {
                Text(action.rawValue)
                    .font(DQ.Typography.sectionHeader())
                    .foregroundStyle(DQ.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .scale))
                    .id(action.rawValue)
            } else if case .passed = livenessDetector.state {
                Label("Liveness Confirmed", systemImage: "checkmark.circle.fill")
                    .font(DQ.Typography.sectionHeader())
                    .foregroundStyle(DQ.Colors.success)
            } else if case .failed(let msg) = livenessDetector.state {
                Text(msg)
                    .font(DQ.Typography.body())
                    .foregroundStyle(DQ.Colors.error)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, DQ.Spacing.xxl)
    }

    // MARK: - Helpers

    private var progressValue: Double {
        let total = 2.0
        let done = Double(livenessDetector.completedActions.count)
        return done / total
    }

    private func actionShortName(_ action: LivenessDetector.LivenessAction) -> String {
        switch action {
        case .turnLeft: "Turn left"
        case .turnRight: "Turn right"
        case .blink: "Blink"
        case .smile: "Smile"
        }
    }

    private func checkCompletion() {
        if livenessDetector.state == .passed {
            onComplete(lastCapturedImage)
        }
    }
}

// MARK: - Camera Manager

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var onFrameCaptured: ((UIImage) -> Void)?

    private let outputQueue = DispatchQueue(label: "com.serendipity.camera")
    private let ciContext = CIContext()
    private var frameCount = 0
    private var isConfigured = false

    func startSession() {
        guard !session.isRunning else { return }

        if !isConfigured {
            session.sessionPreset = .medium

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }

            if session.canAddInput(input) {
                session.addInput(input)
            }

            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: outputQueue)
            output.alwaysDiscardsLateVideoFrames = true

            if session.canAddOutput(output) {
                session.addOutput(output)
            }

            isConfigured = true
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stopSession() {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Process every 5th frame to avoid overwhelming Vision
        frameCount += 1
        guard frameCount % 5 == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)

        DispatchQueue.main.async { [weak self] in
            self?.onFrameCaptured?(image)
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}
