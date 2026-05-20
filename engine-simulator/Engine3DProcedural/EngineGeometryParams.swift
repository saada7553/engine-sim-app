//
//  EngineGeometryParams.swift
//  engine-simulator
//
//  Derives all 3D geometry constants (in meters / radians) and per-cylinder
//  placement data from a high-level EngineSpec. Every procedural part and the
//  animation loop reads from one of these structs, so the model stays in lock
//  step with the configuration the user set in the builder.
//

import Foundation

private let mmToM: Double = 0.001
private let degToRad: Double = .pi / 180.0

/// 4-stroke crank rotation between successive cylinder firings (720° / N).
private let fourStrokeCycleDeg: Double = 720.0

// MARK: - Proportional sizing factors (all dimensionless)

/// Fraction of bore used as cylinder-to-cylinder spacing along the crank axis.
private let cylinderPitchFactorOfBore: Double = 1.30

/// Wrist-pin diameter / length as a fraction of bore.
private let wristPinDiameterFactorOfBore: Double = 0.22
private let wristPinLengthFactorOfBore: Double = 0.90

/// Crank pin (rod journal) diameter relative to bore.
private let crankPinDiameterFactorOfBore: Double = 0.45

/// Main bearing journal diameter relative to bore.
private let mainJournalDiameterFactorOfBore: Double = 0.55

/// Counterweight outer radius relative to crank throw (stroke/2).
private let counterweightRadiusFactorOfThrow: Double = 1.5

/// Counterweight thickness (along crank axis) relative to throw.
private let counterweightThicknessFactorOfThrow: Double = 0.55

/// Crank-web thickness (the flat plate joining adjacent journals).
private let crankWebThicknessFactorOfThrow: Double = 0.35

/// Piston body height as a fraction of bore.
private let pistonHeightFactorOfBore: Double = 0.75

/// Connecting-rod big-end thickness (along the crank-pin axis) as a fraction
/// of bore. This is the rod-bearing width that drives both rod rendering and
/// the bank axial offset for V/flat engines.
private let rodBearingWidthFactorOfBore: Double = 0.22

/// Padding around parts when sizing the block envelope, as a fraction of bore.
private let crankCaseSidePadding: Double = 0.25   // around counterweight reach
private let crankCaseBottomPadding: Double = 0.18 // below counterweight reach
private let crankCaseTopMargin: Double = 0.12     // above counterweight reach
private let bankSlabHalfWidthFactorOfBore: Double = 0.85 // ± side padding for cylinder
private let deckClearanceFactorOfBore: Double = 0.10     // block deck above piston-TDC
private let blockEndsClearanceFactorOfBore: Double = 0.55 // along the crank axis (Y)
private let counterweightReachFactor: Double = 1.35      // disc offset (0.35) + disc radius (1.0)

// MARK: - Valvetrain proportions

private let cylinderHeadHeightFactorOfBore: Double = 0.85   // head extrudes this far above the deck
private let camShaftRadiusFactorOfBore: Double = 0.07
private let camLobeThicknessFactorOfBore: Double = 0.18
private let camLocalZAboveDeckFactor: Double = 0.55         // cam centerline above the deck (× bore)
private let cylinderHalfPlaceForCamFactor: Double = 0.36    // intake/exhaust cam X-offset (× bore)
private let valveStemRadiusFactorOfBore: Double = 0.025
private let valveHeadRadiusFactorOfBore: Double = 0.22
private let valveStemLengthFactorOfBore: Double = 0.85
private let valveSeatBelowDeckFactor: Double = 0.04         // valve seat sits just below deck

private let inchToM: Double = 0.0254
private let mmToMVal: Double = 0.001  // duplicate alias for clarity in cam fields

struct CylinderPlacement {
    let cylinderNumber: Int      // 1-indexed (matches EngineSpec.firingOrder entries)
    let bankIndex: Int           // 0 or 1
    let slotIndex: Int           // position along crank axis, 0-indexed
    let firingPosition: Int      // 0-indexed position in the firing-order sequence
    let yOffset: Double          // meters from engine origin along crank axis
    let bankAngleRad: Double     // signed rotation of this bank's bore axis from vertical
    let phaseOffsetRad: Double   // crank angle (rad) at which this piston reaches TDC, mod 2π
    let camPhaseOffsetRad: Double // cam angle (rad) at this cylinder's TDC compression
}

struct EngineGeometryParams {
    let bore: Double                 // m
    let stroke: Double               // m
    let rodLength: Double            // m
    let compressionHeight: Double    // m
    let crankThrow: Double           // m  (stroke / 2)
    let deckHeight: Double           // m  (crank axis → piston-top at TDC)

