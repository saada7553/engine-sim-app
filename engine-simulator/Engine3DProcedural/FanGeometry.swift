//
//  FanGeometry.swift
//  engine-simulator
//
//  Decorative cooling fan that sits at the front of the engine and spins with
//  the crankshaft. The fan is built as a child of the crankshaft node so it
//  inherits the crank's rotation for free — no extra animation wiring needed.
//
//  A short steel shaft extends from inside the existing crank snout to the
//  back of the fan hub, so the fan reads as physically bolted to the crank
//  instead of floating in front of the block.
//

import SceneKit
import AppKit

private let fanBladeCount: Int = 5
private let fanHubRadiusFactorOfBore: Double = 0.22
private let fanHubThicknessFactorOfBore: Double = 0.16
private let fanBladeThicknessFactorOfBore: Double = 0.035
// Smaller than before — the fan should accent the front of the engine, not
// dominate the silhouette.
private let fanRadiusBoreFactor: Double = 1.15
private let fanRadiusRodFactor: Double = 0.38
/// Distance in bore-units the fan stands proud of the block's front face.
private let fanClearOfBlockFactorOfBore: Double = 0.30
private let fanBladePitchDeg: Double = 18.0
private let fanAlpha: CGFloat = 0.55
// Chord widths along the blade span (root → tip), expressed in bore units.
private let fanBladeChordAtRootFactor: Double = 0.10
private let fanBladeChordAtMidFactor: Double = 0.34
private let fanBladeChordAtTipFactor: Double = 0.12
/// Leading-edge sweep at the tip, bore units. Gives a propeller silhouette.
private let fanBladeSweepAtTipFactor: Double = 0.14
// Shaft that bridges crank snout → fan hub. Made fatter than the snout so the
// joint reads as a solid coupling.
private let fanShaftRadiusFactorOfBore: Double = 0.10
/// How far back (toward the engine, +local-Y) the shaft sticks past the fan
/// hub. This overlap with the existing crank snout guarantees visual contact
/// even when block proportions change. Bore units.
private let fanShaftRearOverlapFactorOfBore: Double = 0.55

enum FanGeometry {
    /// Builds and attaches the fan as a child of the supplied crankshaft node
    /// so the fan rotates in lockstep with the crank.
    static func attach(to crankNode: SCNNode, params p: EngineGeometryParams) {
        // Block centered at Y=0 with extent blockLength → front face at
        // -blockLength/2. Push the fan past that by a bore-relative margin
        // so the blades never clip into the case.
        let fanY = -p.blockLength / 2.0 - p.bore * fanClearOfBlockFactorOfBore

        let fanRoot = SCNNode()
        fanRoot.name = "crankshaftFan"
        fanRoot.position.y = CGFloat(fanY)
        crankNode.addChildNode(fanRoot)

        let hubRadius = p.bore * fanHubRadiusFactorOfBore
        let hubThickness = p.bore * fanHubThicknessFactorOfBore
        let outerRadius = max(p.bore * fanRadiusBoreFactor,
                              p.rodLength * fanRadiusRodFactor)
        let bladeLength = max(outerRadius - hubRadius, p.bore * 0.5)
        let bladeThickness = p.bore * fanBladeThicknessFactorOfBore

        // Shaft from inside the existing crank snout out to the back face of
        // the hub. Anything from the hub back into +Y reaches the snout.
        let shaftRearY = hubThickness / 2.0
                       + p.bore * fanShaftRearOverlapFactorOfBore
        addShaft(to: fanRoot,
                 startLocalY: shaftRearY,
                 endLocalY: 0.0,
                 radius: p.bore * fanShaftRadiusFactorOfBore)

        addHub(to: fanRoot, radius: hubRadius, thickness: hubThickness)

        for i in 0..<fanBladeCount {
            let angle = Double(i) * (2.0 * .pi / Double(fanBladeCount))
            addBlade(to: fanRoot,
                     angleRad: angle,
                     hubRadius: hubRadius,
                     bladeLength: bladeLength,
                     bladeThickness: bladeThickness,
                     bore: p.bore)
        }
    }

    private static func addShaft(to parent: SCNNode,
                                 startLocalY: Double,
                                 endLocalY: Double,
                                 radius: Double) {
        let length = abs(startLocalY - endLocalY)
        guard length > 0 else { return }
        let cyl = SCNCylinder(radius: CGFloat(radius), height: CGFloat(length))
        cyl.radialSegmentCount = 24
        cyl.firstMaterial = shaftMaterial()
        let node = SCNNode(geometry: cyl)
        node.position.y = CGFloat((startLocalY + endLocalY) / 2.0)
        parent.addChildNode(node)
    }

    private static func addHub(to parent: SCNNode,
                               radius: Double,
                               thickness: Double) {
        let hub = SCNCylinder(radius: CGFloat(radius), height: CGFloat(thickness))
        hub.radialSegmentCount = 28
        hub.firstMaterial = fanMaterial()
        let hubNode = SCNNode(geometry: hub)
        parent.addChildNode(hubNode)
    }

