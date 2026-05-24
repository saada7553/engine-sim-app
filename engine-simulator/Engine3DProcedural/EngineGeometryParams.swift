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

/// Max extent of the crank web/counterweight from the main journal centerline,
/// expressed as a multiple of crank throw (stroke/2). The web outline (kidney
/// shape) tip on the counterweight side reaches this distance from the journal.
private let counterweightReachFactorOfThrow: Double = 1.8

/// Counterweight tip radius as a fraction of the total counterweight reach.
/// Larger value = chunkier tip, narrower neck.
private let counterweightTipRadiusFactorOfReach: Double = 0.55

/// Web slab thickness along the crank axis (Y), in bore units.
private let crankWebPlateThicknessFactorOfBore: Double = 0.10

/// Pin-side boss radius in the web outline, as a fraction of crank throw.
/// Ensures the web surrounds the rod pin with visible material.
private let pinBossRadiusFactorOfThrow: Double = 0.55

/// Connecting-rod big-end thickness (along the crank-pin axis) as a fraction
/// of bore. This is the rod-bearing width that drives both rod rendering and
/// the bank axial offset for V/flat engines.
private let rodBearingWidthFactorOfBore: Double = 0.22

/// Padding around parts when sizing the block envelope, as a fraction of bore.
private let crankCaseSidePadding: Double = 0.25   // around counterweight reach
private let crankCaseBottomPadding: Double = 0.18 // below counterweight reach
private let crankCaseTopMargin: Double = 0.12     // above counterweight reach
private let bankSlabHalfWidthFactorOfBore: Double = 0.85 // ± side padding for cylinder
private let pistonValveClearanceFactorOfBore: Double = 0.05 // min gap between piston-TDC and a fully-open valve
// Each end needs at least bore/2 (piston radius) + margin so end cylinders
// don't clip. Total per-axis margin = 2 × this × bore.
private let blockEndsClearanceFactorOfBore: Double = 1.5

// MARK: - Valvetrain proportions
//
// Layering from the deck up (in bank-local +Z):
//   deck top → valve seat (just below deck) → stem extends up → cam base circle
//   touches the stem top → head top sits above the cam's lobe-peak reach.
// The valve stem length is the only free parameter; cam Z and head height are
// derived so the stem top exactly meets the cam base circle and the head
// comfortably encloses the lobe peak.

private let camShaftRadiusFactorOfBore: Double = 0.07
private let camLobeThicknessFactorOfBore: Double = 0.18
private let cylinderHalfPlaceForCamFactor: Double = 0.36    // intake/exhaust cam X-offset (× bore)
private let valveStemRadiusFactorOfBore: Double = 0.025
private let valveHeadRadiusFactorOfBore: Double = 0.22
private let valveStemLengthFactorOfBore: Double = 0.50      // visual stem length
/// Small gap (× bore) between stem top and cam base circle so the relationship
/// reads clearly. Stem length is shortened by this amount.
private let stemCamGapFactorOfBore: Double = 0.025
/// Disc thickness of the valve head (must match ValveGeometry.valveHeadThicknessFactorOfBore).
let valveHeadThicknessFactorOfBore: Double = 0.04
private let valveSeatBelowDeckFactor: Double = 0.04         // valve seat sits just below deck
private let headTopMarginAboveCamFactor: Double = 0.20      // × bore: clearance above cam peak

/// Maximum lift/base ratio for the rendered cam profile. The builder's 2D
/// preview shows a pronounced lobe by using a constant 50px base + 4px/mm
/// lift, giving ratios up to ~0.75 even for big lifts. We cap our visual
/// baseRadius so lift/base never falls below this — the 3D lobe then reads
/// as a real cam silhouette rather than a near-circle.
private let camVisualLiftOverBaseTarget: Double = 0.65

private let inchToM: Double = 0.0254
private let mmToMVal: Double = 0.001  // duplicate alias for clarity in cam fields

struct CylinderPlacement {
    let cylinderNumber: Int      // 1-indexed (matches EngineSpec.firingOrder entries)
    let bankIndex: Int           // 0 or 1
    let slotIndex: Int           // position along crank axis, 0-indexed
    let firingPosition: Int      // 0-indexed position in the firing-order sequence
    let yOffset: Double          // meters from engine origin along crank axis (includes bank-axial offset for V/Flat)
    let slotCenterY: Double      // crank-throw Y for this cylinder's slot (= yOffset for inline; midpoint of paired banks for V/Flat)
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
    let rodBearingWidth: Double      // big-end (and small-end) thickness along pin axis