    // Derived part sizes
    let cylinderPitch: Double        // m, distance between adjacent cylinder slots along crank axis
    let wristPinDiameter: Double
    let wristPinLength: Double
    let crankPinDiameter: Double
    let mainJournalDiameter: Double
    let counterweightRadius: Double
    let counterweightThickness: Double
    let crankWebThickness: Double
    let pistonHeight: Double
    let rodBearingWidth: Double      // big-end (and small-end) thickness along pin axis

    // Block envelope (axis-aligned bounding box in the assembly's local frame
    // BEFORE the world rotation that puts bore-axis world-up). These are
    // overall dimensions used by the camera framer; the actual block geometry
    // builds itself out of a crankcase + per-bank slabs using the more
    // specific fields below.
    //   blockLength → along crank axis (Y)
    //   blockWidth  → across banks (X)
    //   blockHeight → along bore axis (Z)
    let blockLength: Double
    let blockWidth: Double
    let blockHeight: Double
    let blockCenterZ: Double         // Z position of block centroid (crank sits below center)

    // Crankcase dimensions (in assembly-local frame)
    let crankCaseHalfWidth: Double   // X
    let crankCaseBottomZ: Double     // Z, lower face
    let crankCaseTopZ: Double        // Z, upper face (bank slabs start here)

    // Bank slab dimensions (each bank uses one; rotated by ±bankHalfAngleRad)
    let bankSlabHalfWidth: Double    // X in bank-local frame
    let bankSlabBottomZ: Double      // Z in bank-local (= crankCaseTopZ for inline)
    let bankSlabTopZ: Double         // Z in bank-local (piston deck + clearance)

    // Cylinder head (one per bank). Sits directly above the bank slab.
    let headHeight: Double           // Z extent above bankSlabTopZ
    let headHalfWidth: Double        // X (bank-local)
    let headBottomZ: Double          // = bankSlabTopZ
    let headTopZ: Double             // = bankSlabTopZ + headHeight

    // Camshaft / valvetrain
    let camShaftRadius: Double
    let camBaseRadius: Double        // base-circle radius (from EngineSpec.camBaseRadiusIn)
    let camMaxLift: Double           // peak lobe lift above base circle (from camLiftMm)
    let camLobeThickness: Double     // along the cam axis (Y)
    let intakeCamLocalX: Double      // X offset of intake cam center (+X side)
    let exhaustCamLocalX: Double     // X offset of exhaust cam center (-X side)
    let camLocalZ: Double            // Z position of cam centerlines (bank-local)
    let camDurationRadCam: Double    // lobe duration in CAM radians
    let camLobeSeparationRadCam: Double  // LSA in cam radians
    let camAdvanceRadCam: Double     // advance in cam radians (positive = earlier intake)

    let valveStemRadius: Double
    let valveHeadRadius: Double
    let valveStemLength: Double
    let valveSeatZ: Double           // Z in bank-local where the valve head seats

    // Layout cache (for downstream consumers)
    let bankCount: Int
    let bankHalfAngleRad: Double

    // Per-cylinder placement (one entry per cylinder, indexed by cylinderNumber-1)
    let cylinders: [CylinderPlacement]

