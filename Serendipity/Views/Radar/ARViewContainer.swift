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

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> ARCoordinator {
        ARCoordinator(onSessionStart: onSessionStart)
    }
}

// MARK: - ARCoordinator

final class ARCoordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
    var onSessionStart: () -> Void
    private var sessionStarted = false

    init(onSessionStart: @escaping () -> Void) {
        self.onSessionStart = onSessionStart
    }

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
