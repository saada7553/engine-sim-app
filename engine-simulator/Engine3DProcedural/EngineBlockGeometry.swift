//
//  EngineBlockGeometry.swift
//  engine-simulator
//
//  Crankcase + per-bank cylinder-bank slabs, sized from EngineGeometryParams
//  so nothing clips. For inline engines, the crankcase sits below a single
//  upright bank slab. For V/Flat engines, two bank slabs splay outward at
//  ±bankHalfAngleRad, giving the V silhouette.
//
//  All parts share a translucent material with depth-writes disabled so the
//  internals (crank, rods, pistons) remain clearly visible through the block.
//

import SceneKit
import AppKit

private let blockAlpha: CGFloat = 0.03
private let chamferFactorOfBore: Double = 0.04

enum EngineBlockGeometry {
    static func makeNode(params p: EngineGeometryParams, layout: EngineLayout) -> SCNNode {
        let node = SCNNode()
        node.name = "engineBlock"

        addCrankcase(to: node, params: p)
        addBankSlabs(to: node, params: p)

        _ = layout
        return node
    }

    private static func addCrankcase(to parent: SCNNode, params p: EngineGeometryParams) {
        let width = p.crankCaseHalfWidth * 2.0
        let height = p.crankCaseTopZ - p.crankCaseBottomZ
        let chamfer = p.bore * chamferFactorOfBore

        let box = SCNBox(width: CGFloat(width),
                         height: CGFloat(p.blockLength),
                         length: CGFloat(height),
                         chamferRadius: CGFloat(chamfer))
        box.firstMaterial = blockMaterial()

        let n = SCNNode(geometry: box)
        n.position = SCNVector3(0, 0, Float((p.crankCaseTopZ + p.crankCaseBottomZ) / 2.0))
        n.name = "crankcase"
        parent.addChildNode(n)
    }

    private static func addBankSlabs(to parent: SCNNode, params p: EngineGeometryParams) {
        let slabWidth = p.bankSlabHalfWidth * 2.0
        let slabHeight = p.bankSlabTopZ - p.bankSlabBottomZ
        let chamfer = p.bore * chamferFactorOfBore

        // For 1-bank (inline), bankCount is 1 and bank rotation is 0; we still
        // produce a single slab. For 2-bank engines we splay one per bank and
        // shift it along Y by the bank's axial offset (matches the cylinder
        // bores' actual position over the offset pistons).
        let bankCount = p.bankCount
        for bankIndex in 0..<bankCount {
            let bankSign: Double = (bankIndex == 0) ? -1.0 : 1.0
            let angle = (bankIndex == 0 ? 1.0 : -1.0) * p.bankHalfAngleRad
            let axialShift = bankSign * p.bankAxialShift

            let slab = SCNBox(width: CGFloat(slabWidth),
                              height: CGFloat(p.bankSlabLength),
                              length: CGFloat(slabHeight),
                              chamferRadius: CGFloat(chamfer))
            slab.firstMaterial = blockMaterial()
            let slabNode = SCNNode(geometry: slab)
            // Slab sits along the bank's bore axis (local +Z), centered between
            // the crankcase top and the deck, and shifted along Y so its bores
            // sit over this bank's piston slots.
            slabNode.position = SCNVector3(0,
                                           Float(axialShift),
                                           Float((p.bankSlabTopZ + p.bankSlabBottomZ) / 2.0))

            let pivot = SCNNode()
            pivot.name = "bankSlabPivot_\(bankIndex)"
            pivot.eulerAngles.y = CGFloat(angle)
            pivot.addChildNode(slabNode)
            parent.addChildNode(pivot)
        }
    }

    private static func blockMaterial() -> SCNMaterial {
        // Block: dark cast iron with a cool tint, very translucent.
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(calibratedRed: 0.30, green: 0.32, blue: 0.36, alpha: blockAlpha)
        m.transparency = blockAlpha
        m.isDoubleSided = true
        m.metalness.contents = 0.1
        m.roughness.contents = 0.75
        m.lightingModel = .physicallyBased
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        return m
    }
}
