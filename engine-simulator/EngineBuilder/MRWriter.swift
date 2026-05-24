//
//  MRWriter.swift
//  engine-simulator
//
//  Emits a valid .mr script from an EngineSpec for the C++ Piranha compiler.
//

import Foundation

private let mrIndent = "    "
private let twoStrokeCycleDeg = 720.0
private let fallbackGearRatios: [Double] = [3.0, 2.0, 1.4, 1.0]

// Flat (boxer) crank: the crank TDC reference sits at 180° (vs the inline/V
// `pi/2 - halfV`). Journal angles are derived per-cylinder in crankAndJournals.
private let boxerCrankTdcDeg = 180.0

enum MRWriter {

    /// Returns the .mr file body for the given spec.
    static func script(for spec:    EngineSpec) -> String {
        let nodeName = spec.nodeName
        let firingOrder = effectiveFiringOrder(for: spec)

        var out = ""
        out += header()
        out += "\n"
        out += wiresNode(cylinderCount: spec.layout.cylinderCount)
        out += "\n"
        out += ignitionNode(nodeName: nodeName,
                            firingOrder: firingOrder,
                            cylinderCount: spec.layout.cylinderCount)
        out += "\n"
        out += camshaftBuilderNode(nodeName: nodeName, spec: spec, firingOrder: firingOrder)
        out += "\n"
        out += headNode(nodeName: nodeName, spec: spec)
        out += "\n"
        out += engineNode(nodeName: nodeName, spec: spec, firingOrder: firingOrder)
        out += "\n"
        out += vehicleNode(nodeName: nodeName, spec: spec)
        out += "\n"
        out += transmissionNode(nodeName: nodeName, spec: spec)
        out += "\n"
        out += mainNode(nodeName: nodeName)
        return out
    }

    // MARK: - Header

    private static func header() -> String {
        """
        import "engine_sim.mr"

        units units()
        constants constants()
        impulse_response_library ir_lib()

        // The engine_sim default flame-speed curve tops out at 1.5x turbulence,
        // so generated engines burn slowly, make less power and need heavy
        // ignition advance to run well (they feel sluggish on the stock tune).
        // Every strong shipped engine uses ~2.0x — match it here.
        private node es_flame_speed {
        \(mrIndent)alias output __out:
        \(mrIndent)\(mrIndent)function(5.0)
        \(mrIndent)\(mrIndent)\(mrIndent).add_sample(0.0, 3.0)
        \(mrIndent)\(mrIndent)\(mrIndent).add_sample(5.0, 1.5 * 5.0)
        \(mrIndent)\(mrIndent)\(mrIndent).add_sample(10.0, 1.9 * 10.0)
        \(mrIndent)\(mrIndent)\(mrIndent).add_sample(15.0, 2.0 * 15.0)
        \(mrIndent)\(mrIndent)\(mrIndent).add_sample(20.0, 2.0 * 20.0)
        \(mrIndent)\(mrIndent)\(mrIndent).add_sample(25.0, 2.0 * 25.0)
        \(mrIndent)\(mrIndent)\(mrIndent).add_sample(30.0, 2.0 * 30.0)
        \(mrIndent)\(mrIndent)\(mrIndent).add_sample(35.0, 2.0 * 35.0)
        \(mrIndent)\(mrIndent)\(mrIndent).add_sample(40.0, 2.0 * 40.0)
        \(mrIndent)\(mrIndent)\(mrIndent).add_sample(45.0, 2.0 * 45.0);
        }

        """
    }

    // MARK: - Ignition wires

    private static func wiresNode(cylinderCount n: Int) -> String {
        var s = "private node wires {\n"
        for i in 1...n {
            s += "\(mrIndent)output wire\(i): ignition_wire();\n"
        }
        s += "}\n"
        return s
    }

    private static func ignitionNode(nodeName: String,
                                     firingOrder: [Int],
                                     cylinderCount n: Int) -> String {
        var s = """
        label cycle(2 * 360 * units.deg)
        public node \(nodeName)_ignition {
        \(mrIndent)input wires;
        \(mrIndent)input timing_curve;
        \(mrIndent)input rev_limit: 7000 * units.rpm;
        \(mrIndent)input limiter_duration: 0.1;
        \(mrIndent)alias output __out:
        \(mrIndent)\(mrIndent)ignition_module(
        \(mrIndent)\(mrIndent)\(mrIndent)timing_curve: timing_curve,
        \(mrIndent)\(mrIndent)\(mrIndent)rev_limit: rev_limit,
        \(mrIndent)\(mrIndent)\(mrIndent)limiter_duration: limiter_duration
        \(mrIndent)\(mrIndent))

        """
        for (firingPos, cyl) in firingOrder.enumerated() {
            let frac = "(\(firingPos).0 / \(n).0)"
            let terminator = firingPos == firingOrder.count - 1 ? ";" : ""
            s += "\(mrIndent)\(mrIndent)\(mrIndent).connect_wire(wires.wire\(cyl), \(frac) * cycle)\(terminator)\n"
        }
        s += "}\n"
        return s
    }

