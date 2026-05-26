//
//  EngineDesignExpander.swift
//  engine-simulator
//
//  The procedural heavy-lifter: EngineIntent -> a complete, physically
//  consistent, ALWAYS-RUNNABLE EngineSpec. The model only supplies intent
//  (layout/character + a few explicit pins + feature tags); everything here is
//  deterministic engineering:
//    - geometry sized to hit the target displacement,
//    - breathing (CFM, runners, plenum) scaled WITH displacement so power
//      tracks size and nothing chokes,
//    - portFlowScale scaled with cylinder size (MRWriter's head curve is fixed),
//    - masses scaled with size, flywheel shaped by idle character,
//    - cam / ignition / exhaust / gearing / vehicle all derived and coupled,
//    - feature tags nudge specific fields,
//    - every field clamped to a safe range, firing order from the layout.
//
//  Framework-free / all-OS / unit-testable.
//

import Foundation

enum EngineDesignExpander {

    // MARK: - Limits

    private enum Limit {
        static let displacementL: ClosedRange<Double> = 0.5...30
        static let boreMm: ClosedRange<Double> = 60...110
        static let strokeMm: ClosedRange<Double> = 40...110
        static let rodLengthMm: ClosedRange<Double> = 100...260
        static let compressionHeightMm: ClosedRange<Double> = 18...50
        static let compressionRatio: ClosedRange<Double> = 7...14
        // Up to 1.35 so a high-rpm race build can run the short-stroke (very
        // oversquare) geometry that lets it actually rev — a 1.20 ceiling forced
        // every engine into a long enough stroke to choke the redline.
        static let boreStrokeRatio: ClosedRange<Double> = 0.85...1.35
        static let pistonMassG: ClosedRange<Double> = 120...700
        static let rodMassG: ClosedRange<Double> = 180...900
        static let crankMassKg: ClosedRange<Double> = 5...80
        static let flywheelMassKg: ClosedRange<Double> = 3...40
        static let flywheelRadiusIn: ClosedRange<Double> = 3...10
        static let crankFrictionLbFt: ClosedRange<Double> = 1...40
        static let camDurationDeg: ClosedRange<Double> = 190...290
        static let camLiftMm: ClosedRange<Double> = 7...16
        static let camLsaDeg: ClosedRange<Double> = 102...118
        static let camAdvanceDeg: ClosedRange<Double> = -10...10
        static let camBaseRadiusIn: ClosedRange<Double> = 0.4...1.2
        static let intakeRunnerVolumeCc: ClosedRange<Double> = 50...400
        static let intakeRunnerAreaInSq: ClosedRange<Double> = 1.0...5.0
        static let exhaustRunnerVolumeCc: ClosedRange<Double> = 25...200
        static let exhaustRunnerAreaInSq: ClosedRange<Double> = 0.7...3.5
        static let portFlowScale: ClosedRange<Double> = 0.6...3.0
        static let intakePlenumVolumeL: ClosedRange<Double> = 0.3...4.0
        static let intakePlenumAreaCm2: ClosedRange<Double> = 4...40
        static let intakeCfm: ClosedRange<Double> = 120...1400
        static let runnerCfm: ClosedRange<Double> = 60...600
        static let runnerLengthIn: ClosedRange<Double> = 5...16
        static let exhaustPrimaryLengthIn: ClosedRange<Double> = 10...40
        static let exhaustCollectorBoreIn: ClosedRange<Double> = 1.2...4.0
        static let exhaustLengthIn: ClosedRange<Double> = 40...200
        static let redlineRpm: ClosedRange<Double> = 3000...18000
        static let clutchTorqueLbFt: ClosedRange<Double> = 100...1500
        static let chamberVolumeCc: ClosedRange<Double> = 8...250
    }

    private static let ccPerLitre = 1000.0
    private static let referenceCylinderVolumeCc = 500.0   // MRWriter head curve is sized for ~0.5L

    // MARK: - Entry point

