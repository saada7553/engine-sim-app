//
//  ProceduralEngineAssembly.swift
//  engine-simulator
//
//  Builds the full engine scene-graph from an EngineSpec and keeps refs to
//  every moving part so the animation loop can update them each frame.
//
//  Coordinate convention (before the assembly's outer world-up rotation):
//    Y = crankshaft + cam axis (along the block length)
//    Z = bore axis of bank 0 (piston travels along +Z away from crank)
//    X = lateral
//
//  Per-bank parts (head, cams, valves, pistons, rods) are grouped under a
//  single bankPivot per bank that handles the V/Flat splay.
//

import SceneKit
import Foundation

private let valveYHalfPitchFactorOfBore: Double = 0.25  // two valves per cam per cylinder

final class ProceduralEngineParts {
    let assemblyNode: SCNNode
    let params: EngineGeometryParams
    let placements: [CylinderPlacement]

    weak var crankshaft: SCNNode?
    var pistons: [SCNNode] = []          // index = cylinderNumber - 1
    var rods: [SCNNode] = []
    var wristPins: [SCNNode] = []
    /// Cylinder head per bank. Used for engine-wide head damage tinting.
    var heads: [SCNNode] = []

    /// One intake + one exhaust cam per bank. Index = bankIndex.
    var intakeCams: [SCNNode] = []
    var exhaustCams: [SCNNode] = []

    /// Per-cylinder valves. Each entry holds the 2 intake + 2 exhaust valve
    /// nodes, plus the lobe-peak angles used to drive their lift.
    struct ValveSet {
        let intakeValves: [SCNNode]
        let exhaustValves: [SCNNode]
        let intakeLobePeakRad: Double
        let exhaustLobePeakRad: Double
        let valveSeatZ: Double           // bank-local Z when valve is closed
    }
    var valveSetsByCylinder: [ValveSet?] = []

    init(assemblyNode: SCNNode,
         params: EngineGeometryParams,
         placements: [CylinderPlacement]) {
        self.assemblyNode = assemblyNode
        self.params = params
        self.placements = placements
    }
}

enum ProceduralEngineAssembly {
    static func build(spec: EngineSpec) -> ProceduralEngineParts {
        let params = EngineGeometryParams(spec: spec)

        // Outer rotation: bore-axis (local +Z) → world +Y (up); crank-axis
        // (local +Y) → world -Z (into the scene). Camera on +X/+Y/+Z sees the
        // engine from a top-front-side 3/4 view.
        let assembly = SCNNode()
        assembly.name = "proceduralEngineAssembly"
        assembly.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)

        let parts = ProceduralEngineParts(assemblyNode: assembly,
                                          params: params,
                                          placements: params.cylinders)

        // ----- Crankshaft (one node, rotates around Y) -----
        let crank = CrankshaftGeometry.makeNode(params: params)
        assembly.addChildNode(crank)
        parts.crankshaft = crank

        // Decorative cooling fan attached to the crank so it spins with it.
        FanGeometry.attach(to: crank, params: params)

        // ----- Per-bank parts -----
        parts.pistons = Array(repeating: SCNNode(), count: params.cylinders.count)
        parts.rods = Array(repeating: SCNNode(), count: params.cylinders.count)
        parts.wristPins = Array(repeating: SCNNode(), count: params.cylinders.count)
        parts.valveSetsByCylinder = Array<ProceduralEngineParts.ValveSet?>(
            repeating: nil, count: params.cylinders.count)
        parts.intakeCams = Array(repeating: SCNNode(), count: params.bankCount)
        parts.exhaustCams = Array(repeating: SCNNode(), count: params.bankCount)

        // Group cylinders by bank.
        var byBank: [Int: [CylinderPlacement]] = [:]
        for placement in params.cylinders {
            byBank[placement.bankIndex, default: []].append(placement)
        }

