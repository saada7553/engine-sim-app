//
//  ConnectingRodGeometry.swift
//  engine-simulator
//
//  I-beam connecting rod. Local origin = small-end (wrist-pin) center;
//  big end sits at local (0, 0, -rodLength). Local +Z points from big end
//  toward small end (i.e., up the bore). Rotating the rod node around Y
//  about the small end swings the big end in the X-Z plane to follow the
//  crank pin.
//
//  Pin convention: both bearings and the wrist pin share an axis parallel
//  to the crankshaft (local +Y). This matches a real engine — the wrist
//  pin and rod-journal bearing axes are both parallel to the crank.
//
//  I-beam orientation: rod bends in the X-Z plane (as it swings around Y),
//  so the web is tall along X (resists the bending stress) and thin along
//  Y (the pin direction); flanges are wide along Y (matching the bearing
//  width) and thin along X.
//

import SceneKit
import AppKit

private let smallEndOuterRadiusFactor: Double = 0.18   // × bore
private let bigEndOuterRadiusFactor: Double = 0.32     // × bore
private let webThicknessFactorOfBore: Double = 0.09
private let webHeightFactorOfBore: Double = 0.30   // tall direction (X) of the I
private let flangeThicknessFactorOfBore: Double = 0.04
private let ringSegments: Int = 36

enum ConnectingRodGeometry {
    static func makeNode(params p: EngineGeometryParams) -> SCNNode {
        let node = SCNNode()
        node.name = "connectingRod"

        let bore = p.bore
        let rodLen = p.rodLength

        let smallOuter = bore * smallEndOuterRadiusFactor
        let smallInner = p.wristPinDiameter / 2.0
        let bigOuter = bore * bigEndOuterRadiusFactor
        let bigInner = p.crankPinDiameter / 2.0
        let bearingWidth = p.rodBearingWidth        // along Y (pin direction)
        let webThickness = bore * webThicknessFactorOfBore   // along Y
        let webHeight = bore * webHeightFactorOfBore         // along X (tall direction)
        let flangeThickness = bore * flangeThicknessFactorOfBore  // along X

        // Small-end ring (around wrist pin) at local origin.
        let smallEnd = ringNode(outerRadius: smallOuter,
                                innerRadius: smallInner,
                                axialThickness: bearingWidth)
        node.addChildNode(smallEnd)

        // Big-end ring (around crank pin) at -rodLength along the bore axis.
        let bigEnd = ringNode(outerRadius: bigOuter,
                              innerRadius: bigInner,
                              axialThickness: bearingWidth)
        bigEnd.position = SCNVector3(0, 0, Float(-rodLen))
        node.addChildNode(bigEnd)

        // I-beam shaft running between the two ring inner edges.
        let shaftLength = rodLen - smallOuter - bigOuter
        let shaftCenterZ = -rodLen / 2.0 + (smallOuter - bigOuter) / 2.0

        // Web: tall in X (bending direction), thin in Y (pin direction).
        let web = SCNBox(width: webHeight,
                         height: webThickness,
                         length: shaftLength,
                         chamferRadius: webThickness * 0.25)
        web.firstMaterial = rodMaterial()
        let webNode = SCNNode(geometry: web)
        webNode.position = SCNVector3(0, 0, Float(shaftCenterZ))
        node.addChildNode(webNode)

        // Two flanges sit at the top and bottom of the I (X = ±webHeight/2),
        // thin in X (flangeThickness) and wide in Y (= bearingWidth) so they
        // match the bearing thickness at each end.
        let flangeXHalf = (webHeight - flangeThickness) / 2.0
        for xSign in [-1.0, 1.0] {
            let flange = SCNBox(width: flangeThickness,
                                height: bearingWidth,
                                length: shaftLength,
                                chamferRadius: flangeThickness * 0.4)
            flange.firstMaterial = rodMaterial()
            let flangeNode = SCNNode(geometry: flange)
            flangeNode.position = SCNVector3(Float(xSign * flangeXHalf),
                                             0,
                                             Float(shaftCenterZ))
            node.addChildNode(flangeNode)
        }

        return node
    }

    /// Builds a clean ring whose central axis is along Y (the pin/crank-axis
    /// direction). axialThickness = width along the pin.
    private static func ringNode(outerRadius: Double,
                                 innerRadius: Double,
                                 axialThickness: Double) -> SCNNode {
        let tube = SCNTube(innerRadius: CGFloat(innerRadius),
                           outerRadius: CGFloat(outerRadius),
                           height: CGFloat(axialThickness))
        tube.radialSegmentCount = ringSegments
        tube.heightSegmentCount = 1
        tube.firstMaterial = rodMaterial()
        // SCNTube default axis = Y, which is exactly the pin axis. No rotation.
        return SCNNode(geometry: tube)
    }

    private static func rodMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedWhite: 0.68, alpha: 1.0)
        m.metalness.contents = 0.9
        m.roughness.contents = 0.3
        m.lightingModel = .physicallyBased
        return m
    }
}