    static func expand(_ intent: EngineIntent) -> EngineSpec {
        let layout = (intent.layout ?? defaultLayout(intent)).productionSafe
        let n = Double(layout.cylinderCount)
        var displacementL = (intent.displacementL ?? defaultDisplacement(layout: layout, intent: intent))
            .clamped(to: Limit.displacementL)
        // Plausibility by vehicle: a bike isn't 6 litres, a truck isn't 1.5.
        switch intent.vehicleClass {
        case .motorcycle: displacementL = min(displacementL, 1.6)
        case .truck:      displacementL = max(displacementL, 3.5)
        default: break
        }
        let cylVolCc = displacementL * ccPerLitre / n

        var spec = EngineSpec.defaultSpec(name: intent.name.isEmpty ? "AI Engine" : intent.name,
                                          layout: layout)
        spec.id = UUID()
        spec.resyncFiringOrderForLayout()

        applyGeometry(&spec, intent: intent, cylVolCc: cylVolCc, n: n)
        applyMasses(&spec, intent: intent, displacementL: displacementL, cylVolCc: cylVolCc)
        applyStarterAndCondition(&spec, intent: intent, displacementL: displacementL)
        applyCam(&spec, intent: intent)
        applyBreathing(&spec, intent: intent, displacementL: displacementL, cylVolCc: cylVolCc)
        applyExhaust(&spec, intent: intent)
        applyIgnition(&spec, intent: intent, layout: layout, displacementL: displacementL)
        applyFuelAndSound(&spec, intent: intent)
        applyDrivetrain(&spec, intent: intent, layout: layout, displacementL: displacementL)
        applyVehicle(&spec, intent: intent)
        applyVtec(&spec, intent: intent)   // after cam + ignition so it can build on them

        return spec
    }

    // MARK: - Defaults for unspecified basics

    private static func defaultLayout(_ intent: EngineIntent) -> EngineLayout {
        switch intent.vehicleClass {
        case .motorcycle:                 return .inline4
        case .muscle, .truck, .raceCar:   return .v8_90
        case .supercar:                   return .v8_90
        case .sedan, .sportsCar, .lightweight: return .inline4
        }
    }

    private static func defaultDisplacement(layout: EngineLayout, intent: EngineIntent) -> Double {
        let perCyl: Double
        switch intent.vehicleClass {
        case .motorcycle:            perCyl = 0.30
        case .lightweight, .sportsCar: perCyl = 0.50
        case .sedan:                 perCyl = 0.45
        case .muscle, .truck:        perCyl = 0.70
        case .supercar, .raceCar:    perCyl = 0.55
        }
        return Double(layout.cylinderCount) * perCyl
    }

    private static func aspiration(_ intent: EngineIntent) -> DesignAspiration {
        intent.aspiration ?? (intent.has(.highBoost) ? .turbocharged : .naturallyAspirated)
    }

    /// The cam character actually used: never milder than the intended power
    /// level implies, so "high horsepower" gets a real cam even if the cam
    /// stage said "stock". (economy/stock/sport/race for weak/modest/strong/extreme.)
    private static func effectiveCam(_ intent: EngineIntent) -> DesignCamProfile {
        DesignCamProfile.from(rank: max(intent.camProfile.rank, intent.performance.rank))
    }

    /// Breathing/airflow multiplier from the intended power level.
    private static func performanceFlow(_ p: DesignPerformance) -> Double {
        switch p { case .weak: return 0.85; case .modest: return 1.0; case .strong: return 1.15; case .extreme: return 1.3 }
    }

    private static func boostLevel(_ intent: EngineIntent) -> Double {
        guard aspiration(intent).isForced else { return 0 }
        return intent.has(.highBoost) ? 0.85 : 0.55
    }

    // MARK: - Geometry

