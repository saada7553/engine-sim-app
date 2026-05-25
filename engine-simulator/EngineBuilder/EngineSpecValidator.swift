//
//  EngineSpecValidator.swift
//  engine-simulator
//
//  Inspects a finished EngineSpec and flags choices that will keep the engine
//  from running well (or at all) before the user commits it. The whole sim is
//  spark-ignition with a gasoline baseline, so anything that fights that, or
//  that is internally inconsistent (a starter too weak to crank, gears that do
//  not step down, a stroke too long for the redline) surfaces here as plain
//  language the player can act on.
//
//  Pure Foundation so it is unit testable without a model or the UI. The
//  thresholds are deliberately loose: the default builder spec and any sane
//  build must produce zero warnings, so a warning always means something.
//

import Foundation

struct BuildWarning: Identifiable, Equatable {
    enum Severity {
        case critical   // likely will not start, will not run, or shifts wrong
        case caution    // runs, but idles rough, leaves power on the table, or risks float
    }

    let id = UUID()
    let severity: Severity
    let title: String
    let detail: String

    static func == (lhs: BuildWarning, rhs: BuildWarning) -> Bool { lhs.id == rhs.id }
}

enum EngineSpecValidator {

    // MARK: - Thresholds (named so there are no bare numbers in the checks)

    private enum T {
        // Mean piston speed, metres per second.
        static let pistonSpeedCaution = 25.0
        static let pistonSpeedCritical = 30.0

        // Rod length to stroke ratio.
        static let rodRatioLow = 1.40
        static let rodRatioHigh = 2.30

        // Approximate geometric compression ratio (gasoline window).
        static let compressionLow = 8.5
        static let compressionHigh = 13.5
        // Compression a forgiving fuel (E85 / methanol) starts to actually use.
        static let altFuelCompressionFloor = 11.0
        // Compression real diesels rely on to ignite without spark.
        static let dieselCompressionTarget = 16.0

        // Starter: fraction of the size matched recommendation.
        static let starterTorqueCaution = 0.75
        static let starterTorqueCritical = 0.55
        static let starterSpeedCaution = 0.70
        // Extra cranking effort per point of compression above the gasoline norm.
        static let crankEffortPerCompressionPoint = 0.04
        static let compressionNorm = 11.0

        // Flywheel mass, kilograms.
        static let flywheelLight = 4.0
        static let flywheelLightFewCylinders = 5.0
        static let flywheelHeavy = 20.0
        static let fewCylinders = 4

        // Reciprocating mass at high rpm.
        static let heavyPistonG = 380.0
        static let highRedlineRpm = 8000.0

        // Internal drag, lb-ft.
        static let crankFrictionHigh = 18.0

        // Cam.
        static let camDurationBig = 270.0
        static let lobeSeparationTight = 106.0

        // Breathing: intake flow versus the airflow the engine wants at redline.
        static let intakeUndersizedFraction = 0.50
        static let intakeOversizedFraction = 2.60
        static let volumetricEfficiency = 0.90
        static let cidPerLitre = 61.024
        static let cfmAirflowConstant = 3456.0

        // Total spark advance, degrees.
        static let advanceHigh = 42.0
        static let advanceLow = 8.0

        // Ring seal.
        static let blowbyWorn = 1.0

        // Clutch holding torque, lb-ft.
        static let clutchWeak = 150.0
    }

    // MARK: - Derived metrics

    private struct Metrics {
        let cylinders: Int
        let displacementL: Double
        let approxCompression: Double
        let meanPistonSpeed: Double
        let rodRatio: Double
        let requiredIntakeCfm: Double
        let peakAdvance: Double

        init(_ spec: EngineSpec) {
            cylinders = spec.layout.cylinderCount
            displacementL = spec.displacementLitres

            // Geometric compression: swept volume per cylinder over the chamber
            // it is squeezed into. An approximation (it ignores deck and piston
            // dome) but close enough to flag a build that is way off.
            let sweptPerCyl = spec.displacementCc / Double(max(1, cylinders))
            let chamber = max(1.0, spec.chamberVolumeCc)
            approxCompression = (sweptPerCyl + chamber) / chamber

            meanPistonSpeed = 2.0 * (spec.strokeMm / 1000.0) * (spec.redlineRpm / 60.0)
            rodRatio = spec.rodLengthMm / max(1.0, spec.strokeMm)

            let cid = displacementL * T.cidPerLitre
            requiredIntakeCfm = cid * spec.redlineRpm * T.volumetricEfficiency / T.cfmAirflowConstant

            peakAdvance = spec.ignitionTiming.map(\.advanceDeg).max() ?? 0
        }
    }

