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
private let pinBossWidthFactor: Double = 0.25
private let skirtBelowPinFactorOfBore: Double = 0.40
private let pistonSegmentCount: Int = 48

enum PistonGeometry {
    static func makeNode(params p: EngineGeometryParams) -> SCNNode {
        let node = SCNNode()
        node.name = "piston"

        let radius = CGFloat(p.bore / 2.0)
        let crownThickness = CGFloat(p.bore * crownThicknessFactorOfBore)
        let ringLandHeight = CGFloat(p.bore * ringLandHeightFactor)
        let ringSpacing = CGFloat(p.bore * ringSpacingFactor)

        // Wrist-pin sits at local origin. The piston crown must land exactly at
        // z = compressionHeight above the wrist pin so that at TDC the crown is
        // flush with the deck (= crankThrow + rodLength + compressionHeight).
        // Skirt drops below the wrist pin by a fixed fraction of bore.
        let crownTopZ = CGFloat(p.compressionHeight)
        let skirtBottomZ = CGFloat(-p.bore * skirtBelowPinFactorOfBore)
        let bodyHeight = crownTopZ - crownThickness - skirtBottomZ
        let bodyCenterZ = skirtBottomZ + bodyHeight / 2.0

        // Body: main cylinder running along Z, from skirt to bottom of crown.
        let bodyCyl = SCNCylinder(radius: radius * 0.99, height: bodyHeight)
        bodyCyl.radialSegmentCount = pistonSegmentCount
        bodyCyl.firstMaterial = pistonMaterial()
        let body = SCNNode(geometry: bodyCyl)
        body.eulerAngles.x = .pi / 2
        body.position.z = bodyCenterZ
        node.addChildNode(body)

        // Crown disc sits atop the body, top face at compressionHeight.
        let crown = SCNCylinder(radius: radius, height: crownThickness)
        crown.radialSegmentCount = pistonSegmentCount
        crown.firstMaterial = pistonMaterial()
        let crownNode = SCNNode(geometry: crown)
        crownNode.eulerAngles.x = .pi / 2
        crownNode.position.z = crownTopZ - crownThickness / 2
        node.addChildNode(crownNode)

        // Ring grooves descend from just below the crown.
        let firstRingZ: CGFloat = crownNode.position.z - crownThickness / 2 - ringSpacing
        let ringStride: CGFloat = ringSpacing + ringLandHeight
        for i in 0..<ringCount {
            let zPos: CGFloat = firstRingZ - CGFloat(i) * ringStride
            // Don't draw rings that would land below the body envelope.
            if zPos < skirtBottomZ + ringLandHeight { break }
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
            bossNode.position.y = CGFloat(side) * (radius * 0.65)
            node.addChildNode(bossNode)
        }

        return node
    }

    private static func pistonMaterial() -> SCNMaterial {
        // Piston: light cast aluminum, slightly warm.
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedRed: 0.88, green: 0.86, blue: 0.82, alpha: 1.0)
        m.metalness.contents = 0.78
        m.roughness.contents = 0.40
        m.lightingModel = .physicallyBased
        return m
    }

    private static func ringGrooveMaterial() -> SCNMaterial {
        // Ring grooves: dark, almost black (carbon-coated cast iron rings).
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedRed: 0.14, green: 0.13, blue: 0.13, alpha: 1.0)
        m.metalness.contents = 0.55
        m.roughness.contents = 0.62
        m.lightingModel = .physicallyBased
        return m
    }

    private static func pistonInternalMaterial() -> SCNMaterial {
        // Boss material: darker aluminum cast.
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedRed: 0.60, green: 0.58, blue: 0.55, alpha: 1.0)
        m.metalness.contents = 0.70
        m.roughness.contents = 0.50
        m.lightingModel = .physicallyBased
        return m
    }
}