    // MARK: - Camshaft builder

    /// Emits a node that builds intake/exhaust cams for bank 0 (and bank 1 if a V engine).
    private static func camshaftBuilderNode(nodeName: String,
                                            spec: EngineSpec,
                                            firingOrder: [Int]) -> String {
        let layout = spec.layout
        let n = layout.cylinderCount
        let rotPerFiring = twoStrokeCycleDeg / Double(n)   // degrees between consecutive firings

        let bank0Cyls = bank0Cylinders(layout: layout)
        let bank1Cyls = bank1Cylinders(layout: layout)

        let vtec = spec.vtecEnabled

        var s = "public node \(nodeName)_camshaft_builder {\n"
        s += "\(mrIndent)input intake_lobe_profile;\n"
        s += "\(mrIndent)input exhaust_lobe_profile;\n"
        s += "\(mrIndent)input lobe_separation: \(spec.camLobeSeparationDeg) * units.deg;\n"
        s += "\(mrIndent)input intake_lobe_center: lobe_separation;\n"
        s += "\(mrIndent)input exhaust_lobe_center: lobe_separation;\n"
        s += "\(mrIndent)input advance: \(spec.camAdvanceDeg) * units.deg;\n"
        s += "\(mrIndent)input base_radius: \(spec.camBaseRadiusIn) * units.inch;\n"
        if vtec {
            s += "\(mrIndent)input vtec_intake_lobe_profile;\n"
            s += "\(mrIndent)input vtec_exhaust_lobe_profile;\n"
            s += "\(mrIndent)input vtec_lobe_separation: \(spec.vtecCamLobeSeparationDeg) * units.deg;\n"
            s += "\(mrIndent)input vtec_intake_lobe_center: vtec_lobe_separation;\n"
            s += "\(mrIndent)input vtec_exhaust_lobe_center: vtec_lobe_separation;\n"
        }
        s += "\n"

        s += camOutputs(bankCount: layout.bankCount, vtec: vtec)

        s += "\n"
        s += "\(mrIndent)camshaft_parameters params(advance: advance, base_radius: base_radius)\n\n"
        s += camDeclarations(bankCount: layout.bankCount, vtec: vtec)
        s += "\n"
        s += "\(mrIndent)label rot(\(rotPerFiring) * units.deg)\n"
        s += "\(mrIndent)label rot360(360 * units.deg)\n\n"

        // Standard (low-lift) lobes, placed by firing order.
        s += lobesBlock(camName: "_intake_cam_0", center: "intake_lobe_center", intake: true,
                         cylinders: bank0Cyls, firingOrder: firingOrder)
        s += lobesBlock(camName: "_exhaust_cam_0", center: "exhaust_lobe_center", intake: false,
                         cylinders: bank0Cyls, firingOrder: firingOrder)
        if layout.bankCount == 2 {
            s += lobesBlock(camName: "_intake_cam_1", center: "intake_lobe_center", intake: true,
                             cylinders: bank1Cyls, firingOrder: firingOrder)
            s += lobesBlock(camName: "_exhaust_cam_1", center: "exhaust_lobe_center", intake: false,
                             cylinders: bank1Cyls, firingOrder: firingOrder)
        }
        // VTEC (high-lift) lobes, same firing order with the tighter vtec centers.
        if vtec {
            s += lobesBlock(camName: "_vtec_intake_cam_0", center: "vtec_intake_lobe_center", intake: true,
                             cylinders: bank0Cyls, firingOrder: firingOrder)
            s += lobesBlock(camName: "_vtec_exhaust_cam_0", center: "vtec_exhaust_lobe_center", intake: false,
                             cylinders: bank0Cyls, firingOrder: firingOrder)
            if layout.bankCount == 2 {
                s += lobesBlock(camName: "_vtec_intake_cam_1", center: "vtec_intake_lobe_center", intake: true,
                                 cylinders: bank1Cyls, firingOrder: firingOrder)
                s += lobesBlock(camName: "_vtec_exhaust_cam_1", center: "vtec_exhaust_lobe_center", intake: false,
                                 cylinders: bank1Cyls, firingOrder: firingOrder)
            }
        }

        s += "}\n"
        return s
    }

    /// Output declarations for the cam builder (low-lift cams always, vtec cams when enabled).
    private static func camOutputs(bankCount: Int, vtec: Bool) -> String {
        var s = ""
        for bank in 0..<bankCount {
            s += "\(mrIndent)output intake_cam_\(bank): _intake_cam_\(bank);\n"
            s += "\(mrIndent)output exhaust_cam_\(bank): _exhaust_cam_\(bank);\n"
            if vtec {
                s += "\(mrIndent)output vtec_intake_cam_\(bank): _vtec_intake_cam_\(bank);\n"
                s += "\(mrIndent)output vtec_exhaust_cam_\(bank): _vtec_exhaust_cam_\(bank);\n"
            }
        }
        return s
    }

