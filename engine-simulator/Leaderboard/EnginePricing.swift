//
//  EnginePricing.swift
//  engine-simulator
//
//  Realistic part-cost model for an EngineSpec. Pure value-in / value-out —
//  no I/O, no UI — so it can drive the builder's live "Build $" readout and
//  the leaderboard's value/budget metrics from a single source of truth.
//
//  Philosophy: the price rises in the same direction a min-maxer pushes the
//  sliders, so chasing peak power costs money. The performance-enabling
//  extremes are deliberately the expensive ones:
//    - lightweight rotating parts (forged / titanium) cost MORE, not less
//    - high redlines scale steeply (valvetrain + materials)
//    - V / flat layouts carry a second-cylinder-head penalty
//    - alcohol fuels need a costlier fuel system
//    - high compression (small chamber), low blowby / crank friction, long
//      rods, big port flow, and slippery / low-rolling-resistance running gear
//      are all "free power" sliders unless they cost — so they do
//  The ignition timing curve and the gear/diff/tire RATIOS are intentionally
//  free — those are pure tuning skill, not hardware.
//
//  Every "free power" lever is baselined at the DEFAULT spec value, so a stock
//  build pays ~nothing for it and only optimization past stock adds cost; this
//  keeps the headline price for existing engines stable while closing the
//  low-hanging-fruit exploits.
//
//  All rates are named constants; calibration is meant to be tuned in one
//  place. Default I4 spec lands around $18k, a maxed exotic well into six
//  figures.
//

import Foundation

// MARK: - Breakdown

/// Per-section build cost in US dollars. Engine sections sum to `engineCost`
/// (drives the power/torque/value boards); drivetrain + chassis sum to
/// `vehicleCost`; `total` is the whole car (drives the race boards).
struct CostBreakdown: Equatable {
    var block: Double
    var rotatingAssembly: Double
    var camshaft: Double
    var cylinderHead: Double
    var induction: Double
    var exhaust: Double
    var redline: Double
    var fuelSystem: Double

    var clutch: Double
    var transmission: Double
    var chassis: Double

    var engineCost: Double {
        block + rotatingAssembly + camshaft + cylinderHead
            + induction + exhaust + redline + fuelSystem
    }
    var vehicleCost: Double { clutch + transmission + chassis }
    var total: Double { engineCost + vehicleCost }

    /// Ordered, labelled rows for a breakdown UI. Zero-cost rows are kept so
    /// the layout is stable as sliders move a section in and out of cost.
    var engineLineItems: [(label: String, cost: Double)] {
        [("Block & Cylinders", block),
         ("Rotating Assembly", rotatingAssembly),
         ("Camshaft", camshaft),
         ("Cylinder Head", cylinderHead),
         ("Induction", induction),
         ("Exhaust", exhaust),
         ("Redline / Valvetrain", redline),
         ("Fuel System", fuelSystem)]
    }

    var vehicleLineItems: [(label: String, cost: Double)] {
        [("Clutch", clutch),
         ("Transmission", transmission),
         ("Chassis & Tires", chassis)]
    }
}

// MARK: - Pricing

enum EnginePricing {

    // MARK: Block & cylinders
    private enum Block {
        static let base = 1_500.0            // machine shop / assembly floor
        static let perCylinder = 450.0       // bore, piston bore, valve seats
        static let perLitre = 650.0          // raw displacement (material + boring)
        static let secondHeadPenalty = 2_400.0   // V / flat: a whole extra head + cam drive
    }

    // MARK: Rotating assembly — lighter = pricier (forged / titanium)
    private enum Rotating {
        static let pistonRefMassG = 420.0    // a heavy cast piston is "free"
        static let pistonPerGramUnder = 2.5  // forged/light costs per gram saved, per cylinder
        static let rodRefMassG = 720.0
        static let rodPerGramUnder = 1.2     // per rod
        static let crankRefMassKg = 26.0     // a heavy cast crank is "free"
        static let crankPerKgUnder = 120.0   // billet / lightened
        static let flywheelRefMassKg = 16.0
        static let flywheelPerKgUnder = 90.0

        // Long rods (high rod/stroke ratio) need a taller block and a costlier
        // forging — the optimisation a min-maxer reaches for, so it's priced.
        static let rodLengthRefMm = 142.0    // default spec rod length is "free"
        static let perRodLengthMmOver = 55.0
        // Low crank friction = coated bearings / knife-edged crank / dry sump.
        static let crankFrictionRefLbFt = 5.0   // default friction is "free"
        static let perCrankFrictionLbFtUnder = 650.0
        // Low blowby = blueprinted bores + premium ring pack (a fresh, sealed
        // build). The default's slight blowby is "free"; a perfect seal is not.
        static let blowbyRef = 0.1
        static let perBlowbyUnder = 25_000.0    // tiny 0…0.1 range, so steep rate
    }