    // Crank-throw layout
    /// Half the Y-extent of the rod-bearing region on each throw. Inline engines
    /// have one rod per throw (rodBearingWidth/2); V/Flat engines stack two rods
    /// side by side (rodBearingWidth).
    let rodSpanHalf: Double
    /// Thickness of each crank-web slab along Y.
    let crankWebPlateThickness: Double
    /// Y position of each web's outer face relative to the slot center
    /// (= rodSpanHalf + crankWebPlateThickness/2). Web nodes sit at slot ± this.
    let crankWebCenterOffset: Double
    /// Pin-side boss radius in the web outline.
    let crankPinBossRadius: Double
    /// X offset of the counterweight tip center from the main journal (throw-local).
    let counterweightTipOffset: Double
    /// Counterweight tip radius in the web outline.
    let counterweightTipRadius: Double
    /// Max extent of any crank-web feature from the main journal centerline.
    /// Used for crankcase sizing so the counterweight reach never clips the case.
    let counterweightReach: Double

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
    /// Length of a single bank's slab along Y. Equals the per-bank cylinder
    /// span plus end clearance; shorter than `blockLength` on V/Flat engines
    /// because each bank's bores cover only its own (shifted) slots.
    let bankSlabLength: Double

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
    /// Axial (Y) offset applied per bank so paired V/Flat rods sit side-by-side
    /// on a shared crank throw. Bank 0 shifts by -bankAxialShift, bank 1 by
    /// +bankAxialShift. Zero for inline engines.
    let bankAxialShift: Double

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
        self.rodBearingWidth = bore * rodBearingWidthFactorOfBore

        // Throw layout: each cylinder has its own crank pin at its own phase
        // angle (split-pin design). V/Flat engines therefore have 2× the
        // throws of the inline equivalent, packed side-by-side per slot. This
        // keeps the visual correct for any firing order, including those where
        // two cylinders on the same slot don't reach TDC together.
        let webPlateThick = bore * crankWebPlateThicknessFactorOfBore
        self.rodSpanHalf = bore * rodBearingWidthFactorOfBore / 2.0
        self.crankWebPlateThickness = webPlateThick
        self.crankWebCenterOffset = self.rodSpanHalf + webPlateThick / 2.0

        let cwReach = crankThrow * counterweightReachFactorOfThrow
        let cwTipR = cwReach * counterweightTipRadiusFactorOfReach
        self.counterweightReach = cwReach
        self.counterweightTipRadius = cwTipR
        self.counterweightTipOffset = cwReach - cwTipR
        // Pin boss radius: enclose the crank pin with visible material, with a
        // floor tied to crank throw so it scales reasonably with engine size.
        self.crankPinBossRadius = max(self.crankPinDiameter / 2.0 + bore * 0.04,
                                      crankThrow * pinBossRadiusFactorOfThrow)

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

