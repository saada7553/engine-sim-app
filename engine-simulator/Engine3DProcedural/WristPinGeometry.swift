//
//  WristPinGeometry.swift
//  engine-simulator
//
//  Simple wrist-pin cylinder. Its axis is parallel to the crankshaft (local
//  +Y), matching the rod bearings. Origin sits at the pin center.
//

import SceneKit
import AppKit

private let pinSegmentCount: Int = 24

enum WristPinGeometry {
    static func makeNode(params p: EngineGeometryParams) -> SCNNode {
        let node = SCNNode()
        node.name = "wristPin"

        let pin = SCNCylinder(radius: CGFloat(p.wristPinDiameter / 2.0),
                              height: CGFloat(p.wristPinLength))
        pin.radialSegmentCount = pinSegmentCount
        pin.firstMaterial = pinMaterial()
        // SCNCylinder default axis = Y, which is the pin axis. No rotation.
        let pinNode = SCNNode(geometry: pin)
        node.addChildNode(pinNode)

        return node
    }

    private static func pinMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedWhite: 0.6, alpha: 1.0)
        m.metalness.contents = 0.95
        m.roughness.contents = 0.2
        m.lightingModel = .physicallyBased
        return m
    }
}