    private static func camDeclarations(bankCount: Int, vtec: Bool) -> String {
        var s = ""
        for bank in 0..<bankCount {
            s += "\(mrIndent)camshaft _intake_cam_\(bank)(params, lobe_profile: intake_lobe_profile)\n"
            s += "\(mrIndent)camshaft _exhaust_cam_\(bank)(params, lobe_profile: exhaust_lobe_profile)\n"
            if vtec {
                s += "\(mrIndent)camshaft _vtec_intake_cam_\(bank)(params, lobe_profile: vtec_intake_lobe_profile)\n"
                s += "\(mrIndent)camshaft _vtec_exhaust_cam_\(bank)(params, lobe_profile: vtec_exhaust_lobe_profile)\n"
            }
        }
        return s
    }

    private static func lobesBlock(camName: String, center: String, intake: Bool,
                                    cylinders: [Int], firingOrder: [Int]) -> String {
        let sign = intake ? "+" : "-"
        var s = "\(mrIndent)\(camName)\n"
        for cyl in cylinders {
            guard let pos = firingOrder.firstIndex(of: cyl) else { continue }
            s += "\(mrIndent)\(mrIndent).add_lobe(rot360 \(sign) \(center) + \(pos) * rot) // cyl \(cyl)\n"
        }
        return s
    }

    // MARK: - Head

    private static func headNode(nodeName: String, spec: EngineSpec) -> String {
        // Default port flow samples are scaled by portFlowScale (typical pattern in reference engines).
        let intakeSamples: [(Double, Double)] = [
            (0, 0), (50, 58), (100, 103), (150, 156), (200, 214),
            (250, 249), (300, 268), (350, 280), (400, 280), (450, 281)
        ]
        let exhaustSamples: [(Double, Double)] = [
            (0, 0), (50, 37), (100, 72), (150, 113), (200, 160),
            (250, 196), (300, 222), (350, 235), (400, 245), (450, 246)
        ]
        let scale = spec.portFlowScale

        let vtec = spec.vtecEnabled
        let vtecInputs = vtec
            ? "\(mrIndent)input vtec_intake_camshaft;\n\(mrIndent)input vtec_exhaust_camshaft;\n"
            : ""

        var s = """
        private node \(nodeName)_head {
        \(mrIndent)input intake_camshaft;
        \(mrIndent)input exhaust_camshaft;
        \(vtecInputs)\(mrIndent)input flip_display: false;
        \(mrIndent)alias output __out: head;

        \(mrIndent)function intake_flow(50 * units.thou)
        \(mrIndent)intake_flow

        """
        for (lift, flow) in intakeSamples {
            s += "\(mrIndent)\(mrIndent).add_flow_sample(\(lift), \(flow * scale))\n"
        }
        s += "\n\(mrIndent)function exhaust_flow(50 * units.thou)\n"
        s += "\(mrIndent)exhaust_flow\n"
        for (lift, flow) in exhaustSamples {
            s += "\(mrIndent)\(mrIndent).add_flow_sample(\(lift), \(flow * scale))\n"
        }
        s += """

        \(mrIndent)generic_cylinder_head head(
        \(mrIndent)\(mrIndent)chamber_volume: \(spec.chamberVolumeCc) * units.cc,
        \(mrIndent)\(mrIndent)intake_runner_volume: \(spec.intakeRunnerVolumeCc) * units.cc,
        \(mrIndent)\(mrIndent)intake_runner_cross_section_area: \(spec.intakeRunnerAreaInSq) * units.inch * units.inch,
        \(mrIndent)\(mrIndent)exhaust_runner_volume: \(spec.exhaustRunnerVolumeCc) * units.cc,
        \(mrIndent)\(mrIndent)exhaust_runner_cross_section_area: \(spec.exhaustRunnerAreaInSq) * units.inch * units.inch,

        \(mrIndent)\(mrIndent)intake_port_flow: intake_flow,
        \(mrIndent)\(mrIndent)exhaust_port_flow: exhaust_flow,
        \(mrIndent)\(mrIndent)valvetrain: \(valvetrainBlock(spec: spec)),
        \(mrIndent)\(mrIndent)flip_display: flip_display
        \(mrIndent))
        }

        """
        return s
    }