        // For V/flat engines, offset the two banks along the crank axis so
        // their connecting rods don't intersect each other. The shift is one
        // full rod-bearing width per side: with the rod's I-beam flanges being
        // rodBearingWidth wide along Y, this leaves a clear rodBearingWidth gap
        // between the two rods at the slot — matching what real V engines do.
        let bankAxialShift: Double = (layout.bankCount == 2) ? (bore * rodBearingWidthFactorOfBore) : 0.0
        self.bankAxialShift = bankAxialShift

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
                // Place by cylinder number (odd → bank0, even → bank1), matching
                // MRWriter's bank split and the builder's firing-order graphic. The
                // firing *phase* stays keyed to firing position via phaseOffsetRad /
                // camPhaseOffsetRad, so cylinders still fire in the right order — they
                // just now fire in their correct physical location.
                bankIndex = (cylNumber - 1) % 2
                slotIndex = (cylNumber - 1) / 2
            }
            let bankSign: Double = (bankIndex == 0) ? 1.0 : -1.0
            let bankAxialOffset: Double = (bankIndex == 0) ? -bankAxialShift : +bankAxialShift

            let slotCenter = firstSlotY + Double(slotIndex) * cylinderPitch
            placements.append(CylinderPlacement(
                cylinderNumber: cylNumber,
                bankIndex: bankIndex,
                slotIndex: slotIndex,
                firingPosition: position,
                yOffset: slotCenter + bankAxialOffset,
                slotCenterY: slotCenter,
                bankAngleRad: bankSign * halfAngle,
                phaseOffsetRad: phaseRad,
                camPhaseOffsetRad: camPhaseRad
            ))
        }

        self.cylinders = placements

        // ----- Cylinder head + valvetrain proportions -----
        // Head dimensions in X are independent of cam Z; the height is derived
        // below once the cam Z is known so the head always encloses the cam.
        self.headHalfWidth = bore * 1.05

        self.camShaftRadius = bore * camShaftRadiusFactorOfBore
        let maxLift = spec.camLiftMm * mmToMVal
        // Visual base radius: cap so lift/base stays at least camVisualLiftOverBaseTarget.
        // The real cam base from EngineSpec is used as an upper bound; we never
        // INFLATE it, only shrink when the lobe would otherwise look like a circle.
        let realBaseR = spec.camBaseRadiusIn * inchToM
        let cappedBaseR = maxLift / camVisualLiftOverBaseTarget
        let camBaseR = min(realBaseR, cappedBaseR)
        self.camBaseRadius = camBaseR
        self.camMaxLift = maxLift
        self.camLobeThickness = bore * camLobeThicknessFactorOfBore
        self.intakeCamLocalX = bore * cylinderHalfPlaceForCamFactor
        self.exhaustCamLocalX = -bore * cylinderHalfPlaceForCamFactor
        self.camDurationRadCam = spec.camDurationDeg * degToRad
        self.camLobeSeparationRadCam = spec.camLobeSeparationDeg * degToRad
        self.camAdvanceRadCam = spec.camAdvanceDeg * degToRad

        self.valveStemRadius = bore * valveStemRadiusFactorOfBore
        self.valveHeadRadius = bore * valveHeadRadiusFactorOfBore
        // Shorten the stem by stemCamGap so a tiny visible gap appears between
        // the stem top and the cam base circle.
        self.valveStemLength = bore * (valveStemLengthFactorOfBore - stemCamGapFactorOfBore)

        // ----- Block envelope (crankcase + per-bank slabs) -----
        let ccBottom = -self.counterweightReach - bore * crankCaseBottomPadding
        let ccTop = self.counterweightReach + bore * crankCaseTopMargin

        // Crankcase X-extent must clear the counterweight swing in every direction.
        let ccHalfWidth = self.counterweightReach + bore * crankCaseSidePadding

        // Bank slab top (= block deck) must clear a fully-open valve by at
        // least pistonValveClearance above piston-TDC. The valve head sits a
        // tiny bit below the deck (valveSeatBelowDeckFactor × bore), and at
        // max lift dips down by camMaxLift, so:
        //   valveAtMaxLift = deckTop - valveSeatBelowDeck - camMaxLift
        // We require valveAtMaxLift ≥ deckHeight + pistonValveClearance, giving
        //   deckTop ≥ deckHeight + pistonValveClearance + valveSeatBelowDeck + camMaxLift.
        let pistonValveClearance = bore * pistonValveClearanceFactorOfBore
        let valveSeatBelowDeck = bore * valveSeatBelowDeckFactor
        let deckTop = deckHeight + pistonValveClearance + valveSeatBelowDeck + maxLift
        let bankSlabHalfW = bore * bankSlabHalfWidthFactorOfBore

        self.crankCaseHalfWidth = ccHalfWidth
        self.crankCaseBottomZ = ccBottom
        self.crankCaseTopZ = ccTop
        self.bankSlabHalfWidth = bankSlabHalfW
        self.bankSlabBottomZ = ccTop
        self.bankSlabTopZ = deckTop

        // Each bank's slab spans only its own cylinders. Inline matches the
        // crankcase length; V/Flat is shorter (just the bank's cylinder span).
        let perBankSlotSpan = Double(usedSlotCount - 1) * cylinderPitch
        self.bankSlabLength = perBankSlotSpan + bore * blockEndsClearanceFactorOfBore

        // Derive cam Z and head height from the valve geometry so the stem top
        // clears the cam base circle by `stemCamGap`. The valve node origin
        // sits at the seat Z; inside it, the head disc occupies the first
        // valveHeadThickness of +Z, and the stem extends above the head for
        // `valveStemLength`. Cam base bottom = stemTop + stemCamGap.
        let seatZ = deckTop - valveSeatBelowDeck
        let valveHeadThickness = bore * valveHeadThicknessFactorOfBore
        let stemTopZ = seatZ + valveHeadThickness + self.valveStemLength
        let camZ = stemTopZ + bore * stemCamGapFactorOfBore + camBaseR
        let headTop = camZ + camBaseR + maxLift + bore * headTopMarginAboveCamFactor

        self.headBottomZ = deckTop
        self.headTopZ = headTop
        self.headHeight = headTop - deckTop
        self.camLocalZ = camZ
        self.valveSeatZ = seatZ

        // Overall AABB envelope (used only for camera framing).
        let firstY = placements.map(\.yOffset).min() ?? 0
        let lastY = placements.map(\.yOffset).max() ?? 0
        self.blockLength = (lastY - firstY) + bore * blockEndsClearanceFactorOfBore

        // Compute max world-X extent after each bank's rotation around Y. The
        // head sits above the bank slab, so the highest point per bank is the
        // outer-top corner of the head: (±headHalfWidth, ?, headTopZ) rotated.
        let bankCornerX = sin(halfAngle) * self.headTopZ + cos(halfAngle) * headHalfWidth
        let envHalfWidth = max(ccHalfWidth, bankCornerX)
        self.blockWidth = envHalfWidth * 2.0

        // Z envelope spans the crankcase bottom to the head's highest reach.
        let bankCornerZ = cos(halfAngle) * self.headTopZ + sin(halfAngle) * headHalfWidth
        let envTopZ = max(ccTop, bankCornerZ)
        self.blockHeight = envTopZ - ccBottom
        self.blockCenterZ = (envTopZ + ccBottom) / 2.0
    }
}

