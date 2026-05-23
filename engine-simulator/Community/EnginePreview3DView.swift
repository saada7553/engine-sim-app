//
//  EnginePreview3DView.swift
//  engine-simulator
//
//  A single live, non-interactive, slowly-rotating 3D view of one engine spec,
//  used in the community detail sheet. Unlike the main Engine 3D tile this is
//  read-only: no camera control, no live RPM/health/combustion — just the
//  posed assembly on a turntable. One of these exists at a time (the open
//  detail sheet), so the cost is bounded.
//

import SwiftUI
import SceneKit
#if os(macOS)
typealias _PreviewSCNRepresentable = NSViewRepresentable
#else
typealias _PreviewSCNRepresentable = UIViewRepresentable
#endif

private let turntableSecondsPerRevolution: Double = 18.0

struct EnginePreview3DView: _PreviewSCNRepresentable {
    let spec: EngineSpec

    private func makeSCNView() -> SCNView {
        let view = SCNView()
        view.scene = buildScene()
        view.allowsCameraControl = false
        view.backgroundColor = PlatformColor(Color.appBackground)
        view.antialiasingMode = .multisampling2X
        view.isPlaying = true
        view.loops = true
        return view
    }

    private func buildScene() -> SCNScene {
        let scene = EnginePreviewScene.make(spec: spec, background: PlatformColor(Color.appBackground))
        if let root = scene.rootNode.childNode(withName: EnginePreviewScene.engineRootName,
                                               recursively: false) {
            let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0,
                                          duration: turntableSecondsPerRevolution)
            root.runAction(.repeatForever(spin))
        }
        return scene
    }

#if os(macOS)
    func makeNSView(context: Context) -> SCNView { makeSCNView() }
    func updateNSView(_ nsView: SCNView, context: Context) { }
#else
    func makeUIView(context: Context) -> SCNView { makeSCNView() }
    func updateUIView(_ uiView: SCNView, context: Context) { }
#endif
}