    private static func applyGeometry(_ spec: inout EngineSpec, intent: EngineIntent, cylVolCc: Double, n: Double) {
        let cam = effectiveCam(intent)
        var ratio: Double
        switch (intent.powerBand, cam) {
        case (.topEnd, _), (_, .race): ratio = 1.15
        case (.lowEnd, _), (_, .economy): ratio = 0.92
        default: ratio = 1.0
        }
        // A flat-out race engine goes very oversquare (big bore, short stroke) so
        // it can spin to F1-class rpm without exceeding safe piston speed.
        if intent.performance == .extreme { ratio += 0.12 }
        // A high-rev build runs a short stroke (oversquare) so mean piston speed
        // stays sane at high rpm — without this the piston-speed cap below drags
        // the redline right back down.
        if intent.has(.highRedline) { ratio += 0.12 }
        if intent.has(.bigBore)   { ratio += 0.08 }
        if intent.has(.longStroke) { ratio -= 0.10 }
        ratio = ratio.clamped(to: Limit.boreStrokeRatio)

        // cylVol = pi*(bore/2)^2*stroke, bore = ratio*stroke -> stroke = cbrt(4*cylVol/(pi*ratio^2))
        let strokeCm = cbrt(4.0 * cylVolCc / (Double.pi * ratio * ratio))
        let strokeMm = (strokeCm * 10.0).clamped(to: Limit.strokeMm)
        let boreMm = (ratio * strokeMm).clamped(to: Limit.boreMm)

        spec.strokeMm = strokeMm
        spec.boreMm = boreMm
        spec.rodLengthMm = (strokeMm * 1.65).clamped(to: Limit.rodLengthMm)
        spec.compressionHeightMm = (strokeMm * 0.37).clamped(to: Limit.compressionHeightMm)

        var cr = intent.compressionRatio ?? defaultCR(intent)
        if intent.has(.highCompression) { cr += 0.8 }
        if intent.has(.lowCompression)  { cr -= 1.0 }
        cr = cr.clamped(to: Limit.compressionRatio)
        // Size the chamber from the ACTUAL (clamped) cylinder volume, not the
        // requested target — otherwise a huge engine whose bore/stroke hit the
        // clamp gets an oversized chamber and an absurdly low CR.
        let actualCylVolCc = Double.pi * pow((boreMm / 10.0) / 2.0, 2) * (strokeMm / 10.0)
        spec.chamberVolumeCc = (actualCylVolCc / (cr - 1.0)).clamped(to: Limit.chamberVolumeCc)
    }

    private static func defaultCR(_ intent: EngineIntent) -> Double {
        if aspiration(intent).isForced { return aspiration(intent) == .supercharged ? 9.5 : 9.0 }
        switch effectiveCam(intent) {
        case .economy: return 10.0
        case .stock:   return 10.5
        case .sport:   return 11.0
        case .race:    return 11.5
        }
    }

    // MARK: - Masses

    private static func applyMasses(_ spec: inout EngineSpec, intent: EngineIntent, displacementL: Double, cylVolCc: Double) {
        let perCylL = cylVolCc / ccPerLitre
        var piston = 120 + 300 * perCylL
        var crank = 6 + displacementL * 4
        if intent.has(.lightweightInternals) { piston *= 0.8; crank *= 0.85 }

        spec.pistonMassG = piston.clamped(to: Limit.pistonMassG)
        spec.rodMassG = (spec.pistonMassG * 1.25).clamped(to: Limit.rodMassG)
        spec.crankMassKg = crank.clamped(to: Limit.crankMassKg)

        var flywheel = 4 + displacementL * 1.8
        switch intent.idle {
        case .smooth: flywheel *= 1.25
        case .mild:   break
        case .lumpy:  flywheel *= 0.7
        }
        if intent.has(.heavyFlywheel) { flywheel *= 1.4 }
        if intent.has(.lightFlywheel) { flywheel *= 0.6 }
        spec.flywheelMassKg = flywheel.clamped(to: Limit.flywheelMassKg)
        spec.flywheelRadiusIn = (5 + displacementL * 0.4).clamped(to: Limit.flywheelRadiusIn)
        spec.crankFrictionLbFt = (3 + displacementL * 3).clamped(to: Limit.crankFrictionLbFt)
    }

    // MARK: - Starter + condition (blowby)