    // MARK: - Entry point

    /// All warnings for a spec, critical first. Empty means the build is sound.
    static func warnings(for spec: EngineSpec) -> [BuildWarning] {
        let m = Metrics(spec)
        var out: [BuildWarning] = []

        appendGeometry(spec, m, into: &out)
        appendCompressionAndFuel(spec, m, into: &out)
        appendStarter(spec, m, into: &out)
        appendRotating(spec, m, into: &out)
        appendCam(spec, into: &out)
        appendBreathing(spec, m, into: &out)
        appendIgnition(spec, m, into: &out)
        appendDrivetrain(spec, into: &out)

        return out.sorted { $0.severity == .critical && $1.severity == .caution }
    }

    // MARK: - Geometry

    private static func appendGeometry(_ spec: EngineSpec, _ m: Metrics, into out: inout [BuildWarning]) {
        if m.meanPistonSpeed >= T.pistonSpeedCritical {
            out.append(BuildWarning(
                severity: .critical,
                title: "Stroke is too long for this redline",
                detail: "Mean piston speed is about \(speed(m.meanPistonSpeed)), well past what valvetrains survive. Expect valve float and a wild, unstable top end. Shorten the stroke or drop the redline."))
        } else if m.meanPistonSpeed >= T.pistonSpeedCaution {
            out.append(BuildWarning(
                severity: .caution,
                title: "High piston speed",
                detail: "Mean piston speed is about \(speed(m.meanPistonSpeed)), which is race only territory. It will rev there, but a shorter stroke or a lower redline runs happier."))
        }

        if m.rodRatio < T.rodRatioLow {
            out.append(BuildWarning(
                severity: .caution,
                title: "Short rods for this stroke",
                detail: "The rod to stroke ratio is \(ratio(m.rodRatio)). Short rods load the cylinder walls hard and make the engine rougher. A longer rod or a shorter stroke smooths it out."))
        } else if m.rodRatio > T.rodRatioHigh {
            out.append(BuildWarning(
                severity: .caution,
                title: "Unusually long rods",
                detail: "The rod to stroke ratio is \(ratio(m.rodRatio)), longer than almost any real engine. It will run, but the proportions are odd for the bottom end."))
        }
    }

    // MARK: - Compression and fuel

    private static func appendCompressionAndFuel(_ spec: EngineSpec, _ m: Metrics, into out: inout [BuildWarning]) {
        let cr = m.approxCompression

        switch spec.fuel {
        case .gasoline:
            if cr < T.compressionLow {
                out.append(lowCompression(cr))
            } else if cr > T.compressionHigh {
                out.append(BuildWarning(
                    severity: .caution,
                    title: "High compression on pump gas",
                    detail: "Compression is roughly \(comp(cr)) to one. On gasoline that invites knock and a rough, unstable burn. Open the chamber up or expect it to run on the edge."))
            }

        case .diesel:
            out.append(BuildWarning(
                severity: .caution,
                title: "Diesel runs on spark here",
                detail: "This simulator spark ignites every fuel, while real diesels need very high compression, around \(Int(T.dieselCompressionTarget)) to one and up, to light off. This build is near \(comp(cr)) to one, so it behaves like a soft, low compression gas engine. Raise compression with a smaller chamber and keep the rev range low for the best result."))

        case .e85, .methanol:
            if cr < T.altFuelCompressionFloor {
                out.append(BuildWarning(
                    severity: .caution,
                    title: "\(spec.fuel.displayName) wants more compression",
                    detail: "\(spec.fuel.displayName) resists knock and likes high compression, but this build is only about \(comp(cr)) to one. It will feel flat and leave power unused. Shrink the chamber to raise compression and put the fuel to work."))
            } else if cr < T.compressionLow {
                out.append(lowCompression(cr))
            }
        }
    }

    private static func lowCompression(_ cr: Double) -> BuildWarning {
        BuildWarning(
            severity: .caution,
            title: "Low compression",
            detail: "Compression is only about \(comp(cr)) to one, so the engine will feel soft and may idle poorly. Use a smaller chamber volume to bring it up.")
    }

    // MARK: - Starter