    /// The valvetrain expression for the head — a vtec_valvetrain (low + high
    /// cam, engaging at the crossover RPM) when VTEC is on, else standard.
    private static func valvetrainBlock(spec: EngineSpec) -> String {
        if spec.vtecEnabled {
            return """
            vtec_valvetrain(
            \(mrIndent)\(mrIndent)\(mrIndent)min_rpm: \(spec.vtecCrossoverRpm) * units.rpm,
            \(mrIndent)\(mrIndent)\(mrIndent)intake_camshaft: intake_camshaft,
            \(mrIndent)\(mrIndent)\(mrIndent)exhaust_camshaft: exhaust_camshaft,
            \(mrIndent)\(mrIndent)\(mrIndent)vtec_intake_camshaft: vtec_intake_camshaft,
            \(mrIndent)\(mrIndent)\(mrIndent)vtec_exhaust_camshaft: vtec_exhaust_camshaft
            \(mrIndent)\(mrIndent))
            """
        }
        return """
        standard_valvetrain(
        \(mrIndent)\(mrIndent)\(mrIndent)intake_camshaft: intake_camshaft,
        \(mrIndent)\(mrIndent)\(mrIndent)exhaust_camshaft: exhaust_camshaft
        \(mrIndent)\(mrIndent))
        """
    }

    /// `set_cylinder_head` calls for each bank, passing the vtec cams too when enabled.
    private static func headInstall(nodeName: String, spec: EngineSpec) -> String {
        func headCall(bank: Int, flip: Bool) -> String {
            var args = "intake_camshaft: camshaft.intake_cam_\(bank), exhaust_camshaft: camshaft.exhaust_cam_\(bank)"
            if spec.vtecEnabled {
                args += ", vtec_intake_camshaft: camshaft.vtec_intake_cam_\(bank), vtec_exhaust_camshaft: camshaft.vtec_exhaust_cam_\(bank)"
            }
            if flip { args += ", flip_display: true" }
            return "\(mrIndent)b\(bank).set_cylinder_head(\(nodeName)_head(\(args)))\n"
        }
        var s = headCall(bank: 0, flip: false)
        if spec.layout.bankCount == 2 { s += headCall(bank: 1, flip: true) }
        return s
    }

    // MARK: - Engine main node

    private static func engineNode(nodeName: String,
                                   spec: EngineSpec,
                                   firingOrder: [Int]) -> String {
        let layout = spec.layout
        let n = layout.cylinderCount
        let rotPerFiring = twoStrokeCycleDeg / Double(n)
        let halfV = layout.bankHalfAngleDeg

        let bank0Cyls = bank0Cylinders(layout: layout)
        let bank1Cyls = bank1Cylinders(layout: layout)

        var s = "public node \(nodeName) {\n"
        s += "\(mrIndent)alias output __out: engine;\n\n"
        s += "\(mrIndent)wires wires()\n\n"

        s += engineDeclaration(nodeName: nodeName, spec: spec)
        s += labels(spec: spec)
        s += crankAndJournals(spec: spec, firingOrder: firingOrder, n: n,
                               rotPerFiring: rotPerFiring, halfV: halfV)
        s += pistonAndRodParams(spec: spec)
        s += bankAndIntakeExhaust(spec: spec, halfV: halfV)
        s += bankCylinders(spec: spec,
                            bankIndex: 0,
                            bankCyls: bank0Cyls,
                            exhaustName: "exhaust0",
                            wirePrefix: "wires.wire")
        if layout.bankCount == 2 {
            s += bankCylinders(spec: spec,
                                bankIndex: 1,
                                bankCyls: bank1Cyls,
                                exhaustName: "exhaust1",
                                wirePrefix: "wires.wire")
        }

        s += "\n\(mrIndent)engine\n"
        s += "\(mrIndent)\(mrIndent).add_cylinder_bank(b0)"
        if layout.bankCount == 2 {
            s += "\n\(mrIndent)\(mrIndent).add_cylinder_bank(b1)"
        }
        s += "\n\n\(mrIndent)engine.add_crankshaft(c0)\n\n"

        s += camAndIgnitionInstall(spec: spec, nodeName: nodeName)
        s += "}\n"
        return s
    }

    private static func engineDeclaration(nodeName: String, spec: EngineSpec) -> String {
        let fuelStr = fuelBlock(spec.fuel)
        return """
        \(mrIndent)engine engine(
        \(mrIndent)\(mrIndent)name: "\(spec.name)",
        \(mrIndent)\(mrIndent)starter_torque: \(spec.starterTorqueLbFt) * units.lb_ft,
        \(mrIndent)\(mrIndent)starter_speed: \(spec.starterSpeedRpm) * units.rpm,
        \(mrIndent)\(mrIndent)redline: \(spec.redlineRpm) * units.rpm,
        \(mrIndent)\(mrIndent)fuel: \(fuelStr),
        \(mrIndent)\(mrIndent)hf_gain: 0.01,
        \(mrIndent)\(mrIndent)noise: 1.0,
        \(mrIndent)\(mrIndent)jitter: 0.4,
        \(mrIndent)\(mrIndent)simulation_frequency: 7000
        \(mrIndent))


        """
    }