    private static func applyStarterAndCondition(_ spec: inout EngineSpec, intent: EngineIntent, displacementL: Double) {
        // Bigger engines need more cranking torque and spin over slower. Shared
        // recommendation (size + cylinder count) so AI + manual match.
        spec.resyncStarterForLayout()

        // Blowby from the AI-judged condition: worn loses ring seal, fresh is perfect.
        switch intent.condition {
        case .worn:   spec.blowby = 0.7
        case .normal: spec.blowby = 0.1
        case .fresh:  spec.blowby = 0.0
        }
    }

    // MARK: - VTEC

    private static func applyVtec(_ spec: inout EngineSpec, intent: EngineIntent) {
        guard intent.vtec == true else { spec.vtecEnabled = false; return }
        spec.vtecEnabled = true
        // Crossover sits below redline, raised a little so the mild cam is
        // clearly running out of breath right as the high cam slams in. The high
        // cam is far wilder than the low one (big lift + duration jump, tight
        // lobe separation) so the switch lands as a violent surge, not a nudge.
        let crossoverCeiling = max(3500.0, spec.redlineRpm - 500)
        spec.vtecCrossoverRpm = (spec.redlineRpm * 0.66).clamped(to: 3000...crossoverCeiling)
        spec.vtecCamDurationDeg = (spec.camDurationDeg + 52).clamped(to: 240...312)
        spec.vtecCamLiftMm = (spec.camLiftMm + 4.5).clamped(to: 11...17)
        spec.vtecCamLobeSeparationDeg = (spec.camLobeSeparationDeg - 11).clamped(to: 95...114)
    }

    // MARK: - Cam

    private static func applyCam(_ spec: inout EngineSpec, intent: EngineIntent) {
        var (dur, lift, lsa, adv) = camBase(effectiveCam(intent))
        if intent.has(.bigCam)  { dur += 14; lift += 1.0 }
        if intent.has(.mildCam) { dur -= 12; lift -= 1.0 }
        if intent.has(.tightLSA) { lsa -= 3 }
        if intent.has(.wideLSA)  { lsa += 3 }

        spec.camDurationDeg = dur.clamped(to: Limit.camDurationDeg)
        spec.camLiftMm = lift.clamped(to: Limit.camLiftMm)
        spec.camLobeSeparationDeg = lsa.clamped(to: Limit.camLsaDeg)
        spec.camAdvanceDeg = adv.clamped(to: Limit.camAdvanceDeg)
        spec.camBaseRadiusIn = (0.6).clamped(to: Limit.camBaseRadiusIn)
    }

    private static func camBase(_ p: DesignCamProfile) -> (Double, Double, Double, Double) {
        switch p {
        case .economy: return (200, 8.5, 116, 2)
        case .stock:   return (218, 10.0, 113, 0)
        case .sport:   return (236, 11.5, 110, 0)
        case .race:    return (252, 13.0, 107, 0)
        }
    }

    // MARK: - Breathing (the main power lever)

