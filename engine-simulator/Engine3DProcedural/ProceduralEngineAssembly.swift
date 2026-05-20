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
            pivot.eulerAngles.y = CGFloat(bankAngle)
            assembly.addChildNode(pivot)

            // Block slab is added separately in the engine block; head goes here
            // so it inherits the bank rotation.
            let head = CylinderHeadGeometry.makeNode(params: params)
            pivot.addChildNode(head)

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
            let v = ValveGeometry.makeNode(params: params)
            v.position = SCNVector3(Float(params.intakeCamLocalX),
                                    Float(placement.yOffset + ySign * valveYHalf),
                                    Float(params.valveSeatZ))
            bankPivot.addChildNode(v)
            return v
        }
        let exhaustValves: [SCNNode] = [-1.0, 1.0].map { ySign in
            let v = ValveGeometry.makeNode(params: params)
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
        let intakeLobes = cylinders.map {
            CamLobeSpec(yOffset: $0.yOffset,
                        peakAngleRad: intakeLobePeak(for: $0, params: params))
        }
        let exhaustLobes = cylinders.map {
            CamLobeSpec(yOffset: $0.yOffset,
                        peakAngleRad: exhaustLobePeak(for: $0, params: params))
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
        parts.crankshaft?.eulerAngles.y = CGFloat(crankAngle)

        let camAngle = crankAngle / 2.0
        for cam in parts.intakeCams { cam.eulerAngles.y = CGFloat(camAngle) }
        for cam in parts.exhaustCams { cam.eulerAngles.y = CGFloat(camAngle) }

        let r = parts.params.crankThrow
        let L = parts.params.rodLength
        let dur = parts.params.camDurationRadCam
        let maxLift = parts.params.camMaxLift

        for placement in parts.placements {
            let theta = crankAngle - placement.phaseOffsetRad
            let pistonZ = sliderCrankWristPinHeight(crankAngle: theta, throw: r, rodLength: L)
            let rodAngle = -rodInclination(crankAngle: theta, throw: r, rodLength: L)

            let idx = placement.cylinderNumber - 1
            let zPos = Float(pistonZ)
            let yPos = Float(placement.yOffset)

            parts.pistons[idx].position = SCNVector3(0, yPos, zPos)
            parts.wristPins[idx].position = SCNVector3(0, yPos, zPos)

            let rodNode = parts.rods[idx]
            rodNode.position = SCNVector3(0, yPos, zPos)
            rodNode.eulerAngles.y = CGFloat(rodAngle)

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
}