        for bankIndex in 0..<params.bankCount {
            let cylinders = byBank[bankIndex] ?? []
            let pivot = SCNNode()
            pivot.name = "bankPivot_\(bankIndex)"
            let bankAngle = cylinders.first?.bankAngleRad ?? 0
            pivot.eulerAngles.y = SCNFloat(bankAngle)
            assembly.addChildNode(pivot)

            // Block slab is added separately in the engine block; head goes here
            // so it inherits the bank rotation. Shifted along Y so the head bores
            // sit directly over this bank's pistons (no shift for inline).
            let head = CylinderHeadGeometry.makeNode(params: params)
            let bankSign: Float = (bankIndex == 0) ? -1.0 : 1.0
            head.position.y = SCNFloat(bankSign * Float(params.bankAxialShift))
            pivot.addChildNode(head)
            parts.heads.append(head)

            // Per-cylinder pistons / rods / wristpins / valves.
            for placement in cylinders {
                addCylinderParts(to: pivot, placement: placement, params: params, parts: parts)
            }

            // Intake + exhaust cams for this bank's cylinders.
            addCams(to: pivot, bankIndex: bankIndex, cylinders: cylinders,
                    params: params, parts: parts)
        }

        // ----- Block (crankcase + bank slabs are inside the block node) -----
        let block = EngineBlockGeometry.makeNode(params: params, layout: spec.layout)
        assembly.addChildNode(block)

        // Place every moving part at its crank-angle-zero position so the very
        // first rendered frame is already valid (rather than snapping to the
        // correct pose only once the engine starts cranking).
        animate(parts: parts, crankAngle: 0)

