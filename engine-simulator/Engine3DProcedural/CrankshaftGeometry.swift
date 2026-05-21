//
//  CrankshaftGeometry.swift
//  engine-simulator
//
//  Procedural crankshaft. One throw per cylinder (split-pin design): each
//  cylinder gets its own pin and pair of fan/kidney-shaped webs at the
//  cylinder's own phase angle, positioned at the cylinder's yOffset.
//  V/Flat engines pack two such throws side-by-side on each slot (one per
//  bank), with the inner webs meeting at the slot center.
//
//  Each web is built as an extruded SCNGeometry (same construction style as
//  the cam lobe). The web outline is the convex hull of two circles in the
//  X-Z plane: a pin-side boss around the rod pin (small) and a counterweight
//  tip opposite (large), joined by external common tangents.
//

import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

private let mainJournalSegmentCount: Int = 24
private let rodPinSegmentCount: Int = 20
private let webBigArcSamples: Int = 56
private let webSmallArcSamples: Int = 24
private let webTangentSamples: Int = 6
private let snoutLengthFactorOfBore: Double = 0.5
private let mainJournalEndPadFactorOfBore: Double = 0.4
private let frontSnoutRadiusBoost: Double = 1.2
private let rearSnoutRadiusBoost: Double = 1.4
private let pinOverlapIntoWebFactor: Double = 0.3  // × webPlateThickness
private let pinPolishedRoughness: Double = 0.18

enum CrankshaftGeometry {
    static func makeNode(params p: EngineGeometryParams) -> SCNNode {
        let node = SCNNode()
        node.name = "crankshaft"

        // One throw per cylinder, sorted along the crank axis. Each throw
        // carries its own pin (at the cylinder's phase) and two webs flanking
        // the rod-bearing region. For V/Flat engines, the two cylinders on a
        // slot end up with their inner webs touching at the slot center.
        let throws_ = p.cylinders.map { (y: $0.yOffset, angleRad: $0.phaseOffsetRad) }
                                  .sorted(by: { $0.y < $1.y })
        guard let firstThrowY = throws_.first?.y,
              let lastThrowY = throws_.last?.y else { return node }

        let mainRadius = p.mainJournalDiameter / 2.0
        let endPad = p.bore * mainJournalEndPadFactorOfBore
        let snoutLen = p.bore * snoutLengthFactorOfBore
        let webHalfSpan = p.crankWebCenterOffset + p.crankWebPlateThickness / 2.0

        // Front snout (input side).
        let frontSnoutStart = firstThrowY - endPad - snoutLen
        let frontSnoutEnd = firstThrowY - endPad
        addMainJournal(to: node, fromY: frontSnoutStart, toY: frontSnoutEnd,
                       radius: mainRadius * frontSnoutRadiusBoost)
        addMainJournal(to: node, fromY: frontSnoutEnd,
                       toY: firstThrowY - webHalfSpan,
                       radius: mainRadius)

        for (i, t) in throws_.enumerated() {
            addThrow(to: node, slotY: t.y, throwAngleRad: t.angleRad, params: p)

            // Main journal between this throw and the next. For V/Flat engines
            // the two paired throws within a slot overlap in Y, so the journal
            // segment ends up zero-length and addMainJournal skips it.
            let nextStart: Double
            if i + 1 < throws_.count {
                nextStart = throws_[i + 1].y - webHalfSpan
            } else {
                nextStart = lastThrowY + endPad
            }
            let thisEnd = t.y + webHalfSpan
            addMainJournal(to: node, fromY: thisEnd, toY: nextStart, radius: mainRadius)
        }

        // Rear snout + flywheel flange.
        let rearSnoutStart = lastThrowY + endPad
        let rearSnoutEnd = rearSnoutStart + snoutLen * rearSnoutRadiusBoost
        addMainJournal(to: node, fromY: rearSnoutStart, toY: rearSnoutEnd,
                       radius: mainRadius * rearSnoutRadiusBoost)

        let flangeR = p.counterweightReach * 0.85
        let flangeT = p.crankWebPlateThickness * 1.2
        let flange = SCNCylinder(radius: CGFloat(flangeR), height: CGFloat(flangeT))
        flange.radialSegmentCount = mainJournalSegmentCount
        flange.firstMaterial = steelMaterial()
        let flangeNode = SCNNode(geometry: flange)
        flangeNode.position.y = SCNFloat(rearSnoutEnd + flangeT / 2.0)
        node.addChildNode(flangeNode)

        return node
    }

