import Foundation
import Vision
import UIKit

// MARK: - LivenessDetector

@MainActor
final class LivenessDetector: ObservableObject {
    @Published var state: LivenessState = .idle
    @Published var completedActions: [LivenessAction] = []
    @Published var currentAction: LivenessAction?

    private var requiredActions: [LivenessAction] = []
    private var frameHistory: [LivenessFrameResult] = []
    private var actionStartTime: Date?
    private let actionTimeout: TimeInterval = 10

    // Thresholds for detection
    private let yawThreshold: CGFloat = 0.3         // Head turn angle
    private let blinkAspectRatio: CGFloat = 0.2      // Eye closure threshold
    private let smileThreshold: CGFloat = 0.15        // Mouth curvature delta
    private let requiredConfirmFrames = 3             // Consecutive frames to confirm

    private var confirmationCount = 0

    enum LivenessState: Equatable {
        case idle
        case prompting(LivenessAction)
        case analyzing
        case passed
        case failed(String)
    }

    enum LivenessAction: String, CaseIterable {
        case turnLeft = "Turn your head left"
        case turnRight = "Turn your head right"
        case blink = "Blink slowly"
        case smile = "Smile"
    }

    struct LivenessFrameResult {
        var hasFace: Bool
        var yaw: CGFloat?
        var leftEyeAspectRatio: CGFloat?
        var rightEyeAspectRatio: CGFloat?
        var mouthCurvature: CGFloat?
        var timestamp: Date
    }

    // MARK: - Public API

    /// Starts the liveness check by randomly selecting 2 actions.
    func start() {
        let shuffled = LivenessAction.allCases.shuffled()
        requiredActions = Array(shuffled.prefix(2))
        completedActions = []
        frameHistory = []
        confirmationCount = 0
        advanceToNextAction()
    }

    /// Processes a single camera frame for the current action.
    func processFrame(_ image: UIImage) async {
        guard case .prompting(let action) = state else { return }

        // Check timeout
        if let start = actionStartTime, Date().timeIntervalSince(start) > actionTimeout {
            state = .failed("Timed out. Please try again.")
            return
        }

        let result = await analyzeFrame(image)
        frameHistory.append(result)

        guard result.hasFace else {
            confirmationCount = 0
            return
        }

        if checkActionSatisfied(action, frame: result) {
            confirmationCount += 1
            if confirmationCount >= requiredConfirmFrames {
                completedActions.append(action)
                confirmationCount = 0
                advanceToNextAction()
            }
        } else {
            confirmationCount = 0
        }
    }

    /// Returns whether liveness was confirmed.
    func evaluateLiveness() -> Bool {
        state == .passed
    }

    // MARK: - Private

    private func advanceToNextAction() {
        let remaining = requiredActions.filter { !completedActions.contains($0) }
        if let next = remaining.first {
            currentAction = next
            actionStartTime = Date()
            state = .prompting(next)
        } else {
            currentAction = nil
            state = .passed
        }
    }

    private func checkActionSatisfied(_ action: LivenessAction, frame: LivenessFrameResult) -> Bool {
        switch action {
        case .turnLeft:
            guard let yaw = frame.yaw else { return false }
            return yaw > yawThreshold  // Positive yaw = turned left

        case .turnRight:
            guard let yaw = frame.yaw else { return false }
            return yaw < -yawThreshold  // Negative yaw = turned right

        case .blink:
            guard let leftEAR = frame.leftEyeAspectRatio,
                  let rightEAR = frame.rightEyeAspectRatio else { return false }
            let avgEAR = (leftEAR + rightEAR) / 2.0
            return avgEAR < blinkAspectRatio

        case .smile:
            guard let curvature = frame.mouthCurvature else { return false }
            return curvature > smileThreshold
        }
    }

    private func analyzeFrame(_ image: UIImage) async -> LivenessFrameResult {
        guard let cgImage = image.cgImage else {
            return LivenessFrameResult(hasFace: false, timestamp: Date())
        }

        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceLandmarksRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNFaceObservation],
                      let face = observations.first else {
                    continuation.resume(returning: LivenessFrameResult(hasFace: false, timestamp: Date()))
                    return
                }

                let yaw = face.yaw?.cgFloatValue

                var leftEAR: CGFloat?
                var rightEAR: CGFloat?
                var mouthCurvature: CGFloat?

                if let landmarks = face.landmarks {
                    leftEAR = self.eyeAspectRatio(landmarks.leftEye)
                    rightEAR = self.eyeAspectRatio(landmarks.rightEye)
                    mouthCurvature = self.computeMouthCurvature(
                        innerLips: landmarks.innerLips,
                        outerLips: landmarks.outerLips
                    )
                }

                continuation.resume(returning: LivenessFrameResult(
                    hasFace: true,
                    yaw: yaw,
                    leftEyeAspectRatio: leftEAR,
                    rightEyeAspectRatio: rightEAR,
                    mouthCurvature: mouthCurvature,
                    timestamp: Date()
                ))
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Landmark Geometry

    /// Extracts CGPoints from a Vision landmark region's normalized points buffer.
    private func points(from region: VNFaceLandmarkRegion2D) -> [CGPoint] {
        let buffer = region.normalizedPoints
        return (0..<region.pointCount).map { i in
            CGPoint(x: CGFloat(buffer[i].x), y: CGFloat(buffer[i].y))
        }
    }

    /// Computes eye aspect ratio (height / width). Low values = closed eye.
    private func eyeAspectRatio(_ eye: VNFaceLandmarkRegion2D?) -> CGFloat? {
        guard let eye = eye, eye.pointCount >= 6 else { return nil }
        let pts = points(from: eye)
        let xs = pts.map(\.x)
        let ys = pts.map(\.y)
        let width = (xs.max() ?? 0) - (xs.min() ?? 0)
        let height = (ys.max() ?? 0) - (ys.min() ?? 0)
        guard width > 0 else { return nil }
        return height / width
    }

    /// Computes smile curvature from lip landmarks. Higher = wider smile.
    private func computeMouthCurvature(
        innerLips: VNFaceLandmarkRegion2D?,
        outerLips: VNFaceLandmarkRegion2D?
    ) -> CGFloat? {
        guard let outer = outerLips, outer.pointCount >= 6 else { return nil }
        let pts = points(from: outer)
        let xs = pts.map(\.x)
        let ys = pts.map(\.y)
        let width = (xs.max() ?? 0) - (xs.min() ?? 0)
        let height = (ys.max() ?? 0) - (ys.min() ?? 0)
        guard height > 0 else { return nil }
        // Width-to-height ratio increases with smiling
        return width / height
    }
}

// MARK: - Helpers

private extension NSNumber {
    var cgFloatValue: CGFloat {
        CGFloat(doubleValue)
    }
}