    /// Builds one blade: a swept airfoil silhouette extruded for thickness,
    /// then rotated to lie in the fan plane (XZ) and pitched for angle of
    /// attack. Each blade is parented to a pivot rotated around the crank
    /// (Y) axis so all blades share the same hub.
    private static func addBlade(to parent: SCNNode,
                                 angleRad: Double,
                                 hubRadius: Double,
                                 bladeLength: Double,
                                 bladeThickness: Double,
                                 bore: Double) {
        let path = bladeProfilePath(bladeLength: bladeLength, bore: bore)
        let shape = SCNShape(path: path, extrusionDepth: CGFloat(bladeThickness))
        shape.firstMaterial = fanMaterial()

        let bladeNode = SCNNode(geometry: shape)
        // The 2D path is drawn in XY (X = radial, Y = chord). SCNShape extrudes
        // along +Z. Rotating -90° around X swings Y→Z (chord into the fan
        // plane) and Z→-Y (thickness out of the fan plane). Then we tilt by
        // the pitch angle around the radial (X) axis for angle of attack.
        bladeNode.eulerAngles.x = CGFloat(-(.pi / 2.0) + fanBladePitchDeg * .pi / 180.0)
        bladeNode.position = SCNVector3(Float(hubRadius), 0, 0)

        let pivot = SCNNode()
        pivot.eulerAngles.y = CGFloat(angleRad)
        pivot.addChildNode(bladeNode)
        parent.addChildNode(pivot)
    }

    /// Builds the blade silhouette in path-local XY space:
    ///   x ∈ [0, bladeLength] is the radial span (0 = root, length = tip)
    ///   y is the chord, with a slight backward sweep at the tip.
    private static func bladeProfilePath(bladeLength: Double,
                                         bore: Double) -> NSBezierPath {
        let rootHalf = bore * fanBladeChordAtRootFactor
        let midHalf = bore * fanBladeChordAtMidFactor
        let tipHalf = bore * fanBladeChordAtTipFactor
        let sweep = bore * fanBladeSweepAtTipFactor

        let xRoot = 0.0
        let xMid = bladeLength * 0.55
        let xTip = bladeLength

        let path = NSBezierPath()
        path.move(to: NSPoint(x: xRoot, y: -rootHalf))
        path.curve(to: NSPoint(x: xMid, y: -midHalf),
                   controlPoint1: NSPoint(x: bladeLength * 0.18, y: -rootHalf),
                   controlPoint2: NSPoint(x: bladeLength * 0.40, y: -midHalf))
        path.curve(to: NSPoint(x: xTip, y: -tipHalf - sweep * 0.4),
                   controlPoint1: NSPoint(x: bladeLength * 0.75, y: -midHalf * 0.95),
                   controlPoint2: NSPoint(x: bladeLength * 0.92, y: -tipHalf - sweep * 0.6))
        path.curve(to: NSPoint(x: xTip, y: tipHalf - sweep),
                   controlPoint1: NSPoint(x: bladeLength + tipHalf * 0.6, y: -tipHalf - sweep),
                   controlPoint2: NSPoint(x: bladeLength + tipHalf * 0.6, y: tipHalf - sweep))
        path.curve(to: NSPoint(x: xMid, y: midHalf),
                   controlPoint1: NSPoint(x: bladeLength * 0.92, y: tipHalf - sweep * 0.4),
                   controlPoint2: NSPoint(x: bladeLength * 0.75, y: midHalf * 1.05))
        path.curve(to: NSPoint(x: xRoot, y: rootHalf),
                   controlPoint1: NSPoint(x: bladeLength * 0.40, y: midHalf),
                   controlPoint2: NSPoint(x: bladeLength * 0.18, y: rootHalf))
        path.close()
        path.flatness = 0.001
        return path
    }

    private static func fanMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        // Muted steel-teal — interesting but mechanical, doesn't fight the
        // crank/piston colors for attention the way a saturated pink would.
        let color = NSColor(calibratedRed: 0.38, green: 0.58, blue: 0.66,
                            alpha: fanAlpha)
        m.diffuse.contents = color
        m.transparency = fanAlpha
        m.isDoubleSided = true
        m.metalness.contents = 0.35
        m.roughness.contents = 0.45
        m.lightingModel = .physicallyBased
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        return m
    }

    /// Opaque steel for the coupling shaft — matches the crank's look so the
    /// joint reads as a continuous piece of hardware.
    private static func shaftMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedRed: 0.40, green: 0.42, blue: 0.46,
                                     alpha: 1.0)
        m.metalness.contents = 0.95
        m.roughness.contents = 0.32
        m.lightingModel = .physicallyBased
        return m
    }
}
