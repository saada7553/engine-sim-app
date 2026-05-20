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

private let valveSegments: Int = 18

enum ValveKind {
    case intake
    case exhaust
}

enum ValveGeometry {
    static func makeNode(params p: EngineGeometryParams, kind: ValveKind) -> SCNNode {
        let node = SCNNode()
        node.name = "valve_\(kind == .intake ? "intake" : "exhaust")"

        let material = valveMaterial(for: kind)

        // Head disc (axis = Z so rotate cylinder's Y axis → Z).
        let headThickness = p.bore * valveHeadThicknessFactorOfBore
        let head = SCNCylinder(radius: CGFloat(p.valveHeadRadius),
                               height: CGFloat(headThickness))
        head.radialSegmentCount = valveSegments
        head.firstMaterial = material
        let headNode = SCNNode(geometry: head)
        headNode.eulerAngles.x = .pi / 2
        headNode.position.z = CGFloat(headThickness / 2.0)
        node.addChildNode(headNode)

        // Stem extending up from the head.
        let stem = SCNCylinder(radius: CGFloat(p.valveStemRadius),
                               height: CGFloat(p.valveStemLength))
        stem.radialSegmentCount = 12
        stem.firstMaterial = material
        let stemNode = SCNNode(geometry: stem)
        stemNode.eulerAngles.x = .pi / 2
        stemNode.position.z = CGFloat(headThickness + p.valveStemLength / 2.0)
        node.addChildNode(stemNode)

        return node
    }

    private static func valveMaterial(for kind: ValveKind) -> SCNMaterial {
        let m = SCNMaterial()
        switch kind {
        case .intake:
            // Intake: bright polished stainless.
            m.diffuse.contents = NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.86, alpha: 1.0)
            m.metalness.contents = 0.95
            m.roughness.contents = 0.20
        case .exhaust:
            // Exhaust: heat-tinted (orange/bronze) from cycling at high temperature.
            m.diffuse.contents = NSColor(calibratedRed: 0.62, green: 0.36, blue: 0.20, alpha: 1.0)
            m.metalness.contents = 0.88
            m.roughness.contents = 0.40
        }
        m.lightingModel = .physicallyBased
        return m
    }
}