    private static func fuelBlock(_ fuel: FuelPreset) -> String {
        // Shared across fuels: the faster flame curve + a calmer combustion
        // randomness than the 0.5 default so the idle settles instead of hunting.
        let common = "burning_efficiency_randomness: 0.3, turbulence_to_flame_speed_ratio: es_flame_speed()"
        switch fuel {
        case .gasoline:
            return "fuel(max_burning_efficiency: 1.0, \(common))"
        case .e85:
            return "fuel(max_burning_efficiency: 0.95, molecular_afr: 9.7, energy_density: 33.1 * units.kJ / units.g, \(common))"
        case .methanol:
            return "fuel(max_burning_efficiency: 0.9, molecular_afr: 6.5, energy_density: 19.7 * units.kJ / units.g, \(common))"
        case .diesel:
            return "fuel(max_burning_efficiency: 0.85, molecular_afr: 14.5, energy_density: 45.5 * units.kJ / units.g, \(common))"
        }
    }

    private static func labels(spec: EngineSpec) -> String {
        """
        \(mrIndent)label stroke(\(spec.strokeMm) * units.mm)
        \(mrIndent)label bore(\(spec.boreMm) * units.mm)
        \(mrIndent)label rod_length(\(spec.rodLengthMm) * units.mm)
        \(mrIndent)label rod_mass(\(spec.rodMassG) * units.g)
        \(mrIndent)label compression_height(\(spec.compressionHeightMm) * units.mm)
        \(mrIndent)label crank_mass(\(spec.crankMassKg) * units.kg)
        \(mrIndent)label flywheel_mass(\(spec.flywheelMassKg) * units.kg)
        \(mrIndent)label flywheel_radius(\(spec.flywheelRadiusIn) * units.inch)


        """
    }

    private static func crankAndJournals(spec: EngineSpec,
                                          firingOrder: [Int],
                                          n: Int,
                                          rotPerFiring: Double,
                                          halfV: Double) -> String {
        let isFlat = spec.layout.isFlat
        let tdcExpr = isFlat
            ? "\(boxerCrankTdcDeg) * units.deg"
            : "(constants.pi / 2) - (\(halfV) * units.deg)"

        var s = """
        \(mrIndent)label crank_moment(disk_moment_of_inertia(mass: crank_mass, radius: stroke / 2))
        \(mrIndent)label flywheel_moment(disk_moment_of_inertia(mass: flywheel_mass, radius: flywheel_radius))
        \(mrIndent)label other_moment(disk_moment_of_inertia(mass: 5 * units.kg, radius: 6.0 * units.cm))

        \(mrIndent)crankshaft c0(
        \(mrIndent)\(mrIndent)throw: stroke / 2,
        \(mrIndent)\(mrIndent)flywheel_mass: flywheel_mass,
        \(mrIndent)\(mrIndent)mass: crank_mass,
        \(mrIndent)\(mrIndent)friction_torque: \(spec.crankFrictionLbFt) * units.lb_ft,
        \(mrIndent)\(mrIndent)moment_of_inertia: crank_moment + flywheel_moment + other_moment,
        \(mrIndent)\(mrIndent)position_x: 0.0,
        \(mrIndent)\(mrIndent)position_y: 0.0,
        \(mrIndent)\(mrIndent)tdc: \(tdcExpr)
        \(mrIndent))


        """

        // Rod-journal angle per cylinder. Inline/V engines bake the full firing
        // phase into the journal (firing_position * rotPerFiring). Flat (boxer)
        // engines place the n/2 opposed pairs on evenly-spaced crank throws
        // (720°/n apart). CRITICAL: the two cylinders WITHIN a bank must each sit
        // on a DISTINCT throw — two same-bank cylinders sharing a pin is a
        // rank-deficient layout the rigid-body solver can't resolve, so the crank
        // spins up on its own and RPM diverges to inf/garbage. bank0 = odd
        // cylinders, bank1 = even (see bank0Cylinders/bank1Cylinders), so cylinder
        // `cyl` occupies slot (cyl-1)/2 within its bank → throw (cyl-1)/2. The two
        // members of a pair share a throw but land on opposite banks, which is fine.
        let throwSpacingDeg = twoStrokeCycleDeg / Double(n)
        for cyl in 1...n {
            let angle: Double
            if isFlat {
                let bankSlot = (cyl - 1) / 2
                angle = Double(bankSlot) * throwSpacingDeg
            } else {
                guard let pos = firingOrder.firstIndex(of: cyl) else { continue }
                angle = Double(pos) * rotPerFiring
            }
            s += "\(mrIndent)rod_journal rj\(cyl - 1)(angle: \(angle) * units.deg) // cyl \(cyl)\n"
        }
        s += "\n\(mrIndent)c0\n"
        for cyl in 1...n {
            s += "\(mrIndent)\(mrIndent).add_rod_journal(rj\(cyl - 1))\n"
        }
        s += "\n"
        return s
    }

