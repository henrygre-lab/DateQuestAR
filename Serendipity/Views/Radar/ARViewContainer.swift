// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] §04 — the AR session is explicitly paused on background and torn down
//     when the view goes away, rather than left to system behaviour
// [x] AR frames stay on-device — nothing is captured, stored or transmitted
// [x] No PII rendered into the scene

import SwiftUI
import ARKit
import SceneKit

// MARK: - ARViewContainer (UIViewRepresentable)

struct ARViewContainer: UIViewRepresentable {
    var onSessionStart: () -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        arView.session.delegate = context.coordinator
        arView.autoenablesDefaultLighting = true
        arView.automaticallyUpdatesLighting = true

        context.coordinator.attach(to: arView)
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    /// Stops the camera when the radar goes away. Without this the session
    /// outlives the view — SwiftUI releasing the representable does not stop an
    /// `ARSession`, it only drops the last reference that could have.
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ARCoordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> ARCoordinator {
        ARCoordinator(onSessionStart: onSessionStart)
    }
}

// MARK: - ARCoordinator

final class ARCoordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
    var onSessionStart: () -> Void

    private weak var arView: ARSCNView?
    private var sessionStarted = false
    private var observers: [NSObjectProtocol] = []

    init(onSessionStart: @escaping () -> Void) {
        self.onSessionStart = onSessionStart
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Session lifecycle
    //
    // §04: "ARKit camera sessions must terminate when the app enters the
    // background — no background camera access."
    //
    // ARKit does interrupt itself on backgrounding, so this is not closing an
    // open camera. It is the difference between the rule being *satisfied* and
    // the rule being *implemented*: the previous version relied entirely on
    // system behaviour it never named, on an app that ships `location` and
    // `bluetooth-central` background modes and so keeps running when most apps
    // would be suspended. A checklist item like this exists precisely so the
    // camera's lifetime is something the code states rather than inherits.
    //
    // The concrete gap it did have was teardown: nothing stopped the session
    // when the radar was dismissed, leaving it running until ARSCNView happened
    // to be deallocated. `dismantleUIView` now makes that deterministic.

    private static func makeConfiguration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        return config
    }

    func attach(to view: ARSCNView) {
        arView = view
        start(resetting: true)

        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.pause() },
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.start(resetting: false) }
        ]
    }

    func detach() {
        pause()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        arView = nil
    }

    /// Resets tracking on first run only. Coming back from the background keeps
    /// the existing anchors — a full reset there throws away the user's mapped
    /// surroundings for no reason.
    private func start(resetting: Bool) {
        guard let arView else { return }
        arView.session.run(
            Self.makeConfiguration(),
            options: resetting ? [.resetTracking, .removeExistingAnchors] : []
        )
    }

    private func pause() {
        arView?.session.pause()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !sessionStarted else { return }
        sessionStarted = true
        DispatchQueue.main.async { self.onSessionStart() }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        Log.ar.error("Session failed: \(error.localizedDescription)")
    }

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        // TODO: Add AR directional hints/overlays as SCNNodes
        return nil
    }
}