    init(spec: EngineSpec) {
        self.bore = spec.boreMm * mmToM
        self.stroke = spec.strokeMm * mmToM
        self.rodLength = spec.rodLengthMm * mmToM
        self.compressionHeight = spec.compressionHeightMm * mmToM
        self.crankThrow = stroke / 2.0
        self.deckHeight = crankThrow + rodLength + compressionHeight

        self.cylinderPitch = bore * cylinderPitchFactorOfBore
        self.wristPinDiameter = bore * wristPinDiameterFactorOfBore
        self.wristPinLength = bore * wristPinLengthFactorOfBore
        self.crankPinDiameter = bore * crankPinDiameterFactorOfBore
        self.mainJournalDiameter = bore * mainJournalDiameterFactorOfBore
        self.counterweightRadius = crankThrow * counterweightRadiusFactorOfThrow
        self.counterweightThickness = crankThrow * counterweightThicknessFactorOfThrow
        self.crankWebThickness = crankThrow * crankWebThicknessFactorOfThrow
        self.pistonHeight = bore * pistonHeightFactorOfBore
        self.rodBearingWidth = bore * rodBearingWidthFactorOfBore

        let layout = spec.layout
        self.bankCount = layout.bankCount
        let cylindersPerBank = layout.cylinderCount / layout.bankCount
        let halfAngle = layout.bankHalfAngleDeg * degToRad
        self.bankHalfAngleRad = halfAngle

        // ----- Cylinder placement -----
        let firingOrder = spec.firingOrderIsValid ? spec.firingOrder : layout.firingOrder
        let degBetweenFires = fourStrokeCycleDeg / Double(layout.cylinderCount)

        var firingPositionByCylinder: [Int: Int] = [:]
        for (position, cylNumber) in firingOrder.enumerated() {
            firingPositionByCylinder[cylNumber] = position
        }

        var placements: [CylinderPlacement] = []
        placements.reserveCapacity(layout.cylinderCount)

        let usedSlotCount = max(cylindersPerBank, 1)
        let firstSlotY = -Double(usedSlotCount - 1) * cylinderPitch / 2.0

        // For V/flat engines, offset bank 1 forward along the crank axis by one
        // rod-bearing width so the paired rods sit side-by-side on a shared crank
        // throw instead of intersecting. Bank 0 shifts backward by the same amount,
        // keeping the engine centered.
        let bankAxialShift: Double = (layout.bankCount == 2) ? (bore * rodBearingWidthFactorOfBore / 2.0) : 0.0

        for cylNumber in 1...layout.cylinderCount {
            let position = firingPositionByCylinder[cylNumber] ?? (cylNumber - 1)
            let phaseDeg = (Double(position) * degBetweenFires).truncatingRemainder(dividingBy: 360.0)
            let phaseRad = phaseDeg * degToRad
            // Cam runs at half crank speed, so the cam-angle distance between
            // successive firings is (720°/N) / 2 = 360°/N = 2π/N cam radians.
            let camPhaseRad = Double(position) * (2.0 * .pi / Double(layout.cylinderCount))

            let bankIndex: Int
            let slotIndex: Int
            if layout.bankCount == 1 {
                bankIndex = 0
                slotIndex = cylNumber - 1
            } else {
                bankIndex = position % 2
                slotIndex = position / 2
            }
            let bankSign: Double = (bankIndex == 0) ? 1.0 : -1.0
            let bankAxialOffset: Double = (bankIndex == 0) ? -bankAxialShift : +bankAxialShift

            placements.append(CylinderPlacement(
                cylinderNumber: cylNumber,
                bankIndex: bankIndex,
                slotIndex: slotIndex,
                firingPosition: position,
                yOffset: firstSlotY + Double(slotIndex) * cylinderPitch + bankAxialOffset,
                bankAngleRad: bankSign * halfAngle,
                phaseOffsetRad: phaseRad,
                camPhaseOffsetRad: camPhaseRad
            ))
        }

        self.cylinders = placements

        // ----- Cylinder head + valvetrain proportions -----
        self.headHeight = bore * cylinderHeadHeightFactorOfBore
        self.headHalfWidth = bore * 1.05   // wider than the bank slab so cams fit inside
        // headBottomZ/headTopZ are filled after we know bankSlabTopZ below

        self.camShaftRadius = bore * camShaftRadiusFactorOfBore
        self.camBaseRadius = spec.camBaseRadiusIn * inchToM
        self.camMaxLift = spec.camLiftMm * mmToMVal
        self.camLobeThickness = bore * camLobeThicknessFactorOfBore
        self.intakeCamLocalX = bore * cylinderHalfPlaceForCamFactor
        self.exhaustCamLocalX = -bore * cylinderHalfPlaceForCamFactor
        self.camDurationRadCam = spec.camDurationDeg * degToRad
        self.camLobeSeparationRadCam = spec.camLobeSeparationDeg * degToRad
        self.camAdvanceRadCam = spec.camAdvanceDeg * degToRad

        self.valveStemRadius = bore * valveStemRadiusFactorOfBore
        self.valveHeadRadius = bore * valveHeadRadiusFactorOfBore
        self.valveStemLength = bore * valveStemLengthFactorOfBore

        // ----- Block envelope (crankcase + per-bank slabs) -----
        let counterweightReach = counterweightRadius * counterweightReachFactor
        let ccBottom = -counterweightReach - bore * crankCaseBottomPadding
        let ccTop = counterweightReach + bore * crankCaseTopMargin

        // Crankcase X-extent must clear the counterweight swing in every direction.
        let ccHalfWidth = counterweightReach + bore * crankCaseSidePadding

        // Bank slab: starts at the crankcase top, runs along the bank-local +Z to
        // a point slightly above piston-TDC. Width is just enough to cover the bore.
        let deckTop = deckHeight + bore * deckClearanceFactorOfBore
        let bankSlabHalfW = bore * bankSlabHalfWidthFactorOfBore

        self.crankCaseHalfWidth = ccHalfWidth
        self.crankCaseBottomZ = ccBottom
        self.crankCaseTopZ = ccTop
        self.bankSlabHalfWidth = bankSlabHalfW
        self.bankSlabBottomZ = ccTop
        self.bankSlabTopZ = deckTop

        // Fill head + cam Z positions now that bankSlabTopZ is known.
        self.headBottomZ = deckTop
        self.headTopZ = deckTop + bore * cylinderHeadHeightFactorOfBore
        self.camLocalZ = deckTop + bore * camLocalZAboveDeckFactor
        self.valveSeatZ = deckTop - bore * valveSeatBelowDeckFactor

        // Overall AABB envelope (used only for camera framing).
        let firstY = placements.map(\.yOffset).min() ?? 0
        let lastY = placements.map(\.yOffset).max() ?? 0
        self.blockLength = (lastY - firstY) + bore * blockEndsClearanceFactorOfBore

        // Compute max world-X extent after each bank's rotation around Y. The
        // head sits above the bank slab, so the highest point per bank is the
        // outer-top corner of the head: (±headHalfWidth, ?, headTop) rotated.
        let headTop = self.headTopZ
        let bankCornerX = sin(halfAngle) * headTop + cos(halfAngle) * headHalfWidth
        let envHalfWidth = max(ccHalfWidth, bankCornerX)
        self.blockWidth = envHalfWidth * 2.0

        // Z envelope spans the crankcase bottom to the head's highest reach.
        let bankCornerZ = cos(halfAngle) * headTop + sin(halfAngle) * headHalfWidth
        let envTopZ = max(ccTop, bankCornerZ)
        self.blockHeight = envTopZ - ccBottom
        self.blockCenterZ = (envTopZ + ccBottom) / 2.0
    }
}