    // MARK: - Main journal

    private static func addMainJournal(to parent: SCNNode,
                                       fromY: Double,
                                       toY: Double,
                                       radius: Double) {
        let length = toY - fromY
        guard length > 0.0005 else { return }
        let cyl = SCNCylinder(radius: CGFloat(radius), height: CGFloat(length))
        cyl.radialSegmentCount = mainJournalSegmentCount
        cyl.firstMaterial = steelMaterial()
        let cylNode = SCNNode(geometry: cyl)
        cylNode.position.y = SCNFloat((fromY + toY) / 2.0)
        parent.addChildNode(cylNode)
    }

    // MARK: - One throw (pin + two webs)

    private static func addThrow(to parent: SCNNode,
                                 slotY: Double,
                                 throwAngleRad: Double,
                                 params p: EngineGeometryParams) {
        let throwR = p.crankThrow
        let pinX = throwR * sin(throwAngleRad)
        let pinZ = throwR * cos(throwAngleRad)

        // Rod pin runs across the throw between the two webs and pushes a bit
        // into each web so the join reads as solid material.
        let webInnerHalf = p.rodSpanHalf
        let webOverlap = p.crankWebPlateThickness * pinOverlapIntoWebFactor
        let pinLength = 2.0 * (webInnerHalf + webOverlap)
        let pin = SCNCylinder(radius: CGFloat(p.crankPinDiameter / 2.0),
                              height: CGFloat(pinLength))
        pin.radialSegmentCount = rodPinSegmentCount
        pin.firstMaterial = pinMaterial()
        let pinNode = SCNNode(geometry: pin)
        pinNode.position = SCNVector3(Float(pinX), Float(slotY), Float(pinZ))
        parent.addChildNode(pinNode)

        // Two webs flanking the rod-bearing region.
        for side: Double in [-1.0, +1.0] {
            let webY = slotY + side * p.crankWebCenterOffset
            let web = makeWebNode(params: p, throwAngleRad: throwAngleRad)
            web.position.y = SCNFloat(webY)
            parent.addChildNode(web)
        }
    }

    // MARK: - Fan-shaped web geometry

    private static func makeWebNode(params p: EngineGeometryParams,
                                    throwAngleRad: Double) -> SCNNode {
        // Outline in throw-local (X, Z): pin direction = +X, counterweight tip = -X.
        let contour = buildWebContour(throwR: p.crankThrow,
                                      pinBossR: p.crankPinBossRadius,
                                      cwOffset: p.counterweightTipOffset,
                                      cwR: p.counterweightTipRadius)
        let geo = extrudeContour(contour: contour, thickness: p.crankWebPlateThickness)
        geo.firstMaterial = steelMaterial()
        let node = SCNNode(geometry: geo)
        // The pin sits at (throwR·sin(angle), throwR·cos(angle)) — i.e., at
        // atan2-angle (π/2 − throwAngleRad). To align the contour's +X feature
        // with the pin under SceneKit's CW-positive Y rotation, rotate by
        // (throwAngleRad − π/2). Inline cyl 1 (throwAngleRad = 0) then places
        // the web's pin boss directly above the crank center at +Z, matching
        // the pin's initial location.
        node.eulerAngles.y = SCNFloat(throwAngleRad - .pi / 2)
        return node
    }