    private static func appendStarter(_ spec: EngineSpec, _ m: Metrics, into out: inout [BuildWarning]) {
        // Cranking gets harder as compression climbs, so scale the size matched
        // recommendation up for a high compression build.
        let compressionPenalty = 1.0 + max(0, m.approxCompression - T.compressionNorm) * T.crankEffortPerCompressionPoint
        let needTorque = spec.recommendedStarterTorqueLbFt * compressionPenalty

        if spec.starterTorqueLbFt < needTorque * T.starterTorqueCritical {
            out.append(BuildWarning(
                severity: .critical,
                title: "Starter too weak to crank this engine",
                detail: "A \(spec.layout.displayName) of this size and compression wants around \(torque(needTorque)) of starter torque, but this one makes \(torque(spec.starterTorqueLbFt)). It may never spin over fast enough to fire. Raise starter torque."))
        } else if spec.starterTorqueLbFt < needTorque * T.starterTorqueCaution {
            out.append(BuildWarning(
                severity: .caution,
                title: "Starter is on the weak side",
                detail: "Starter torque is \(torque(spec.starterTorqueLbFt)) against a recommended \(torque(needTorque)) for this build. It should still crank, but starting may be slow or stubborn."))
        }

        if spec.starterSpeedRpm < spec.recommendedStarterSpeedRpm * T.starterSpeedCaution {
            out.append(BuildWarning(
                severity: .caution,
                title: "Starter spins too slowly",
                detail: "Cranking speed is \(rpm(spec.starterSpeedRpm)), below the \(rpm(spec.recommendedStarterSpeedRpm)) this engine likes. A slow crank can struggle to build enough airflow to catch."))
        }
    }

    // MARK: - Rotating mass and friction

    private static func appendRotating(_ spec: EngineSpec, _ m: Metrics, into out: inout [BuildWarning]) {
        let few = m.cylinders <= T.fewCylinders

        if spec.flywheelMassKg < T.flywheelLight || (few && spec.flywheelMassKg < T.flywheelLightFewCylinders) {
            out.append(BuildWarning(
                severity: .caution,
                title: "Light flywheel may not hold idle",
                detail: "At \(mass(spec.flywheelMassKg)) the flywheel stores little energy between firing strokes\(few ? ", and with only \(m.cylinders) cylinders the gaps are large" : ""). Idle can hunt or stall. Add flywheel mass for a steadier idle."))
        } else if spec.flywheelMassKg > T.flywheelHeavy {
            out.append(BuildWarning(
                severity: .caution,
                title: "Heavy flywheel blunts response",
                detail: "A \(mass(spec.flywheelMassKg)) flywheel makes the engine slow to rev and slow to return to idle. Lighten it if you want a sharper throttle."))
        }

        if spec.pistonMassG > T.heavyPistonG && spec.redlineRpm > T.highRedlineRpm {
            out.append(BuildWarning(
                severity: .caution,
                title: "Heavy pistons at high rpm",
                detail: "\(Int(spec.pistonMassG)) g pistons swinging to \(rpm(spec.redlineRpm)) put big loads on the rotating assembly and risk float. Lighter pistons suit this redline better."))
        }

        if spec.crankFrictionLbFt > T.crankFrictionHigh {
            out.append(BuildWarning(
                severity: .caution,
                title: "High internal friction",
                detail: "Crank friction is \(torque(spec.crankFrictionLbFt)), enough to eat a real chunk of output and make the idle laboured. Lower it unless you are modelling a very tired engine."))
        }
    }

    // MARK: - Cam and VTEC

    private static func appendCam(_ spec: EngineSpec, into out: inout [BuildWarning]) {
        if spec.camDurationDeg > T.camDurationBig {
            out.append(BuildWarning(
                severity: .caution,
                title: "Very big cam",
                detail: "\(Int(spec.camDurationDeg))° of duration is a wild, race style cam. Expect a lumpy, low vacuum idle that may be hard to hold. Pair it with a higher idle and lighter expectations down low."))
        }

        if spec.camLobeSeparationDeg < T.lobeSeparationTight {
            out.append(BuildWarning(
                severity: .caution,
                title: "Tight lobe separation",
                detail: "A \(Int(spec.camLobeSeparationDeg))° lobe separation gives heavy overlap and a choppy idle. Widen it for a calmer engine, or keep it for the lope."))
        }

        guard spec.vtecEnabled else { return }

        if spec.vtecCrossoverRpm >= spec.redlineRpm {
            out.append(BuildWarning(
                severity: .critical,
                title: "VTEC crossover is above the redline",
                detail: "The second cam switches in at \(rpm(spec.vtecCrossoverRpm)) but the engine stops at \(rpm(spec.redlineRpm)), so it never engages. Drop the crossover below the redline or turn VTEC off."))
        }
        if spec.vtecCamDurationDeg <= spec.camDurationDeg {
            out.append(BuildWarning(
                severity: .caution,
                title: "VTEC cam is not wilder than the primary",
                detail: "The high rpm cam (\(Int(spec.vtecCamDurationDeg))°) is no bigger than the primary (\(Int(spec.camDurationDeg))°), so switching to it does nothing useful. Give it more duration or turn VTEC off."))
        }
    }