    private static func pistonAndRodParams(spec: EngineSpec) -> String {
        """
        \(mrIndent)piston_parameters piston_params(
        \(mrIndent)\(mrIndent)mass: \(spec.pistonMassG) * units.g,
        \(mrIndent)\(mrIndent)blowby: 0,
        \(mrIndent)\(mrIndent)compression_height: compression_height,
        \(mrIndent)\(mrIndent)wrist_pin_position: 0 * units.mm,
        \(mrIndent)\(mrIndent)displacement: 0.0
        \(mrIndent))

        \(mrIndent)connecting_rod_parameters cr_params(
        \(mrIndent)\(mrIndent)mass: rod_mass,
        \(mrIndent)\(mrIndent)moment_of_inertia: rod_moment_of_inertia(mass: rod_mass, length: rod_length),
        \(mrIndent)\(mrIndent)center_of_mass: 0.0,
        \(mrIndent)\(mrIndent)length: rod_length
        \(mrIndent))


        """
    }

    private static func bankAndIntakeExhaust(spec: EngineSpec, halfV: Double) -> String {
        let ir = "ir_lib.\(spec.impulseResponse.irLibField)"
        var s = """
        \(mrIndent)cylinder_bank_parameters bank_params(
        \(mrIndent)\(mrIndent)bore: bore,
        \(mrIndent)\(mrIndent)deck_height: stroke / 2 + rod_length + compression_height
        \(mrIndent))

        \(mrIndent)intake intake(
        \(mrIndent)\(mrIndent)plenum_volume: \(spec.intakePlenumVolumeL) * units.L,
        \(mrIndent)\(mrIndent)plenum_cross_section_area: \(spec.intakePlenumAreaCm2) * units.cm2,
        \(mrIndent)\(mrIndent)intake_flow_rate: k_carb(\(spec.intakeCfm)),
        \(mrIndent)\(mrIndent)runner_flow_rate: k_carb(\(spec.runnerCfm)),
        \(mrIndent)\(mrIndent)runner_length: \(spec.intakeRunnerLengthIn) * units.inch,
        \(mrIndent)\(mrIndent)idle_flow_rate: k_carb(\(spec.idleCfm)),
        \(mrIndent)\(mrIndent)idle_throttle_plate_position: \(spec.idleThrottlePosition)
        \(mrIndent))

        \(mrIndent)exhaust_system_parameters es_params(
        \(mrIndent)\(mrIndent)outlet_flow_rate: k_carb(1000.0),
        \(mrIndent)\(mrIndent)primary_tube_length: \(spec.exhaustPrimaryLengthIn) * units.inch,
        \(mrIndent)\(mrIndent)primary_flow_rate: k_carb(400.0),
        \(mrIndent)\(mrIndent)velocity_decay: 1.0,
        \(mrIndent)\(mrIndent)collector_cross_section_area: circle_area(\(spec.exhaustCollectorBoreIn / 2.0) * units.inch)
        \(mrIndent))

        \(mrIndent)exhaust_system exhaust0(
        \(mrIndent)\(mrIndent)es_params,
        \(mrIndent)\(mrIndent)length: \(spec.exhaustLengthIn) * units.inch,
        \(mrIndent)\(mrIndent)audio_volume: \(spec.exhaustAudioVolume),
        \(mrIndent)\(mrIndent)impulse_response: \(ir)
        \(mrIndent))

        """
        if spec.layout.bankCount == 2 {
            s += """
            \(mrIndent)exhaust_system exhaust1(
            \(mrIndent)\(mrIndent)es_params,
            \(mrIndent)\(mrIndent)length: \(spec.exhaustLengthIn) * units.inch,
            \(mrIndent)\(mrIndent)audio_volume: \(spec.exhaustAudioVolume),
            \(mrIndent)\(mrIndent)impulse_response: \(ir)
            \(mrIndent))

            """
        }
        s += "\n\(mrIndent)cylinder_bank b0(bank_params, angle: -\(halfV) * units.deg)\n"
        if spec.layout.bankCount == 2 {
            s += "\(mrIndent)cylinder_bank b1(bank_params, angle: \(halfV) * units.deg)\n"
        }
        s += "\n"
        return s
    }