        return parts
    }

    // MARK: - Per-cylinder assembly

    private static func addCylinderParts(to bankPivot: SCNNode,
                                         placement: CylinderPlacement,
                                         params: EngineGeometryParams,
                                         parts: ProceduralEngineParts) {
        let yOffset = Float(placement.yOffset)
        let idx = placement.cylinderNumber - 1

        let piston = PistonGeometry.makeNode(params: params)
        piston.position = SCNVector3(0, yOffset, 0)
        bankPivot.addChildNode(piston)
        parts.pistons[idx] = piston

        let rod = ConnectingRodGeometry.makeNode(params: params)
        rod.position = SCNVector3(0, yOffset, 0)
        bankPivot.addChildNode(rod)
        parts.rods[idx] = rod

        let pin = WristPinGeometry.makeNode(params: params)
        pin.position = SCNVector3(0, yOffset, 0)
        bankPivot.addChildNode(pin)
        parts.wristPins[idx] = pin

        // Valves: 2 intake + 2 exhaust per cylinder, split along Y so they sit
        // either side of the cylinder center.
        let valveYHalf = params.bore * valveYHalfPitchFactorOfBore
        let intakeValves: [SCNNode] = [-1.0, 1.0].map { ySign in
            let v = ValveGeometry.makeNode(params: params, kind: .intake)
            v.position = SCNVector3(Float(params.intakeCamLocalX),
                                    Float(placement.yOffset + ySign * valveYHalf),
                                    Float(params.valveSeatZ))
            bankPivot.addChildNode(v)
            return v
        }
        let exhaustValves: [SCNNode] = [-1.0, 1.0].map { ySign in
            let v = ValveGeometry.makeNode(params: params, kind: .exhaust)
            v.position = SCNVector3(Float(params.exhaustCamLocalX),
                                    Float(placement.yOffset + ySign * valveYHalf),
                                    Float(params.valveSeatZ))
            bankPivot.addChildNode(v)
            return v
        }

        parts.valveSetsByCylinder[idx] = ProceduralEngineParts.ValveSet(
            intakeValves: intakeValves,
            exhaustValves: exhaustValves,
            intakeLobePeakRad: intakeLobePeak(for: placement, params: params),
            exhaustLobePeakRad: exhaustLobePeak(for: placement, params: params),
            valveSeatZ: params.valveSeatZ
        )
    }

    // MARK: - Cams

    private static func addCams(to bankPivot: SCNNode,
                                bankIndex: Int,
                                cylinders: [CylinderPlacement],
                                params: EngineGeometryParams,
                                parts: ProceduralEngineParts) {
        // Two lobes per cylinder per cam — one directly above each of the two
        // valves it actuates. Both lobes share the same peak angle.
        let valveYHalf = params.bore * valveYHalfPitchFactorOfBore
        let intakeLobes = cylinders.flatMap { cyl -> [CamLobeSpec] in
            let peak = intakeLobePeak(for: cyl, params: params)
            return [
                CamLobeSpec(yOffset: cyl.yOffset - valveYHalf, peakAngleRad: peak),
                CamLobeSpec(yOffset: cyl.yOffset + valveYHalf, peakAngleRad: peak),
            ]
        }
        let exhaustLobes = cylinders.flatMap { cyl -> [CamLobeSpec] in
            let peak = exhaustLobePeak(for: cyl, params: params)
            return [
                CamLobeSpec(yOffset: cyl.yOffset - valveYHalf, peakAngleRad: peak),
                CamLobeSpec(yOffset: cyl.yOffset + valveYHalf, peakAngleRad: peak),
            ]
        }

        let firstY = cylinders.map(\.yOffset).min() ?? 0
        let lastY = cylinders.map(\.yOffset).max() ?? 0
        let shaftStartY = firstY - params.bore * 0.4
        let shaftEndY = lastY + params.bore * 0.4

        let intakeCam = CamshaftGeometry.makeNode(params: params,
                                                  lobes: intakeLobes,
                                                  shaftStartY: shaftStartY,
                                                  shaftEndY: shaftEndY)
        intakeCam.position = SCNVector3(Float(params.intakeCamLocalX),
                                        0,
                                        Float(params.camLocalZ))
        bankPivot.addChildNode(intakeCam)
        parts.intakeCams[bankIndex] = intakeCam

        let exhaustCam = CamshaftGeometry.makeNode(params: params,
                                                   lobes: exhaustLobes,
                                                   shaftStartY: shaftStartY,
                                                   shaftEndY: shaftEndY)
        exhaustCam.position = SCNVector3(Float(params.exhaustCamLocalX),
                                         0,
                                         Float(params.camLocalZ))
        bankPivot.addChildNode(exhaustCam)
        parts.exhaustCams[bankIndex] = exhaustCam
    }

    // MARK: - Animation

    static func animate(parts: ProceduralEngineParts, crankAngle: Double) {
        parts.crankshaft?.eulerAngles.y = SCNFloat(crankAngle)

        let camAngle = crankAngle / 2.0
        for cam in parts.intakeCams { cam.eulerAngles.y = SCNFloat(camAngle) }
        for cam in parts.exhaustCams { cam.eulerAngles.y = SCNFloat(camAngle) }

        let r = parts.params.crankThrow
        let L = parts.params.rodLength
        let dur = parts.params.camDurationRadCam
        let maxLift = parts.params.camMaxLift

        for placement in parts.placements {
            // The crank pin's assembly-frame angle is (phaseOffset + crankAngle),
            // measured from +X around Y. In the bank's local frame (rotated by
            // bankAngleRad from assembly), the pin's effective angle becomes
            // (phaseOffset + crankAngle - bankAngleRad). The slider-crank
            // equations below take that as their crank-angle argument.
            let theta = crankAngle + placement.phaseOffsetRad - placement.bankAngleRad
            let pistonZ = sliderCrankWristPinHeight(crankAngle: theta, throw: r, rodLength: L)
            let rodAngle = -rodInclination(crankAngle: theta, throw: r, rodLength: L)

            let idx = placement.cylinderNumber - 1
            let zPos = Float(pistonZ)
            let yPos = Float(placement.yOffset)

            parts.pistons[idx].position = SCNVector3(0, yPos, zPos)
            parts.wristPins[idx].position = SCNVector3(0, yPos, zPos)

            let rodNode = parts.rods[idx]
            rodNode.position = SCNVector3(0, yPos, zPos)
            rodNode.eulerAngles.y = SCNFloat(rodAngle)

            // Valves
            guard let vs = parts.valveSetsByCylinder[idx] else { continue }
            let intakeLift = camLift(lobePeakAngleRad: vs.intakeLobePeakRad,
                                     camRotationRad: camAngle,
                                     durationRadCam: dur,
                                     maxLift: maxLift)
            let exhaustLift = camLift(lobePeakAngleRad: vs.exhaustLobePeakRad,
                                      camRotationRad: camAngle,
                                      durationRadCam: dur,
                                      maxLift: maxLift)
            let valveYHalf = parts.params.bore * valveYHalfPitchFactorOfBore
            let intakeZ = Float(vs.valveSeatZ - intakeLift)
            let exhaustZ = Float(vs.valveSeatZ - exhaustLift)

            for (i, valve) in vs.intakeValves.enumerated() {
                let ySign: Float = (i == 0) ? -1 : 1
                valve.position = SCNVector3(Float(parts.params.intakeCamLocalX),
                                            yPos + ySign * Float(valveYHalf),
                                            intakeZ)
            }
            for (i, valve) in vs.exhaustValves.enumerated() {
                let ySign: Float = (i == 0) ? -1 : 1
                valve.position = SCNVector3(Float(parts.params.exhaustCamLocalX),
                                            yPos + ySign * Float(valveYHalf),
                                            exhaustZ)
            }
        }
    }

    // MARK: - Damage visualization
    //
    // Per-frame: walk over each tracked part and set its material emission
    // colour to a red tint whose intensity is the part's damage (0..1).
    // The stock material diffuse is preserved; emission ADDS red on top,
    // giving a "warming up / glowing hot" appearance that scales smoothly
    // with severity.
    static func applyDamageTints(
        parts: ProceduralEngineParts,
        cylinderHealths: [CylinderHealthState],
        engineWide: EngineWideHealthState
    ) {
        // Per-cylinder parts.
        let n = min(cylinderHealths.count, parts.pistons.count)
        for i in 0..<n {
            let c = cylinderHealths[i]
            tintNodeTree(parts.pistons[i],   damage: 1.0 - c.piston)
            if i < parts.rods.count {
                tintNodeTree(parts.rods[i],  damage: 1.0 - c.rod)
            }
            if i < parts.wristPins.count {
                // Pin shares fate with the piston for visual cohesion.
                tintNodeTree(parts.wristPins[i], damage: 1.0 - c.piston)
            }
            // Valves: tint per intake/exhaust health.
            if i < parts.valveSetsByCylinder.count,
               let vs = parts.valveSetsByCylinder[i] {
                let intakeDmg  = 1.0 - c.intakeValve
                let exhaustDmg = 1.0 - c.exhaustValve
                for v in vs.intakeValves  { tintNodeTree(v, damage: intakeDmg) }
                for v in vs.exhaustValves { tintNodeTree(v, damage: exhaustDmg) }
            }
        }

        // Engine-wide parts.
        let crankDmg = 1.0 - engineWide.crankshaft
        if let crank = parts.crankshaft {
            tintNodeTree(crank, damage: crankDmg)
        }
        let camDmg = 1.0 - engineWide.camshaft
        for cam in parts.intakeCams  { tintNodeTree(cam, damage: camDmg) }
        for cam in parts.exhaustCams { tintNodeTree(cam, damage: camDmg) }
        let headDmg = 1.0 - engineWide.cylinderHead
        for head in parts.heads      { tintNodeTree(head, damage: headDmg) }
    }

    /// Apply red-emission tint to every material in the node subtree. A small
    /// deadzone keeps near-pristine parts visually unchanged.
    private static func tintNodeTree(_ root: SCNNode, damage: Double) {
        let d = max(0.0, min(1.0, damage))
        // Deadzone: parts under 8% damage stay visually clean. Prevents
        // every part looking faintly pink during normal driving.
        let intensity: CGFloat
        if d < 0.08 {
            intensity = 0
        } else {
            let t = (d - 0.08) / 0.92      // 0..1 above deadzone
            // Bright red, capped at 0.85 so it doesn't fully blow out the
            // material's underlying color/shading.
            intensity = CGFloat(0.85 * t)
        }
        let color: PlatformColor
        if intensity <= 0 {
            color = PlatformColor.black
        } else {
            color = PlatformColor(red: intensity,
                                  green: 0,
                                  blue: 0,
                                  alpha: 1.0)
        }
        applyEmission(to: root, color: color)
    }

    private static func applyEmission(to root: SCNNode, color: PlatformColor) {
        if let materials = root.geometry?.materials {
            for material in materials {
                material.emission.contents = color
            }
        }
        for child in root.childNodes {
            applyEmission(to: child, color: color)
        }
    }
}