    // MARK: - Breathing

    private static func appendBreathing(_ spec: EngineSpec, _ m: Metrics, into out: inout [BuildWarning]) {
        guard m.requiredIntakeCfm > 0 else { return }
        let ratio = spec.intakeCfm / m.requiredIntakeCfm

        if ratio < T.intakeUndersizedFraction {
            out.append(BuildWarning(
                severity: .caution,
                title: "Intake too small to feed this engine",
                detail: "At \(cfm(spec.intakeCfm)) the intake cannot flow what \(litres(m.displacementL)) wants by \(rpm(spec.redlineRpm)). Power will sign off early and the top end will feel strangled. Open up the intake or lower the redline."))
        } else if ratio > T.intakeOversizedFraction {
            out.append(BuildWarning(
                severity: .caution,
                title: "Intake far larger than needed",
                detail: "\(cfm(spec.intakeCfm)) is much more than this engine can use. Low speed response and idle quality suffer with an oversized intake. A smaller one sharpens the bottom end."))
        }
    }

    // MARK: - Ignition

    private static func appendIgnition(_ spec: EngineSpec, _ m: Metrics, into out: inout [BuildWarning]) {
        if m.peakAdvance > T.advanceHigh {
            out.append(BuildWarning(
                severity: .caution,
                title: "Lots of ignition advance",
                detail: "Peak advance reaches \(Int(m.peakAdvance))°, far enough to knock and run unstable. Pull the top of the timing curve back if it misbehaves."))
        } else if m.peakAdvance < T.advanceLow {
            out.append(BuildWarning(
                severity: .caution,
                title: "Very little ignition advance",
                detail: "The timing curve never gets past \(Int(m.peakAdvance))°. The burn finishes too late and the engine will feel soft. Add advance through the mid and upper rpm."))
        }

        if spec.blowby > T.blowbyWorn {
            out.append(BuildWarning(
                severity: .caution,
                title: "High blowby",
                detail: "Blowby is set to \(String(format: "%.2f", spec.blowby)), modelling worn rings. The engine will be down on compression and power and may run rough. Lower it for a fresh build."))
        }
    }

    // MARK: - Drivetrain

    private static func appendDrivetrain(_ spec: EngineSpec, into out: inout [BuildWarning]) {
        let gears = spec.gearRatios
        let stepsDown = zip(gears, gears.dropFirst()).allSatisfy { $0 > $1 }
        if gears.count < 2 || !stepsDown {
            out.append(BuildWarning(
                severity: .critical,
                title: "Gear ratios do not step down",
                detail: "Each gear should be numerically lower than the one before it, from first to top. As set, shifting will behave strangely. Order the ratios from tallest first gear to shortest top gear."))
        }

        if spec.clutchTorqueLbFt < T.clutchWeak {
            out.append(BuildWarning(
                severity: .caution,
                title: "Clutch may slip",
                detail: "Clutch holding torque is only \(torque(spec.clutchTorqueLbFt)). Under load it can slip instead of driving the wheels. Raise it if the car bogs or the revs flare on a shift."))
        }
    }

    // MARK: - Formatting helpers

    private static func speed(_ v: Double) -> String { String(format: "%.0f m/s", v) }
    private static func ratio(_ v: Double) -> String { String(format: "%.2f to 1", v) }
    private static func comp(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func torque(_ v: Double) -> String { String(format: "%.0f lb-ft", v) }
    private static func rpm(_ v: Double) -> String { String(format: "%.0f rpm", v) }
    private static func mass(_ v: Double) -> String { String(format: "%.1f kg", v) }
    private static func cfm(_ v: Double) -> String { String(format: "%.0f CFM", v) }
    private static func litres(_ v: Double) -> String { String(format: "%.1f L", v) }
}