    /// Counter-clockwise contour (viewed from +Y) wrapping two circles:
    ///   pin boss at (+throwR, 0) with radius pinBossR (small)
    ///   counterweight tip at (-cwOffset, 0) with radius cwR (large)
    /// joined by external common tangents above and below.
    private static func buildWebContour(throwR: Double,
                                        pinBossR: Double,
                                        cwOffset: Double,
                                        cwR: Double) -> [SIMD2<Float>] {
        let centerSeparation = throwR + cwOffset
        let radiusDelta = cwR - pinBossR
        let tangentSpan = sqrt(max(centerSeparation * centerSeparation
                                   - radiusDelta * radiusDelta, 1e-9))
        // Slope of the UPPER external tangent (downward-going from cw to pin).
        let tangentSlope = -radiusDelta / tangentSpan
        let invSqrt = 1.0 / sqrt(tangentSlope * tangentSlope + 1.0)
        // Outward-normal direction at upper tangent points (perpendicular to
        // the tangent line, pointing into +Z half-plane).
        let normalX = -tangentSlope * invSqrt
        let normalZ = invSqrt

        let pinCenter = SIMD2<Double>(throwR, 0)
        let cwCenter = SIMD2<Double>(-cwOffset, 0)

        // Tangent points on each circle, upper (z > 0) and lower (z < 0).
        let pinUp = pinCenter + SIMD2<Double>(pinBossR * normalX, pinBossR * normalZ)
        let pinDn = pinCenter + SIMD2<Double>(pinBossR * normalX, -pinBossR * normalZ)
        let cwUp = cwCenter + SIMD2<Double>(cwR * normalX, cwR * normalZ)
        let cwDn = cwCenter + SIMD2<Double>(cwR * normalX, -cwR * normalZ)

        // Angles (from each circle's center) of the tangent points.
        let thetaPin = atan2(pinBossR * normalZ, pinBossR * normalX)  // ∈ (0, π/2)
        let thetaCw = atan2(cwR * normalZ, cwR * normalX)             // ∈ (0, π/2)

        var contour: [SIMD2<Float>] = []
        contour.reserveCapacity(webBigArcSamples + webSmallArcSamples + 2 * webTangentSamples)

        // 1) Big arc around counterweight: CCW from cwUp (angle thetaCw) all the
        //    way around the -X side to cwDn (angle 2π - thetaCw).
        let bigSweep = 2.0 * .pi - 2.0 * thetaCw
        for i in 0..<webBigArcSamples {
            let t = Double(i) / Double(webBigArcSamples)
            let a = thetaCw + t * bigSweep
            let p2 = cwCenter + SIMD2<Double>(cwR * cos(a), cwR * sin(a))
            contour.append(SIMD2<Float>(Float(p2.x), Float(p2.y)))
        }

        // 2) Lower tangent: straight line from cwDn to pinDn (+X direction).
        for i in 0..<webTangentSamples {
            let t = Double(i) / Double(webTangentSamples)
            let p2 = cwDn + t * (pinDn - cwDn)
            contour.append(SIMD2<Float>(Float(p2.x), Float(p2.y)))
        }

        // 3) Small arc around pin: CCW from pinDn (angle -thetaPin) through the
        //    +X side to pinUp (angle +thetaPin).
        let smallSweep = 2.0 * thetaPin
        for i in 0..<webSmallArcSamples {
            let t = Double(i) / Double(webSmallArcSamples)
            let a = -thetaPin + t * smallSweep
            let p2 = pinCenter + SIMD2<Double>(pinBossR * cos(a), pinBossR * sin(a))
            contour.append(SIMD2<Float>(Float(p2.x), Float(p2.y)))
        }

        // 4) Upper tangent: straight line from pinUp back to cwUp (-X direction).
        for i in 0..<webTangentSamples {
            let t = Double(i) / Double(webTangentSamples)
            let p2 = pinUp + t * (cwUp - pinUp)
            contour.append(SIMD2<Float>(Float(p2.x), Float(p2.y)))
        }

        return contour
    }