    // MARK: Camshaft
    private enum Cam {
        static let durationBaselineDeg = 200.0
        static let perDurationDeg = 28.0
        static let liftBaselineMm = 8.0
        static let perLiftMm = 320.0
        static let vtecFlatFee = 3_500.0     // variable valvetrain hardware
        static let vtecPerDurationDeg = 22.0 // the second, wilder profile
        static let vtecPerLiftMm = 240.0
    }

    // MARK: Cylinder head & ports
    private enum Head {
        static let portFlowBaseline = 1.0
        static let perPortFlowFraction = 6_000.0   // CNC porting above stock flow
        static let intakeRunnerAreaBaseInSq = 3.6
        static let perIntakeRunnerAreaInSq = 700.0
        static let exhaustRunnerAreaBaseInSq = 1.56
        static let perExhaustRunnerAreaInSq = 600.0
        // High compression = a small combustion chamber (deck clearance is zero
        // in this sim, so chamber volume is the ONLY compression lever). A
        // smaller chamber means forged pistons + race-fuel-grade build.
        static let chamberVolumeRefCc = 50.0       // default chamber is "free"
        static let perChamberCcUnder = 130.0
        // Per-runner flow capacity above stock = more port/valve work.
        static let runnerCfmRef = 200.0            // default runner flow is "free"
        static let perRunnerCfmOver = 4.0
    }

    // MARK: Induction
    private enum Induction {
        static let cfmBaseline = 450.0
        static let perCfm = 6.0              // bigger throttle body / ITBs
        static let plenumBaselineL = 1.0
        static let perPlenumLitre = 800.0
    }

    // MARK: Exhaust
    private enum Exhaust {
        static let collectorBoreBaselineIn = 1.75
        static let perCollectorBoreIn = 1_400.0
        static let primaryLengthBaselineIn = 20.0
        static let perPrimaryLengthIn = 40.0   // tuned-length / equal-length headers
    }

    // MARK: Redline / valvetrain — steep above the baseline
    private enum Redline {
        static let baselineRpm = 6_000.0
        static let perThousandSquared = 2_600.0   // quadratic in thousands above baseline
    }

    // MARK: Fuel system — surcharge over gasoline
    private enum Fuel {
        static func surcharge(_ preset: FuelPreset) -> Double {
            switch preset {
            case .gasoline: return 0
            case .e85:      return 1_800.0   // ethanol-rated lines, bigger injectors
            case .methanol: return 4_000.0   // corrosion-rated everything, huge flow
            case .diesel:   return 6_500.0   // high-pressure direct injection
            }
        }
    }

    // MARK: Drivetrain & chassis
    private enum Clutch {
        static let baselineLbFt = 350.0
        static let perLbFt = 6.0             // multi-plate, higher clamp
    }
    private enum Transmission {
        static let baselineGearCount = 5
        static let perExtraGear = 2_200.0
    }
    private enum Chassis {
        static let massRefLb = 3_600.0       // a heavy steel car is "free"
        static let perLbUnder = 9.0          // lightweighting (carbon / alloy)
        static let dragRef = 0.42            // a barn-door body is "free"
        static let perDragFractionUnder = 22_000.0   // slippery body / aero
        static let sqInPerSqFt = 144.0
        // Drag force is Cd × frontal area, so a small frontal area is free aero
        // unless it's priced too. Baselined at the default 66×50 in body.
        static let frontalAreaRefFtSq = 66.0 * 50.0 / sqInPerSqFt
        static let perFrontalAreaFtSqUnder = 420.0
        // Low rolling resistance = race tyres + low-drag wheel bearings.
        static let rollingResistanceRefN = 500.0      // default running gear is "free"
        static let perRollingResistanceNUnder = 5.0
    }

    // MARK: - Entry point

    static func price(for spec: EngineSpec) -> CostBreakdown {
        CostBreakdown(
            block: blockCost(spec),
            rotatingAssembly: rotatingCost(spec),
            camshaft: camCost(spec),
            cylinderHead: headCost(spec),
            induction: inductionCost(spec),
            exhaust: exhaustCost(spec),
            redline: redlineCost(spec),
            fuelSystem: Fuel.surcharge(spec.fuel),
            clutch: clutchCost(spec),
            transmission: transmissionCost(spec),
            chassis: chassisCost(spec)
        )
    }

    /// Convenience for callers that only need the headline number.
    static func buildCost(for spec: EngineSpec) -> Double { price(for: spec).total }