    private static func applyBreathing(_ spec: inout EngineSpec, intent: EngineIntent, displacementL: Double, cylVolCc: Double) {
        let camFlow: Double
        switch effectiveCam(intent) {
        case .economy: camFlow = 0.85
        case .stock:   camFlow = 1.0
        case .sport:   camFlow = 1.15
        case .race:    camFlow = 1.30
        }
        let boostMul = 1 + 0.7 * boostLevel(intent)

        // Airflow tracks displacement, cam AND the intended power level so
        // "high horsepower" actually breathes (and makes) more than a mild build.
        spec.intakeCfm = (displacementL * 145 * camFlow * performanceFlow(intent.performance) * boostMul).clamped(to: Limit.intakeCfm)
        spec.runnerCfm = (spec.intakeCfm * 0.43).clamped(to: Limit.runnerCfm)

        // The key fix: scale the head's port flow with cylinder size.
        spec.portFlowScale = (cylVolCc / referenceCylinderVolumeCc).clamped(to: Limit.portFlowScale)

        spec.intakeRunnerVolumeCc = (60 + cylVolCc * 0.15).clamped(to: Limit.intakeRunnerVolumeCc)
        spec.intakeRunnerAreaInSq = (spec.boreMm / 40.0).clamped(to: Limit.intakeRunnerAreaInSq)
        spec.exhaustRunnerVolumeCc = (spec.intakeRunnerVolumeCc * 0.4).clamped(to: Limit.exhaustRunnerVolumeCc)
        spec.exhaustRunnerAreaInSq = (spec.intakeRunnerAreaInSq * 0.78).clamped(to: Limit.exhaustRunnerAreaInSq)

        var plenum = displacementL * 0.35 + 0.3
        if intent.has(.bigPlenum)   { plenum *= 1.5 }
        if intent.has(.smallPlenum) { plenum *= 0.6 }
        spec.intakePlenumVolumeL = plenum.clamped(to: Limit.intakePlenumVolumeL)
        spec.intakePlenumAreaCm2 = (displacementL * 4 + 4).clamped(to: Limit.intakePlenumAreaCm2)

        var runnerLen: Double
        switch intent.powerBand {
        case .lowEnd: runnerLen = 14
        case .broad:  runnerLen = 11
        case .topEnd: runnerLen = 8
        }
        if intent.has(.longRunners)  { runnerLen += 3 }
        if intent.has(.shortRunners) { runnerLen -= 3 }
        spec.intakeRunnerLengthIn = runnerLen.clamped(to: Limit.runnerLengthIn)

        spec.idleCfm = 0
        spec.idleThrottlePosition = intent.camProfile == .economy ? 0.997 : 0.996
    }

    // MARK: - Exhaust

    private static func applyExhaust(_ spec: inout EngineSpec, intent: EngineIntent) {
        var primary: Double
        var length: Double
        switch intent.powerBand {
        case .lowEnd: primary = 31; length = 115
        case .broad:  primary = 26; length = 100
        case .topEnd: primary = 20; length = 85
        }
        if intent.has(.longHeaders)  { primary += 5 }
        if intent.has(.shortHeaders) { primary -= 5 }
        spec.exhaustPrimaryLengthIn = primary.clamped(to: Limit.exhaustPrimaryLengthIn)
        spec.exhaustLengthIn = length.clamped(to: Limit.exhaustLengthIn)
        spec.exhaustCollectorBoreIn = (spec.boreMm / 40.0 + 0.2).clamped(to: Limit.exhaustCollectorBoreIn)
    }

    // MARK: - Ignition

    private static func applyIgnition(_ spec: inout EngineSpec, intent: EngineIntent, layout: EngineLayout, displacementL: Double) {
        var redline = intent.redlineRpm ?? defaultRedline(intent)
        if intent.has(.highRedline) { redline += 1500 }
        // A real engine's ceiling is set by mean PISTON SPEED, not displacement:
        // a short-stroke F1 V12 screams to ~18k while a long-stroke truck V8
        // can't. (The old `9500 - displacementL*400` cap dragged the F1 down to
        // ~7k purely because of its size.)
        redline = min(redline, pistonSpeedRedlineCap(spec: spec, intent: intent))
        redline = redline.clamped(to: Limit.redlineRpm)
        spec.redlineRpm = redline

        spec.limiterDurationSec = intent.camProfile == .race ? 0.15 : 0.18
        spec.ignitionTiming = buildTimingCurve(redline: redline, fuel: intent.fuel ?? .gasoline)
    }

