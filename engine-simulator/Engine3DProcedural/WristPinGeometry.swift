//
//  WristPinGeometry.swift
//  engine-simulator
//
//  Simple wrist-pin cylinder. Its axis is parallel to the crankshaft (local
//  +Y), matching the rod bearings. Origin sits at the pin center.
//

import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
        // Wrist pin: polished hardened steel — darker than rod, very shiny.
        let m = SCNMaterial()
        m.diffuse.contents = PlatformColor.calibrated(red: 0.30, green: 0.32, blue: 0.36, alpha: 1.0)
        m.metalness.contents = 0.98
        m.roughness.contents = 0.12
        m.lightingModel = .physicallyBased
        return m
    }
}