    /// Whole-dollar currency string ("$18,240") shared by every cost surface.
    static func formatted(_ dollars: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: dollars.rounded())) ?? "$0"
    }

    // MARK: - Section helpers

    private static func blockCost(_ spec: EngineSpec) -> Double {
        let cylinders = Double(spec.layout.cylinderCount)
        let heads = spec.layout.bankCount > 1 ? Block.secondHeadPenalty : 0
        return Block.base
            + cylinders * Block.perCylinder
            + spec.displacementLitres * Block.perLitre
            + heads
    }

    private static func rotatingCost(_ spec: EngineSpec) -> Double {
        let cylinders = Double(spec.layout.cylinderCount)
        let piston = under(Rotating.pistonRefMassG, spec.pistonMassG)
            * Rotating.pistonPerGramUnder * cylinders
        let rod = under(Rotating.rodRefMassG, spec.rodMassG)
            * Rotating.rodPerGramUnder * cylinders
        let crank = under(Rotating.crankRefMassKg, spec.crankMassKg)
            * Rotating.crankPerKgUnder
        let flywheel = under(Rotating.flywheelRefMassKg, spec.flywheelMassKg)
            * Rotating.flywheelPerKgUnder
        let rodLength = over(Rotating.rodLengthRefMm, spec.rodLengthMm)
            * Rotating.perRodLengthMmOver
        let crankFriction = under(Rotating.crankFrictionRefLbFt, spec.crankFrictionLbFt)
            * Rotating.perCrankFrictionLbFtUnder
        let sealing = under(Rotating.blowbyRef, spec.blowby) * Rotating.perBlowbyUnder
        return piston + rod + crank + flywheel + rodLength + crankFriction + sealing
    }

    private static func camCost(_ spec: EngineSpec) -> Double {
        var cost = over(Cam.durationBaselineDeg, spec.camDurationDeg) * Cam.perDurationDeg
        cost += over(Cam.liftBaselineMm, spec.camLiftMm) * Cam.perLiftMm
        guard spec.vtecEnabled else { return cost }
        cost += Cam.vtecFlatFee
        cost += over(Cam.durationBaselineDeg, spec.vtecCamDurationDeg) * Cam.vtecPerDurationDeg
        cost += over(Cam.liftBaselineMm, spec.vtecCamLiftMm) * Cam.vtecPerLiftMm
        return cost
    }

    private static func headCost(_ spec: EngineSpec) -> Double {
        let porting = over(Head.portFlowBaseline, spec.portFlowScale) * Head.perPortFlowFraction
        let intake = over(Head.intakeRunnerAreaBaseInSq, spec.intakeRunnerAreaInSq)
            * Head.perIntakeRunnerAreaInSq
        let exhaust = over(Head.exhaustRunnerAreaBaseInSq, spec.exhaustRunnerAreaInSq)
            * Head.perExhaustRunnerAreaInSq
        let compression = under(Head.chamberVolumeRefCc, spec.chamberVolumeCc)
            * Head.perChamberCcUnder
        let runnerFlow = over(Head.runnerCfmRef, spec.runnerCfm) * Head.perRunnerCfmOver
        return porting + intake + exhaust + compression + runnerFlow
    }

    private static func inductionCost(_ spec: EngineSpec) -> Double {
        over(Induction.cfmBaseline, spec.intakeCfm) * Induction.perCfm
            + over(Induction.plenumBaselineL, spec.intakePlenumVolumeL) * Induction.perPlenumLitre
    }

    private static func exhaustCost(_ spec: EngineSpec) -> Double {
        over(Exhaust.collectorBoreBaselineIn, spec.exhaustCollectorBoreIn) * Exhaust.perCollectorBoreIn
            + over(Exhaust.primaryLengthBaselineIn, spec.exhaustPrimaryLengthIn) * Exhaust.perPrimaryLengthIn
    }

    private static func redlineCost(_ spec: EngineSpec) -> Double {
        let thousandsOver = over(Redline.baselineRpm, spec.redlineRpm) / 1_000.0
        return thousandsOver * thousandsOver * Redline.perThousandSquared
    }

    private static func clutchCost(_ spec: EngineSpec) -> Double {
        over(Clutch.baselineLbFt, spec.clutchTorqueLbFt) * Clutch.perLbFt
    }

    private static func transmissionCost(_ spec: EngineSpec) -> Double {
        let extra = max(0, spec.gearRatios.count - Transmission.baselineGearCount)
        return Double(extra) * Transmission.perExtraGear
    }

    private static func chassisCost(_ spec: EngineSpec) -> Double {
        let frontalAreaFtSq = spec.frontalAreaWidthIn * spec.frontalAreaHeightIn
            / Chassis.sqInPerSqFt
        return under(Chassis.massRefLb, spec.vehicleMassLb) * Chassis.perLbUnder
            + under(Chassis.dragRef, spec.dragCoefficient) * Chassis.perDragFractionUnder
            + under(Chassis.frontalAreaRefFtSq, frontalAreaFtSq) * Chassis.perFrontalAreaFtSqUnder
            + under(Chassis.rollingResistanceRefN, spec.rollingResistanceN)
                * Chassis.perRollingResistanceNUnder
    }

    // MARK: - Math helpers

    /// Cost magnitude for a value sitting ABOVE a baseline (0 at/below it).
    private static func over(_ baseline: Double, _ value: Double) -> Double {
        max(0, value - baseline)
    }

    /// Cost magnitude for a value sitting UNDER a reference (0 at/above it).
    /// Used where the performance direction is "smaller / lighter".
    private static func under(_ reference: Double, _ value: Double) -> Double {
        max(0, reference - value)
    }
}