// MARK: - Cam timing helpers
//
// All cam angles live in the SCNNode Y-rotation convention used to drive both
// the crankshaft and the camshaft (eulerAngles.y, positive = CW viewed from
// +Y). In that convention a feature initially at +X rotates by α ends up
// pointing at direction (cos α, −sin α), so its "rotation angle" is α and the
// follower (sitting at −Z below the cam) corresponds to α = +π/2.
//
// Derivation of intake/exhaust peaks for a cylinder at firing position p:
//   compression TDC of cyl p happens at cam angle camPhaseOffset (= p·2π/N).
//   Overlap TDC is one crank revolution later → cam = camPhaseOffset + π.
//   Intake centerline (cam) = overlap + LSA/2 − advance.
//   Exhaust centerline (cam) = overlap − LSA/2 − advance.
//   The lobe is built with its peak at +X. Rotating the cam by `cam` puts
//   the (already-pre-rotated by peakAngleRad) peak at rotation angle
//   peakAngleRad + cam. Setting that to π/2 at the relevant centerline gives:
//     intake : peakAngleRad = −π/2 − camPhaseOffset − LSA/2 + advance
//     exhaust: peakAngleRad = −π/2 − camPhaseOffset + LSA/2 + advance

/// Lobe peak angle for a cylinder's intake cam lobe (SCN rotation convention).
func intakeLobePeak(for placement: CylinderPlacement, params p: EngineGeometryParams) -> Double {
    return -.pi / 2.0 - placement.camPhaseOffsetRad - (p.camLobeSeparationRadCam / 2.0) + p.camAdvanceRadCam
}

/// Lobe peak angle for a cylinder's exhaust cam lobe (SCN rotation convention).
func exhaustLobePeak(for placement: CylinderPlacement, params p: EngineGeometryParams) -> Double {
    return -.pi / 2.0 - placement.camPhaseOffsetRad + (p.camLobeSeparationRadCam / 2.0) + p.camAdvanceRadCam
}

/// Cam lift at the follower (rotation angle +π/2) given the lobe's design peak
/// angle and the current cam rotation. Lift is 0 outside the lobe duration and
/// follows a smooth cos² ramp inside it.
func camLift(lobePeakAngleRad: Double,
             camRotationRad: Double,
             durationRadCam: Double,
             maxLift: Double) -> Double {
    let followerAngle: Double = .pi / 2.0
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
