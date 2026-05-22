//
//  CamshaftGeometry.swift
//  engine-simulator
//
//  Procedural camshaft: central shaft along Y plus one cam lobe per cylinder
//  served. Each lobe is a hand-built SCNGeometry — front cap, back cap, and
//  side wall — generated from the same cos² lobe profile as the builder
//  preview, so the silhouette looks like a real cam lobe (a circle with a
//  smooth nose) rather than a smoothed-out pill.
//

import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

private let shaftRadialSegments: Int = 24
private let lobeContourPointCount: Int = 192

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
        shaftNode.position.y = SCNFloat((shaftStartY + shaftEndY) / 2.0)
        node.addChildNode(shaftNode)

        for lobe in lobes {
            let lobeNode = makeLobeNode(params: p, peakAngleRad: lobe.peakAngleRad)
            lobeNode.position.y = SCNFloat(lobe.yOffset)
            node.addChildNode(lobeNode)
        }

        return node
    }

    /// Builds a 3D cam-lobe disc by hand: contour vertices, triangulated caps,
    /// and side-wall quads. Lobe extends along Y (the cam axis); the profile
    /// lies in the X-Z plane with the peak pointing along +X at peakAngleRad=0.
    private static func makeLobeNode(params p: EngineGeometryParams,
                                     peakAngleRad: Double) -> SCNNode {
        // In the diagnostic wireframe a 192-point lobe cap fans into a solid
        // disc of lines, so drop to a coarse contour there. The solid view
        // keeps the full count.
        let n = ProceduralWireframeBuild.active
            ? ProceduralWireframeBuild.lobeContourPoints
            : lobeContourPointCount
        let baseR = p.camBaseRadius
        let lift = p.camMaxLift
        let halfDur = p.camDurationRadCam / 2.0
        let halfThickness = p.camLobeThickness / 2.0

        // 1) Build the 2D contour in (X, Z), centered around the cam axis.
        var contour: [SIMD2<Float>] = []
        contour.reserveCapacity(n)
        for i in 0..<n {
            let theta = 2.0 * .pi * Double(i) / Double(n)
            let wrapped = atan2(sin(theta), cos(theta))   // [-π, π], peak at θ=0
            let r: Double
            if abs(wrapped) < halfDur, halfDur > 0 {
                let arg = wrapped * .pi / p.camDurationRadCam
                let c = cos(arg)
                r = baseR + lift * c * c
            } else {
                r = baseR
            }
            contour.append(SIMD2<Float>(Float(r * cos(theta)),
                                         Float(r * sin(theta))))
        }

        // 2) Emit vertices: ring of points at -Y face, ring at +Y face, plus
        //    center points for each cap so we can triangulate as a fan.
        var verts: [SCNVector3] = []
        var normals: [SCNVector3] = []
        verts.reserveCapacity(n * 2 + 2)
        normals.reserveCapacity(n * 2 + 2)

        let backY = Float(-halfThickness)
        let frontY = Float(halfThickness)

        // Back-cap ring (Y = -halfThickness). Normal: -Y.
        for p2 in contour {
            verts.append(SCNVector3(p2.x, backY, p2.y))
            normals.append(SCNVector3(0, -1, 0))
        }
        // Front-cap ring (Y = +halfThickness). Normal: +Y.
        for p2 in contour {
            verts.append(SCNVector3(p2.x, frontY, p2.y))
            normals.append(SCNVector3(0, 1, 0))
        }
        // Cap centers
        let backCenterIndex = verts.count
        verts.append(SCNVector3(0, backY, 0))
        normals.append(SCNVector3(0, -1, 0))
        let frontCenterIndex = verts.count
        verts.append(SCNVector3(0, frontY, 0))
        normals.append(SCNVector3(0, 1, 0))

        // Side-wall vertices need their own normals (radial). We re-emit each
        // contour point on each face so the side-wall and the cap can have
        // independent normals.
        let sideStartIndex = verts.count
        for i in 0..<n {
            let p2 = contour[i]
            let next = contour[(i + 1) % n]
            // Edge tangent in X-Z: (next - p2). Normal points outward, which
            // for a counter-clockwise contour is rotated -π/2 from the tangent.
            let tx = next.x - p2.x
            let tz = next.y - p2.y
            // Outward normal (rotate tangent by -90° about Y): (tz, 0, -tx).
            let nx = tz
            let nz = -tx
            let len = max(sqrt(nx * nx + nz * nz), 1e-6)
            let nrm = SCNVector3(nx / len, 0, nz / len)
            // Two vertices at this contour point (back and front face).
            verts.append(SCNVector3(p2.x, backY, p2.y))
            normals.append(nrm)
            verts.append(SCNVector3(p2.x, frontY, p2.y))
            normals.append(nrm)
        }

        // 3) Indices.
        var indices: [Int32] = []
        // Back cap (fan around back-center). Wind so the normal faces -Y, i.e.
        // viewed from -Y the triangles are counter-clockwise.
        for i in 0..<n {
            let a = Int32(i)
            let b = Int32((i + 1) % n)
            let c = Int32(backCenterIndex)
            indices.append(contentsOf: [c, b, a])
        }
        // Front cap (fan around front-center). Wind opposite to face +Y.
        for i in 0..<n {
            let a = Int32(n + i)
            let b = Int32(n + (i + 1) % n)
            let c = Int32(frontCenterIndex)
            indices.append(contentsOf: [c, a, b])
        }
        // Side walls (quad strip between back and front contour rings).
        for i in 0..<n {
            let bA = Int32(sideStartIndex + 2 * i)
            let fA = Int32(sideStartIndex + 2 * i + 1)
            let bB = Int32(sideStartIndex + 2 * ((i + 1) % n))
            let fB = Int32(sideStartIndex + 2 * ((i + 1) % n) + 1)
            // Two triangles per quad — outward winding (viewed from outside).
            indices.append(contentsOf: [bA, fA, fB, bA, fB, bB])
        }

        // 4) Build SCNGeometry from vertex/normal/index sources.
        let vertexSource = SCNGeometrySource(vertices: verts)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geo = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        geo.firstMaterial = camMaterial()

        let node = SCNNode(geometry: geo)
        // Rotate so the lobe peak (currently at +X) sits at peakAngleRad in
        // the cam's X-Z plane.
        node.eulerAngles.y = SCNFloat(peakAngleRad)
        return node
    }

    private static func camMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = PlatformColor.calibrated(red: 0.62, green: 0.58, blue: 0.52, alpha: 1.0)
        m.metalness.contents = 0.85
        m.roughness.contents = 0.35
        m.lightingModel = .physicallyBased
        return m
    }
}
