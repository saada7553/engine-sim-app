//
//  CylinderHeadGeometry.swift
//  engine-simulator
//
//  Translucent cylinder head, one per bank. Sits directly on top of the bank
//  slab in the bank-local frame and is rotated by the bank's pivot so V/Flat
//  engines have splayed heads.
//

import SceneKit
import AppKit

private let headAlpha: CGFloat = 0.04
private let chamferFactorOfBore: Double = 0.06

enum CylinderHeadGeometry {
    static func makeNode(params p: EngineGeometryParams) -> SCNNode {
        let node = SCNNode()
        node.name = "cylinderHead"

        let box = SCNBox(width: CGFloat(p.headHalfWidth * 2.0),
                         height: CGFloat(p.bankSlabLength),
                         length: CGFloat(p.headHeight),
                         chamferRadius: CGFloat(p.bore * chamferFactorOfBore))
        box.firstMaterial = headMaterial()

        let n = SCNNode(geometry: box)
        n.position = SCNVector3(0, 0, Float((p.headTopZ + p.headBottomZ) / 2.0))
        node.addChildNode(n)

        return node
    }

    private static func headMaterial() -> SCNMaterial {
        // Head: lighter aluminum cast (vs. iron block), still translucent.
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedRed: 0.72, green: 0.70, blue: 0.66, alpha: headAlpha)
        m.transparency = headAlpha
        m.isDoubleSided = true
        m.metalness.contents = 0.18
        m.roughness.contents = 0.70
        m.lightingModel = .physicallyBased
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        return m
    }
}
