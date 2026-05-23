//
//  EnginePreviewScene.swift
//  engine-simulator
//
//  Builds a self-contained, statically-posed SceneKit scene for an EngineSpec:
//  the procedural assembly, the standard light rig, and a framed camera. Shared
//  by the off-screen thumbnail renderer (EnginePreviewRenderer) and the live
//  rotating detail view (EnginePreview3DView) so both frame and light an engine
//  exactly like the main Engine 3D tile — no duplicated geometry/camera math.
//

import SceneKit

enum EnginePreviewScene {
    static let engineRootName = "previewEngineRoot"

    /// A ready-to-render scene for `spec`. The assembly is posed at crank
    /// angle 0 (no animation, no combustion glow, no damage tint) and the
    /// camera is framed with the same math the live tile uses.
    static func make(spec: EngineSpec, background: PlatformColor) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = background

        Engine3DProceduralView.addStandardLights(to: scene)

        let parts = ProceduralEngineAssembly.build(spec: spec)
        let root = SCNNode()
        root.name = engineRootName
        root.addChildNode(parts.assemblyNode)
        scene.rootNode.addChildNode(root)

        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.005
        cameraNode.camera?.zFar = 50.0
        scene.rootNode.addChildNode(cameraNode)
        Engine3DProceduralView.placeCameraStatic(cameraNode, params: parts.params)

        return scene
    }
}