// MARK: - Cam timing helpers

/// Lobe peak angle (in cam-local radians) for a cylinder's intake cam lobe.
/// Built so that when the cam has rotated to the intake centerline, the lobe
/// peak ends up at the follower direction (-π/2 in the cam's X-Z plane).
func intakeLobePeak(for placement: CylinderPlacement, params p: EngineGeometryParams) -> Double {
    return -(3.0 * .pi / 2.0) - placement.camPhaseOffsetRad - (p.camLobeSeparationRadCam / 2.0) + p.camAdvanceRadCam
}

/// Lobe peak angle (in cam-local radians) for a cylinder's exhaust cam lobe.
func exhaustLobePeak(for placement: CylinderPlacement, params p: EngineGeometryParams) -> Double {
    return -(3.0 * .pi / 2.0) - placement.camPhaseOffsetRad + (p.camLobeSeparationRadCam / 2.0) + p.camAdvanceRadCam
}

/// Cam lift at the follower direction (-π/2 in the cam's X-Z plane) given the
/// lobe's design peak angle and the current cam rotation. Lift is 0 outside the
/// lobe duration and follows a smooth cos² ramp inside it.
func camLift(lobePeakAngleRad: Double,
             camRotationRad: Double,
             durationRadCam: Double,
             maxLift: Double) -> Double {
    let followerAngle: Double = -.pi / 2.0
    let lobeWorldAngle = lobePeakAngleRad + camRotationRad
    let raw = followerAngle - lobeWorldAngle
    let wrapped = atan2(sin(raw), cos(raw))  // in [-π, π]
    let half = durationRadCam / 2.0
    guard abs(wrapped) < half, half > 0 else { return 0 }
    let normalized = wrapped * .pi / durationRadCam
    let c = cos(normalized)
    return maxLift * c * c
}

/// Slider-crank piston position along its bore axis, measured from the crank centerline.
/// Returns the Z (bore-axis) distance from crank center to wrist-pin center.
func sliderCrankWristPinHeight(crankAngle: Double,
                               throw r: Double,
                               rodLength L: Double) -> Double {
    let sinT = sin(crankAngle)
    let cosT = cos(crankAngle)
    let underRoot = max(L * L - r * r * sinT * sinT, 0)
    return r * cosT + sqrt(underRoot)
}

/// Connecting-rod inclination from the bore axis, given crank angle.
/// Positive when the big end sits at +X relative to the small end.
func rodInclination(crankAngle: Double,
                    throw r: Double,
                    rodLength L: Double) -> Double {
    let sinT = sin(crankAngle)
    return asin(min(max(r * sinT / L, -1.0), 1.0))
}
