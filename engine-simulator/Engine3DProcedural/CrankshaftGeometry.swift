//
//  CrankshaftGeometry.swift
//  engine-simulator
//
//  Procedural crankshaft built from the per-cylinder placement data in
//  EngineGeometryParams. One throw per cylinder, journal angle taken from
//  CylinderPlacement.phaseOffsetRad so the shape responds to firing-order
//  changes. Main journals run along the crank axis (Y); rod pins sit at a
//  radius equal to the crank throw, with paired counterweights opposite.
//
//  Returned node is in the engine's coordinate frame (Y = crank axis); the
//  whole node rotates around Y to drive the animation.
//

import SceneKit
import AppKit

private let mainJournalSegmentCount: Int = 24
private let rodPinSegmentCount: Int = 20
private let snoutLengthFactorOfBore: Double = 0.5

enum CrankshaftGeometry {
    static func makeNode(params p: EngineGeometryParams) -> SCNNode {
        let node = SCNNode()
        node.name = "crankshaft"

        let mainRadius = CGFloat(p.mainJournalDiameter / 2.0)
        let pinRadius = CGFloat(p.crankPinDiameter / 2.0)
        let throwR = CGFloat(p.crankThrow)
        let webThickness = CGFloat(p.crankWebThickness)
        let counterweightR = CGFloat(p.counterweightRadius)
        let counterweightThickness = CGFloat(p.counterweightThickness)

        let sortedThrows = p.cylinders.sorted { $0.yOffset < $1.yOffset }
        let firstY = sortedThrows.first?.yOffset ?? 0
        let lastY = sortedThrows.last?.yOffset ?? 0

        // Group cylinders by slot (shared Y) so V-engine pairs share one throw.
        var slotsByY: [(y: Double, angleRad: Double)] = []
        var seenSlots = Set<Int>()
        for placement in sortedThrows {
            if seenSlots.insert(placement.slotIndex).inserted {
                slotsByY.append((placement.yOffset, placement.phaseOffsetRad))
            }
        }

        // Build the spine: main journals between slots + end snouts.
        let snoutLength = CGFloat(p.bore * snoutLengthFactorOfBore)
        addMainJournal(to: node,
                       fromY: firstY - p.bore * 0.4 - p.bore * snoutLengthFactorOfBore,
                       toY: firstY - p.bore * 0.4,
                       radius: mainRadius * 1.2)
        addMainJournal(to: node,
                       fromY: lastY + p.bore * 0.4,
                       toY: lastY + p.bore * 0.4 + p.bore * snoutLengthFactorOfBore * 1.3,
                       radius: mainRadius * 1.4)
        _ = snoutLength

        for (i, slot) in slotsByY.enumerated() {
            let slotStart = slot.y - Double(p.crankWebThickness)
            let slotEnd = slot.y + Double(p.crankWebThickness)

            // Main journal segment leading INTO this slot from the previous one
            // (or from the front snout if it's the first).
            let prevEnd = i == 0 ? firstY - p.bore * 0.4 : slotsByY[i - 1].y + Double(p.crankWebThickness)
            addMainJournal(to: node, fromY: prevEnd, toY: slotStart, radius: mainRadius)

            // Two webs (front and rear of the throw) + the rod pin between them +
            // counterweight opposite the pin.
            addThrow(to: node,
                     centerY: slot.y,
                     angleRad: slot.angleRad,
                     params: p,
                     throwRadius: throwR,
                     pinRadius: pinRadius,
                     webThickness: webThickness,
                     counterweightR: counterweightR,
                     counterweightThickness: counterweightThickness)
        }

        // Main journal from last slot to rear snout.
        if let last = slotsByY.last {
            addMainJournal(to: node,
                           fromY: last.y + Double(p.crankWebThickness),
                           toY: lastY + p.bore * 0.4,
                           radius: mainRadius)
        }

        // Flywheel-end flange (visible disc at the back).
        let flange = SCNCylinder(radius: counterweightR * 0.95, height: webThickness * 1.2)
        flange.radialSegmentCount = mainJournalSegmentCount
        flange.firstMaterial = steelMaterial()
        let flangeNode = SCNNode(geometry: flange)
        flangeNode.position.y = CGFloat(lastY) + CGFloat(p.bore * 0.4) + CGFloat(p.bore * snoutLengthFactorOfBore * 0.65)
        node.addChildNode(flangeNode)

        return node
    }

