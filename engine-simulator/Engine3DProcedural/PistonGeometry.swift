//
//  PistonGeometry.swift
//  engine-simulator
//
//  Procedural piston model. One factory; cloned per cylinder by the assembly.
//  Local coordinates: bore axis = +Z, wrist-pin axis = X.
//  Origin sits at the wrist-pin center so the slider-crank loop can place the
//  piston by setting its position equal to the wrist-pin height.
//

import SceneKit
import AppKit

private let crownThicknessFactorOfBore: Double = 0.12
private let ringLandHeightFactor: Double = 0.06
private let ringCount: Int = 3
private let ringSpacingFactor: Double = 0.08
private let skirtThicknessFactor: Double = 0.04
private let pinBossWidthFactor: Double = 0.25
private let pistonSegmentCount: Int = 48

enum PistonGeometry {
    static func makeNode(params p: EngineGeometryParams) -> SCNNode {
        let node = SCNNode()
        node.name = "piston"

        let radius = CGFloat(p.bore / 2.0)
        let height = CGFloat(p.pistonHeight)
        let crownThickness = CGFloat(p.bore * crownThicknessFactorOfBore)
        let ringLandHeight = CGFloat(p.bore * ringLandHeightFactor)
        let ringSpacing = CGFloat(p.bore * ringSpacingFactor)

        // Wrist-pin sits at local origin; crown is above (+Z), skirt below.
        // Body: main cylinder running along Z.
        let bodyCyl = SCNCylinder(radius: radius * 0.99, height: height)
        bodyCyl.radialSegmentCount = pistonSegmentCount
        bodyCyl.firstMaterial = pistonMaterial()
        let body = SCNNode(geometry: bodyCyl)
        // SCNCylinder is axis-aligned to Y; rotate so its axis lies along Z.
        body.eulerAngles.x = .pi / 2
        // Center of body sits a bit above wrist-pin (more crown than skirt).
        body.position.z = CGFloat(p.pistonHeight) * 0.15
        node.addChildNode(body)

        // Crown disc (slightly inset top).
        let crown = SCNCylinder(radius: radius, height: crownThickness)
        crown.radialSegmentCount = pistonSegmentCount
        crown.firstMaterial = pistonMaterial()
        let crownNode = SCNNode(geometry: crown)
        crownNode.eulerAngles.x = .pi / 2
        crownNode.position.z = body.position.z + height / 2 + crownThickness / 2
        node.addChildNode(crownNode)

        // Compression / oil ring grooves rendered as thin dark tori around the body.
        let firstRingZ: CGFloat = crownNode.position.z - crownThickness / 2 - ringSpacing
        let ringStride: CGFloat = ringSpacing + ringLandHeight
        for i in 0..<ringCount {
            let zPos: CGFloat = firstRingZ - CGFloat(i) * ringStride
            let ring = SCNTorus(ringRadius: radius * 0.97, pipeRadius: ringLandHeight / 2)
            ring.ringSegmentCount = pistonSegmentCount
            ring.pipeSegmentCount = 12
            ring.firstMaterial = ringGrooveMaterial()
            let ringNode = SCNNode(geometry: ring)
            ringNode.eulerAngles.x = .pi / 2
            ringNode.position.z = zPos
            node.addChildNode(ringNode)
        }

        // Wrist-pin bosses: stubby cylinders along Y (the pin axis), sitting at
        // ±Y inside the piston so the wrist pin can pass through them.
        let bossLength = CGFloat(p.bore * pinBossWidthFactor)
        let bossRadius = CGFloat(p.wristPinDiameter * 0.8)
        let boss = SCNCylinder(radius: bossRadius, height: bossLength)
        boss.radialSegmentCount = 24
        boss.firstMaterial = pistonInternalMaterial()
        for side in [-1.0, 1.0] {
            let bossNode = SCNNode(geometry: boss)
            // Default cylinder axis = Y, which is already the pin direction.
            bossNode.position.y = CGFloat(side) * (radius * 0.65)
            node.addChildNode(bossNode)
        }

        _ = skirtThicknessFactor  // reserved for future skirt detail; kept for documentation
        return node
    }

    private static func pistonMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedWhite: 0.78, alpha: 1.0)
        m.metalness.contents = 0.85
        m.roughness.contents = 0.35
        m.lightingModel = .physicallyBased
        return m
    }

    private static func ringGrooveMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedWhite: 0.2, alpha: 1.0)
        m.metalness.contents = 0.6
        m.roughness.contents = 0.6
        m.lightingModel = .physicallyBased
        return m
    }

    private static func pistonInternalMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedWhite: 0.55, alpha: 1.0)
        m.metalness.contents = 0.7
        m.roughness.contents = 0.5
        m.lightingModel = .physicallyBased
        return m
    }
}