    private static func bankCylinders(spec: EngineSpec,
                                       bankIndex: Int,
                                       bankCyls: [Int],
                                       exhaustName: String,
                                       wirePrefix: String) -> String {
        var s = "\(mrIndent)b\(bankIndex)\n"
        for (idx, cyl) in bankCyls.enumerated() {
            let rj = "rj\(cyl - 1)"
            let wire = "\(wirePrefix)\(cyl)"
            let primary = Double(bankCyls.count - 1 - idx) * 2.0 + 4.0
            s += """
            \(mrIndent)\(mrIndent).add_cylinder(
            \(mrIndent)\(mrIndent)\(mrIndent)piston: piston(piston_params, blowby: k_28inH2O(\(spec.blowby))),
            \(mrIndent)\(mrIndent)\(mrIndent)connecting_rod: connecting_rod(cr_params),
            \(mrIndent)\(mrIndent)\(mrIndent)rod_journal: \(rj),
            \(mrIndent)\(mrIndent)\(mrIndent)intake: intake,
            \(mrIndent)\(mrIndent)\(mrIndent)exhaust_system: \(exhaustName),
            \(mrIndent)\(mrIndent)\(mrIndent)ignition_wire: \(wire),
            \(mrIndent)\(mrIndent)\(mrIndent)primary_length: \(primary) * units.inch,
            \(mrIndent)\(mrIndent)\(mrIndent)sound_attenuation: 1.0
            \(mrIndent)\(mrIndent))

            """
        }
        return s
    }

    private static func camAndIgnitionInstall(spec: EngineSpec, nodeName: String) -> String {
        let vtec = spec.vtecEnabled

        var s = """
        \(mrIndent)harmonic_cam_lobe intake_lobe(
        \(mrIndent)\(mrIndent)duration_at_50_thou: \(spec.camDurationDeg) * units.deg,
        \(mrIndent)\(mrIndent)gamma: 1.1,
        \(mrIndent)\(mrIndent)lift: \(spec.camLiftMm) * units.mm,
        \(mrIndent)\(mrIndent)steps: 100
        \(mrIndent))

        \(mrIndent)harmonic_cam_lobe exhaust_lobe(
        \(mrIndent)\(mrIndent)duration_at_50_thou: \(spec.camDurationDeg) * units.deg,
        \(mrIndent)\(mrIndent)gamma: 1.1,
        \(mrIndent)\(mrIndent)lift: \(spec.camLiftMm * 0.98) * units.mm,
        \(mrIndent)\(mrIndent)steps: 100
        \(mrIndent))


        """

        if vtec {
            s += """
            \(mrIndent)harmonic_cam_lobe vtec_intake_lobe(
            \(mrIndent)\(mrIndent)duration_at_50_thou: \(spec.vtecCamDurationDeg) * units.deg,
            \(mrIndent)\(mrIndent)gamma: 1.1,
            \(mrIndent)\(mrIndent)lift: \(spec.vtecCamLiftMm) * units.mm,
            \(mrIndent)\(mrIndent)steps: 100
            \(mrIndent))

            \(mrIndent)harmonic_cam_lobe vtec_exhaust_lobe(
            \(mrIndent)\(mrIndent)duration_at_50_thou: \(spec.vtecCamDurationDeg) * units.deg,
            \(mrIndent)\(mrIndent)gamma: 1.1,
            \(mrIndent)\(mrIndent)lift: \(spec.vtecCamLiftMm * 0.98) * units.mm,
            \(mrIndent)\(mrIndent)steps: 100
            \(mrIndent))


            """
        }

        s += "\(mrIndent)\(nodeName)_camshaft_builder camshaft(\n"
        s += "\(mrIndent)\(mrIndent)intake_lobe_profile: intake_lobe,\n"
        s += "\(mrIndent)\(mrIndent)exhaust_lobe_profile: exhaust_lobe,\n"
        s += "\(mrIndent)\(mrIndent)lobe_separation: \(spec.camLobeSeparationDeg) * units.deg,\n"
        s += "\(mrIndent)\(mrIndent)intake_lobe_center: \(spec.camLobeSeparationDeg) * units.deg,\n"
        s += "\(mrIndent)\(mrIndent)exhaust_lobe_center: \(spec.camLobeSeparationDeg) * units.deg,\n"
        s += "\(mrIndent)\(mrIndent)advance: \(spec.camAdvanceDeg) * units.deg,\n"
        if vtec {
            s += "\(mrIndent)\(mrIndent)vtec_intake_lobe_profile: vtec_intake_lobe,\n"
            s += "\(mrIndent)\(mrIndent)vtec_exhaust_lobe_profile: vtec_exhaust_lobe,\n"
            s += "\(mrIndent)\(mrIndent)vtec_lobe_separation: \(spec.vtecCamLobeSeparationDeg) * units.deg,\n"
            s += "\(mrIndent)\(mrIndent)vtec_intake_lobe_center: \(spec.vtecCamLobeSeparationDeg) * units.deg,\n"
            s += "\(mrIndent)\(mrIndent)vtec_exhaust_lobe_center: \(spec.vtecCamLobeSeparationDeg) * units.deg,\n"
        }
        s += "\(mrIndent)\(mrIndent)base_radius: \(spec.camBaseRadiusIn) * units.inch\n"
        s += "\(mrIndent))\n\n\n"

        s += headInstall(nodeName: nodeName, spec: spec)

        s += "\n\(mrIndent)function timing_curve(1000 * units.rpm)\n"
        s += "\(mrIndent)timing_curve\n"
        for pt in spec.ignitionTiming.sorted(by: { $0.rpm < $1.rpm }) {
            s += "\(mrIndent)\(mrIndent).add_sample(\(pt.rpm) * units.rpm, \(pt.advanceDeg) * units.deg)\n"
        }

        s += """

        \(mrIndent)engine.add_ignition_module(
        \(mrIndent)\(mrIndent)\(nodeName)_ignition(
        \(mrIndent)\(mrIndent)\(mrIndent)wires: wires,
        \(mrIndent)\(mrIndent)\(mrIndent)timing_curve: timing_curve,
        \(mrIndent)\(mrIndent)\(mrIndent)rev_limit: \(spec.revLimitRpm) * units.rpm,
        \(mrIndent)\(mrIndent)\(mrIndent)limiter_duration: \(spec.limiterDurationSec)
        \(mrIndent)\(mrIndent))
        \(mrIndent))

        """
        return s
    }