    /// Extrudes a CCW (X, Z)-plane contour into a 3D slab along Y. Builds back
    /// cap (Y = -t/2), front cap (Y = +t/2), and a side wall with radial
    /// outward normals. Mirrors the construction used for the cam lobe.
    private static func extrudeContour(contour: [SIMD2<Float>], thickness: Double) -> SCNGeometry {
        let n = contour.count
        precondition(n >= 3, "Contour needs at least 3 points")
        let backY = Float(-thickness / 2.0)
        let frontY = Float(thickness / 2.0)

        var verts: [SCNVector3] = []
        var normals: [SCNVector3] = []
        verts.reserveCapacity(n * 4 + 2)
        normals.reserveCapacity(n * 4 + 2)

        // Back-cap ring (normal -Y).
        for p2 in contour {
            verts.append(SCNVector3(p2.x, backY, p2.y))
            normals.append(SCNVector3(0, -1, 0))
        }
        // Front-cap ring (normal +Y).
        for p2 in contour {
            verts.append(SCNVector3(p2.x, frontY, p2.y))
            normals.append(SCNVector3(0, 1, 0))
        }
        let backCenterIndex = verts.count
        verts.append(SCNVector3(0, backY, 0))
        normals.append(SCNVector3(0, -1, 0))
        let frontCenterIndex = verts.count
        verts.append(SCNVector3(0, frontY, 0))
        normals.append(SCNVector3(0, 1, 0))

        // Side-wall vertices with their own outward radial normals.
        let sideStartIndex = verts.count
        for i in 0..<n {
            let p2 = contour[i]
            let next = contour[(i + 1) % n]
            let tx = next.x - p2.x
            let tz = next.y - p2.y
            // CCW contour → outward normal is tangent rotated by -90° around Y.
            let nx = tz
            let nz = -tx
            let len = max(sqrt(nx * nx + nz * nz), 1e-6)
            let nrm = SCNVector3(nx / len, 0, nz / len)
            verts.append(SCNVector3(p2.x, backY, p2.y));  normals.append(nrm)
            verts.append(SCNVector3(p2.x, frontY, p2.y)); normals.append(nrm)
        }

        var indices: [Int32] = []
        indices.reserveCapacity(n * 12)
        // Back cap fan (normal -Y → CW winding viewed from +Y).
        for i in 0..<n {
            let a = Int32(i)
            let b = Int32((i + 1) % n)
            let c = Int32(backCenterIndex)
            indices.append(contentsOf: [c, b, a])
        }
        // Front cap fan (normal +Y → CCW winding viewed from +Y).
        for i in 0..<n {
            let a = Int32(n + i)
            let b = Int32(n + (i + 1) % n)
            let c = Int32(frontCenterIndex)
            indices.append(contentsOf: [c, a, b])
        }
        // Side-wall quad strip.
        for i in 0..<n {
            let bA = Int32(sideStartIndex + 2 * i)
            let fA = Int32(sideStartIndex + 2 * i + 1)
            let bB = Int32(sideStartIndex + 2 * ((i + 1) % n))
            let fB = Int32(sideStartIndex + 2 * ((i + 1) % n) + 1)
            indices.append(contentsOf: [bA, fA, fB, bA, fB, bB])
        }

        let vertexSource = SCNGeometrySource(vertices: verts)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
    }

    // MARK: - Materials

    private static func steelMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = PlatformColor.calibrated(red: 0.40, green: 0.42, blue: 0.46, alpha: 1.0)
        m.metalness.contents = 0.95
        m.roughness.contents = 0.32
        m.lightingModel = .physicallyBased
        return m
    }

    private static func pinMaterial() -> SCNMaterial {
        // Polished pin: a touch shinier than the web bodies.
        let m = SCNMaterial()
        m.diffuse.contents = PlatformColor.calibrated(red: 0.48, green: 0.50, blue: 0.54, alpha: 1.0)
        m.metalness.contents = 0.97
        m.roughness.contents = pinPolishedRoughness
        m.lightingModel = .physicallyBased
        return m
    }
}