    private static func addMainJournal(to parent: SCNNode,
                                       fromY: Double,
                                       toY: Double,
                                       radius: CGFloat) {
        let length = CGFloat(toY - fromY)
        guard length > 0.0005 else { return }
        let cyl = SCNCylinder(radius: radius, height: length)
        cyl.radialSegmentCount = mainJournalSegmentCount
        cyl.firstMaterial = steelMaterial()
        let cylNode = SCNNode(geometry: cyl)
        cylNode.position.y = CGFloat((fromY + toY) / 2)
        parent.addChildNode(cylNode)
    }

    private static func addThrow(to parent: SCNNode,
                                 centerY: Double,
                                 angleRad: Double,
                                 params p: EngineGeometryParams,
                                 throwRadius: CGFloat,
                                 pinRadius: CGFloat,
                                 webThickness: CGFloat,
                                 counterweightR: CGFloat,
                                 counterweightThickness: CGFloat) {
        let sinA = CGFloat(sin(angleRad))
        let cosA = CGFloat(cos(angleRad))

        // Pin offset in the X-Z plane.
        let pinX = throwRadius * sinA
        let pinZ = throwRadius * cosA

        let webHalfThick = webThickness / 2
        let webYFront = CGFloat(centerY) - p.crankThrow.cg - webHalfThick
        let webYBack = CGFloat(centerY) + p.crankThrow.cg + webHalfThick
        _ = webYFront; _ = webYBack
        // Webs sit at y = centerY ± (counterweightThickness/2 + half a tiny gap).
        let webGap = counterweightThickness / 2 + webHalfThick
        let frontWebY = CGFloat(centerY) - webGap
        let backWebY = CGFloat(centerY) + webGap

        // Rod pin spanning between the two webs.
        let pinLength = (backWebY - frontWebY)
        let pin = SCNCylinder(radius: pinRadius, height: pinLength)
        pin.radialSegmentCount = rodPinSegmentCount
        pin.firstMaterial = steelMaterial()
        let pinNode = SCNNode(geometry: pin)
        pinNode.position = SCNVector3(Float(pinX), Float(centerY), Float(pinZ))
        parent.addChildNode(pinNode)

        // Two crank webs / counterweights — fan-shaped slabs in X-Z plane, thin in Y.
        for webY in [frontWebY, backWebY] {
            addCounterweight(to: parent,
                             centerY: webY,
                             pinX: pinX,
                             pinZ: pinZ,
                             counterweightR: counterweightR,
                             counterweightThickness: counterweightThickness,
                             throwRadius: throwRadius)
        }
    }

    private static func addCounterweight(to parent: SCNNode,
                                         centerY: CGFloat,
                                         pinX: CGFloat,
                                         pinZ: CGFloat,
                                         counterweightR: CGFloat,
                                         counterweightThickness: CGFloat,
                                         throwRadius: CGFloat) {
        // A counterweight is a thick disc offset to the opposite side of the pin,
        // approximating the real fan shape with a full disc whose center is shifted
        // away from the pin by ~50% of its radius.
        let disc = SCNCylinder(radius: counterweightR, height: counterweightThickness)
        disc.radialSegmentCount = mainJournalSegmentCount
        disc.firstMaterial = steelMaterial()
        let discNode = SCNNode(geometry: disc)

        // Offset opposite to the pin direction (so the heavy side balances the pin).
        let pinMag = sqrt(pinX * pinX + pinZ * pinZ)
        let dirX: CGFloat = pinMag > 0 ? -pinX / pinMag : 0
        let dirZ: CGFloat = pinMag > 0 ? -pinZ / pinMag : 0
        let offset = counterweightR * 0.35
        discNode.position = SCNVector3(Float(dirX * offset), Float(centerY), Float(dirZ * offset))
        parent.addChildNode(discNode)

        // Add a smaller "boss" disc on the pin side so the web visually carries the pin.
        let boss = SCNCylinder(radius: throwRadius * 1.1, height: counterweightThickness)
        boss.radialSegmentCount = mainJournalSegmentCount
        boss.firstMaterial = steelMaterial()
        let bossNode = SCNNode(geometry: boss)
        bossNode.position = SCNVector3(Float(pinX * 0.5), Float(centerY), Float(pinZ * 0.5))
        parent.addChildNode(bossNode)
    }

    private static func steelMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedWhite: 0.55, alpha: 1.0)
        m.metalness.contents = 0.95
        m.roughness.contents = 0.35
        m.lightingModel = .physicallyBased
        return m
    }
}

private extension Double {
    var cg: CGFloat { CGFloat(self) }
}
