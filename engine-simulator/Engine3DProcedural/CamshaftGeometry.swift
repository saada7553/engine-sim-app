//
//  CamshaftGeometry.swift
//  engine-simulator
//
//  Procedural camshaft: one central shaft running along Y (the cam axis,
//  parallel to the crank) plus one cam lobe per cylinder served. Each lobe
//  is a 2D profile (base circle + cosine bump) extruded into a thin disc.
//
//  The lobe's 2D profile is generated with peak at +X (path-local). After
//  extrusion the node is reoriented so the lobe disc lies in the X-Z plane
//  (axis along Y, matching the shaft); a final Ry rotation positions the
//  lobe peak at its design angle on the cam.
//
//  The lobe geometry itself is static — animation rotates the entire
//  camshaft node around Y at half crank speed, sweeping all lobes together.
//

import SceneKit
import AppKit

private let shaftRadialSegments: Int = 24
private let lobeContourPointCount: Int = 96

struct CamLobeSpec {
    let yOffset: Double         // along cam axis
    let peakAngleRad: Double    // lobe peak angle (cam-local, in the cam's X-Z plane)
}

enum CamshaftGeometry {
    static func makeNode(params p: EngineGeometryParams,
                         lobes: [CamLobeSpec],
                         shaftStartY: Double,
                         shaftEndY: Double) -> SCNNode {
        let node = SCNNode()
        node.name = "camshaft"

        // Central shaft (default cylinder axis = Y, no rotation needed).
        let shaftLength = max(shaftEndY - shaftStartY, 0.001)
        let shaft = SCNCylinder(radius: CGFloat(p.camShaftRadius),
                                height: CGFloat(shaftLength))
        shaft.radialSegmentCount = shaftRadialSegments
        shaft.firstMaterial = camMaterial()
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.position.y = CGFloat((shaftStartY + shaftEndY) / 2.0)
        node.addChildNode(shaftNode)

        // One lobe per cylinder served.
        for lobe in lobes {
            let lobeNode = makeLobeNode(params: p, peakAngleRad: lobe.peakAngleRad)
            lobeNode.position.y = CGFloat(lobe.yOffset)
            node.addChildNode(lobeNode)
        }

        return node
    }

    private static func makeLobeNode(params p: EngineGeometryParams,
                                     peakAngleRad: Double) -> SCNNode {
        let path = lobeProfilePath(params: p)
        let shape = SCNShape(path: path, extrusionDepth: CGFloat(p.camLobeThickness))
        shape.firstMaterial = camMaterial()

        // SCNShape default: path in X-Y plane, extrusion along +Z.
        // First an inner node centers the disc along its extrusion axis and
        // reorients the path so the disc lies in the X-Z plane (axis Y).
        let innerNode = SCNNode(geometry: shape)
        innerNode.position.z = -CGFloat(p.camLobeThickness) / 2.0
        innerNode.eulerAngles.x = -.pi / 2

        let outerNode = SCNNode()
        outerNode.addChildNode(innerNode)
        // Position the lobe peak at peakAngleRad in the cam's X-Z plane.
        outerNode.eulerAngles.y = CGFloat(peakAngleRad)
        return outerNode
    }

    /// Builds a 2D cam contour with peak at +X in path coordinates.
    /// For |θ| > duration/2 the profile sits on the base circle; inside the
    /// duration it rises smoothly to camMaxLift via a cosine bump.
    private static func lobeProfilePath(params p: EngineGeometryParams) -> NSBezierPath {
        let path = NSBezierPath()
        let halfDur = p.camDurationRadCam / 2.0
        for i in 0..<lobeContourPointCount {
            let theta = 2.0 * .pi * Double(i) / Double(lobeContourPointCount)
            let wrapped = atan2(sin(theta), cos(theta))   // in [-π, π], peak at θ=0
            let r: Double
            if abs(wrapped) < halfDur, halfDur > 0 {
                let x = wrapped * .pi / p.camDurationRadCam
                let c = cos(x)
                r = p.camBaseRadius + p.camMaxLift * c * c
            } else {
                r = p.camBaseRadius
            }
            let px = r * cos(theta)
            let py = r * sin(theta)
            if i == 0 {
                path.move(to: NSPoint(x: CGFloat(px), y: CGFloat(py)))
            } else {
                path.line(to: NSPoint(x: CGFloat(px), y: CGFloat(py)))
            }
        }
        path.close()
        return path
    }

    private static func camMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        m.metalness.contents = 0.9
        m.roughness.contents = 0.3
        m.lightingModel = .physicallyBased
        return m
    }
}