    /// Max rpm allowed by a mean-piston-speed ceiling (mean speed = 2·stroke·rpm).
    /// Street builds stay near 20 m/s; a race/extreme engine runs the ~28 m/s of
    /// real motorsport, so short-stroke screamers can reach F1-class rpm.
    private static func pistonSpeedRedlineCap(spec: EngineSpec, intent: EngineIntent) -> Double {
        var limitMs: Double
        switch max(intent.performance.rank, effectiveCam(intent).rank) {
        case 0:  limitMs = 19   // weak / economy
        case 1:  limitMs = 21   // modest / stock
        case 2:  limitMs = 24   // strong / sport
        default: limitMs = 28   // extreme / race
        }
        // A deliberately high-revving engine accepts higher mean piston speed
        // (lightened internals, short stroke), so the cap rises with it.
        if intent.has(.highRedline) { limitMs += 4 }
        let strokeM = spec.strokeMm / 1000.0
        guard strokeM > 0 else { return Limit.redlineRpm.upperBound }
        return limitMs * 60.0 / (2.0 * strokeM)
    }

    private static func defaultRedline(_ intent: EngineIntent) -> Double {
        // Redline follows the intended POWER level first (a "slow worn-out"
        // engine must not rev to 9k), then a layout-based nudge. The piston-speed
        // cap above keeps these honest for the actual geometry.
        var base: Double
        switch intent.performance {
        case .weak:    base = 5500
        case .modest:  base = 6800
        case .strong:  base = 8200
        case .extreme: base = 9800
        }
        switch intent.vehicleClass {
        case .motorcycle:  base += 2500   // bikes scream
        case .truck:       base -= 800
        case .muscle:      base -= 600
        case .supercar:    base += 800
        case .raceCar:     base += 3500   // F1 / prototype territory
        default: break
        }
        return base
    }

    private static func peakAdvance(_ fuel: FuelPreset) -> Double {
        // This sim spark-ignites every fuel, so even "diesel" needs real spark
        // advance — 22° crippled the engine and forced the user to hand-add it.
        switch fuel {
        case .gasoline: return 38
        case .e85, .methanol: return 40
        case .diesel: return 32
        }
    }

    private static func buildTimingCurve(redline: Double, fuel: FuelPreset) -> [TimingPoint] {
        let peak = peakAdvance(fuel)
        let step = 1000.0
        let topRpm = (redline / step).rounded(.up) * step
        let peakRpm = max(step, redline * 0.6)
        let idleAdvance = 12.0

        var points: [TimingPoint] = []
        var rpm = 0.0
        while rpm <= topRpm + 0.5 {
            let advance: Double
            if rpm <= step {
                advance = idleAdvance
            } else if rpm >= peakRpm {
                advance = peak
            } else {
                let t = (rpm - step) / (peakRpm - step)
                advance = idleAdvance + t * (peak - idleAdvance)
            }
            points.append(TimingPoint(rpm: rpm, advanceDeg: (advance * 10).rounded() / 10))
            rpm += step
        }
        return points
    }

    // MARK: - Fuel + sound

    private static func applyFuelAndSound(_ spec: inout EngineSpec, intent: EngineIntent) {
        spec.fuel = intent.fuel ?? .gasoline
        switch intent.sound {
        case .smooth:     spec.impulseResponse = .mildExhaustReverb; spec.exhaustAudioVolume = 0.18
        case .stock:      spec.impulseResponse = .mildExhaust;       spec.exhaustAudioVolume = 0.22
        case .aggressive: spec.impulseResponse = .sharp;             spec.exhaustAudioVolume = 0.30
        case .raw:        spec.impulseResponse = .defaultIR;         spec.exhaustAudioVolume = 0.36
        }
    }

    // MARK: - Drivetrain

    private static func applyDrivetrain(_ spec: inout EngineSpec, intent: EngineIntent, layout: EngineLayout, displacementL: Double) {
        spec.clutchTorqueLbFt = (displacementL * 90 + 80).clamped(to: Limit.clutchTorqueLbFt)

        let gearCount = gearCount(for: intent)

        var (first, top): (Double, Double)
        switch intent.gearing {
        case .short:    (first, top) = (4.0, 1.0)
        case .balanced: (first, top) = (3.5, 0.85)
        case .tall:     (first, top) = (3.2, 0.62)
        }
        if intent.has(.shortGears) { first += 0.4; top += 0.15 }
        if intent.has(.tallGears)  { first -= 0.3; top -= 0.1 }
        spec.gearRatios = geometricGears(count: gearCount, first: first, top: max(0.45, top))
    }

