//
//  ValveGeometry.swift
//  engine-simulator
//
//  Generic poppet valve: flat circular head at local origin, stem extending
//  along +Z (the bore axis). Closed position = node placed with head at the
//  valve seat (Z = valveSeatZ). To "open" the valve, translate it -Z by lift.
//

import SceneKit
import AppKit

private let valveHeadThicknessFactorOfBore: Double = 0.04
private let valveSegments: Int = 18

enum ValveGeometry {
    static func makeNode(params p: EngineGeometryParams) -> SCNNode {
        let node = SCNNode()
        node.name = "valve"

        // Head disc (axis = Z so rotate cylinder's Y axis → Z).
        let headThickness = p.bore * valveHeadThicknessFactorOfBore
        let head = SCNCylinder(radius: CGFloat(p.valveHeadRadius),
                               height: CGFloat(headThickness))
        head.radialSegmentCount = valveSegments
        head.firstMaterial = valveMaterial()
        let headNode = SCNNode(geometry: head)
        headNode.eulerAngles.x = .pi / 2
        headNode.position.z = CGFloat(headThickness / 2.0)
        node.addChildNode(headNode)

        // Stem extending up from the head.
        let stem = SCNCylinder(radius: CGFloat(p.valveStemRadius),
                               height: CGFloat(p.valveStemLength))
        stem.radialSegmentCount = 12
        stem.firstMaterial = valveMaterial()
        let stemNode = SCNNode(geometry: stem)
        stemNode.eulerAngles.x = .pi / 2
        stemNode.position.z = CGFloat(headThickness + p.valveStemLength / 2.0)
        node.addChildNode(stemNode)

        return node
    }

    private static func valveMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedWhite: 0.5, alpha: 1.0)
        m.metalness.contents = 0.95
        m.roughness.contents = 0.25
        m.lightingModel = .physicallyBased
        return m
    }
}