    // MARK: - Vehicle / transmission (placeholders)

    private static func vehicleNode(nodeName: String, spec: EngineSpec) -> String {
        """
        private node \(nodeName)_vehicle {
        \(mrIndent)alias output __out:
        \(mrIndent)\(mrIndent)vehicle(
        \(mrIndent)\(mrIndent)\(mrIndent)mass: \(spec.vehicleMassLb) * units.lb,
        \(mrIndent)\(mrIndent)\(mrIndent)drag_coefficient: \(spec.dragCoefficient),
        \(mrIndent)\(mrIndent)\(mrIndent)cross_sectional_area: (\(spec.frontalAreaWidthIn) * units.inch) * (\(spec.frontalAreaHeightIn) * units.inch),
        \(mrIndent)\(mrIndent)\(mrIndent)diff_ratio: \(spec.diffRatio),
        \(mrIndent)\(mrIndent)\(mrIndent)tire_radius: \(spec.tireRadiusIn) * units.inch,
        \(mrIndent)\(mrIndent)\(mrIndent)rolling_resistance: \(spec.rollingResistanceN) * units.N
        \(mrIndent)\(mrIndent));
        }

        """
    }

    private static func transmissionNode(nodeName: String, spec: EngineSpec) -> String {
        let ratios = spec.gearRatios.isEmpty ? fallbackGearRatios : spec.gearRatios
        var s = "private node \(nodeName)_transmission {\n"
        s += "\(mrIndent)alias output __out:\n"
        s += "\(mrIndent)\(mrIndent)transmission(\n"
        s += "\(mrIndent)\(mrIndent)\(mrIndent)max_clutch_torque: \(spec.clutchTorqueLbFt) * units.lb_ft\n"
        s += "\(mrIndent)\(mrIndent))"
        for (i, ratio) in ratios.enumerated() {
            let term = i == ratios.count - 1 ? ";" : ""
            s += "\n\(mrIndent)\(mrIndent)\(mrIndent).add_gear(\(ratio))\(term)"
        }
        s += "\n}\n"
        return s
    }

    private static func mainNode(nodeName: String) -> String {
        """
        public node main {
        \(mrIndent)set_engine(\(nodeName)())
        \(mrIndent)set_vehicle(\(nodeName)_vehicle())
        \(mrIndent)set_transmission(\(nodeName)_transmission())
        }
        """
    }

    // MARK: - Helpers

    /// Use the spec's firing order if it's a valid permutation; otherwise fall
    /// back to the layout default. Keeps generated .mr files valid even if the
    /// editor leaves the spec in an intermediate state.
    private static func effectiveFiringOrder(for spec: EngineSpec) -> [Int] {
        spec.firingOrderIsValid ? spec.firingOrder : spec.layout.firingOrder
    }

    private static func bank0Cylinders(layout: EngineLayout) -> [Int] {
        let n = layout.cylinderCount
        if layout.bankCount == 1 { return Array(1...n) }
        return (1...n).filter { $0.isMultiple(of: 2) == false }   // 1, 3, 5, ...
    }

    private static func bank1Cylinders(layout: EngineLayout) -> [Int] {
        let n = layout.cylinderCount
        if layout.bankCount == 1 { return [] }
        return (1...n).filter { $0.isMultiple(of: 2) }            // 2, 4, 6, ...
    }
}

private extension EngineSpec {
    /// Sanitized node name used in the generated .mr script (lowercase, alnum + underscore).
    var nodeName: String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        let lower = name.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        var s = String(lower)
        while s.contains("__") { s = s.replacingOccurrences(of: "__", with: "_") }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if s.isEmpty { s = "user_engine" }
        if let first = s.first, first.isNumber { s = "e_" + s }
        return s
    }
}