    /// Gear count follows the POWER there is to manage, then the vehicle class
    /// adjusts. A slow economy engine doesn't need a close-ratio 6-speed (the old
    /// flat default oversized every slow build's gearbox); the extra cogs of a
    /// race car / supercar are only handed out when there's real power to keep in
    /// the band.
    private static func gearCount(for intent: EngineIntent) -> Int {
        var count: Int
        switch intent.performance {
        case .weak:    count = 4
        case .modest:  count = 5
        case .strong:  count = 6
        case .extreme: count = 6
        }
        switch intent.vehicleClass {
        case .truck:
            count = min(count, 5)
        case .raceCar, .supercar:
            if intent.performance.rank >= DesignPerformance.strong.rank { count = 7 }
        case .motorcycle:
            count = min(max(count, 5), 6)
        default:
            break
        }
        return count
    }

    private static func geometricGears(count: Int, first: Double, top: Double) -> [Double] {
        guard count > 1 else { return [first] }
        let factor = pow(top / first, 1.0 / Double(count - 1))
        return (0..<count).map { i in (first * pow(factor, Double(i)) * 100).rounded() / 100 }
    }

    // MARK: - Vehicle

    private struct VehicleProfile {
        let massLb, drag, w, h, diff, tire, roll: Double
        // Brakes: rotor diameter (in), pad friction (µ), caliper clamp force (N).
        let discIn, padMu, clampN: Double
    }

    private static func applyVehicle(_ spec: inout EngineSpec, intent: EngineIntent) {
        let p = vehicleProfile(intent.vehicleClass)
        spec.vehicleMassLb = p.massLb
        spec.dragCoefficient = p.drag
        spec.frontalAreaWidthIn = p.w
        spec.frontalAreaHeightIn = p.h
        spec.diffRatio = p.diff
        spec.tireRadiusIn = p.tire
        spec.rollingResistanceN = p.roll
        spec.brakeDiscDiameterIn = p.discIn
        spec.brakePadFriction = p.padMu
        spec.brakeClampForceN = p.clampN
    }

    private static func vehicleProfile(_ c: DesignVehicleClass) -> VehicleProfile {
        switch c {
        case .lightweight: return .init(massLb: 1800, drag: 0.31, w: 60, h: 48, diff: 4.10, tire: 9,  roll: 200, discIn: 11, padMu: 0.42, clampN: 16_000)
        case .sportsCar:   return .init(massLb: 3000, drag: 0.32, w: 70, h: 48, diff: 3.70, tire: 10, roll: 250, discIn: 12.5, padMu: 0.45, clampN: 20_000)
        case .sedan:       return .init(massLb: 3400, drag: 0.30, w: 72, h: 56, diff: 3.40, tire: 11, roll: 300, discIn: 12, padMu: 0.38, clampN: 18_000)
        case .muscle:      return .init(massLb: 3800, drag: 0.38, w: 74, h: 52, diff: 3.40, tire: 12, roll: 350, discIn: 13, padMu: 0.42, clampN: 22_000)
        case .supercar:    return .init(massLb: 3200, drag: 0.33, w: 76, h: 45, diff: 3.90, tire: 11, roll: 220, discIn: 14.5, padMu: 0.50, clampN: 28_000)
        case .truck:       return .init(massLb: 5000, drag: 0.45, w: 80, h: 75, diff: 4.10, tire: 14, roll: 500, discIn: 14, padMu: 0.38, clampN: 26_000)
        case .raceCar:     return .init(massLb: 2200, drag: 0.30, w: 72, h: 42, diff: 4.30, tire: 12, roll: 180, discIn: 15, padMu: 0.55, clampN: 32_000)
        case .motorcycle:  return .init(massLb: 600,  drag: 0.55, w: 28, h: 44, diff: 2.40, tire: 12, roll: 120, discIn: 12, padMu: 0.48, clampN: 12_000)
        }
    }
}

// MARK: - Clamp

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
