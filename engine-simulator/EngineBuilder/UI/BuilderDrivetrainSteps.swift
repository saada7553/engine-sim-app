//
//  BuilderDrivetrainSteps.swift
//  engine-simulator
//
//  Transmission and vehicle sections for the engine builder.
//

import SwiftUI

// MARK: - Constants

private enum DrivetrainDiagram {
    static let gearBarHeight: CGFloat = 18
    static let gearBarSpacing: CGFloat = 10
    static let gearRatioMin: Double = 0.4
    static let gearRatioMax: Double = 6.0
    static let gearRatioStep: Double = 0.01
    static let maxGears: Int = 8
    static let minGears: Int = 2
    static let chartLeftLabelWidth: CGFloat = 36
    static let chartRightValueWidth: CGFloat = 60

    static let vehicleSilhouetteWidth: CGFloat = 320
    static let vehicleSilhouetteHeight: CGFloat = 240
    static let tireTreadWidthIn: Double = 9     // typical tread width, head-on
    static let vehicleSlackBelowBodyIn: Double = 6
    static let vehicleSlackAboveBodyIn: Double = 8

    // Frontal-view slider maxima — used for stable scaling so adjusting one
    // dimension doesn't visually move the others.
    static let maxFrontalWidthIn: Double = 90
    static let maxFrontalHeightIn: Double = 80
    static let maxTireRadiusIn: Double = 16
}

private enum BrakeDiagram {
    static let discDiameterRange: ClosedRange<Double> = 9...16
    static let discDiameterStep: Double = 0.5
    static let padFrictionRange: ClosedRange<Double> = 0.25...0.55
    static let padFrictionStep: Double = 0.01
    static let clampForceRange: ClosedRange<Double> = 8_000...40_000
    static let clampForceStep: Double = 500

    static let diagramWidth: CGFloat = 320
    static let diagramHeight: CGFloat = 240
    // Scale the drawn rotor against the largest selectable disc so adjusting the
    // diameter visibly grows the rotor.
    static let maxDiscDiameterIn: Double = 16
    static let lbPerKg: Double = 0.453592
    static let newtonsPerLbf: Double = 4.44822
    static let gravity: Double = 9.80665
}

private let defaultGearRatios: [Double] = [5.25, 3.36, 2.17, 1.72, 1.32, 1.0]
private let newGearDefaultRatio: Double = 1.0

// MARK: - Transmission

struct TransmissionStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 22) {
                BuilderSectionHeading(title: "Step 9 · Transmission")
                Text("Clutch capacity caps how much torque can transfer.\nGear ratios multiply engine torque before the diff — lower number = taller gear.")
                    .font(.system(size: Theme.FontSize.control, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .lineSpacing(4)

                BuilderSlider(label: "Max clutch torque",
                              value: $state.spec.clutchTorqueLbFt,
                              range: 150...2500, step: 10, unit: "lb-ft", format: "%.0f")
                    .frame(maxWidth: 480)

                GearListEditor(ratios: $state.spec.gearRatios)
                    .frame(maxWidth: 480)
            }
            .frame(maxWidth: 520)

            VStack(spacing: 14) {
                BuilderSectionHeading(title: "Gear chart")
                GearRatioChart(ratios: state.spec.gearRatios)
                    .frame(width: 340, height: gearChartHeight)
            }
            Spacer()
        }
    }

    private var gearChartHeight: CGFloat {
        let count = max(state.spec.gearRatios.count, 1)
        return CGFloat(count) * (DrivetrainDiagram.gearBarHeight + DrivetrainDiagram.gearBarSpacing) + 24
    }
}

private struct GearListEditor: View {
    @Binding var ratios: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BuilderSectionHeading(title: "Gears (1st → top)")

            ForEach(Array(ratios.enumerated()), id: \.offset) { idx, _ in
                gearRow(index: idx)
            }

            HStack(spacing: 8) {
                Button(action: addGear) {
                    Text("+ ADD GEAR")
                        .font(.system(size: Theme.FontSize.body, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(BuilderTheme.label)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(Rectangle().stroke(BuilderTheme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(ratios.count >= DrivetrainDiagram.maxGears)
                .opacity(ratios.count >= DrivetrainDiagram.maxGears ? 0.35 : 1)

                Button(action: resetGears) {
                    Text("RESET")
                        .font(.system(size: Theme.FontSize.body, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(BuilderTheme.label)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(Rectangle().stroke(BuilderTheme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func gearRow(index: Int) -> some View {
        HStack(spacing: 10) {
            Text(gearLabel(index))
                .font(.system(size: Theme.FontSize.callout, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(BuilderTheme.label)
                .frame(width: 36, alignment: .leading)

            BuilderSlider(label: "ratio",
                          value: ratioBinding(for: index),
                          range: DrivetrainDiagram.gearRatioMin...DrivetrainDiagram.gearRatioMax,
                          step: DrivetrainDiagram.gearRatioStep,
                          unit: "",
                          format: "%.2f")

            Button(action: { removeGear(at: index) }) {
                Image(systemName: "trash")
                    .font(.system(size: Theme.FontSize.callout))
                    .foregroundColor(BuilderTheme.label)
                    .frame(width: 22, height: 22)
                    .overlay(Rectangle().stroke(BuilderTheme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(ratios.count <= DrivetrainDiagram.minGears)
            .opacity(ratios.count <= DrivetrainDiagram.minGears ? 0.35 : 1)
        }
    }

    private func gearLabel(_ idx: Int) -> String {
        switch idx {
        case 0: return "1st"
        case 1: return "2nd"
        case 2: return "3rd"
        default: return "\(idx + 1)th"
        }
    }

    private func ratioBinding(for index: Int) -> Binding<Double> {
        Binding(
            get: { index < ratios.count ? ratios[index] : newGearDefaultRatio },
            set: { newValue in
                guard index < ratios.count else { return }
                ratios[index] = newValue
            }
        )
    }

    private func addGear() {
        let last = ratios.last ?? newGearDefaultRatio
        // New gear sits between last and top; nudge slightly taller (lower ratio).
        let suggested = max(DrivetrainDiagram.gearRatioMin, last * 0.85)
        ratios.append(suggested)
    }

    private func removeGear(at index: Int) {
        guard ratios.count > DrivetrainDiagram.minGears,
              index >= 0, index < ratios.count else { return }
        ratios.remove(at: index)
    }

    private func resetGears() {
        ratios = defaultGearRatios
    }
}

private struct GearRatioChart: View {
    let ratios: [Double]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let usableW = w - DrivetrainDiagram.chartLeftLabelWidth - DrivetrainDiagram.chartRightValueWidth
            let maxRatio = max(ratios.max() ?? 1.0, 1.0)

            VStack(spacing: DrivetrainDiagram.gearBarSpacing) {
                ForEach(Array(ratios.enumerated()), id: \.offset) { idx, ratio in
                    HStack(spacing: 8) {
                        Text(idx == 0 ? "1st" : (idx == 1 ? "2nd" : (idx == 2 ? "3rd" : "\(idx + 1)th")))
                            .font(.system(size: Theme.FontSize.body, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(BuilderTheme.label)
                            .frame(width: DrivetrainDiagram.chartLeftLabelWidth, alignment: .leading)

                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(BuilderTheme.line)
                                .frame(height: 1)
                            Rectangle()
                                .fill(idx == 0 ? BuilderTheme.accent : Color.white.opacity(0.8))
                                .frame(width: usableW * CGFloat(ratio / maxRatio),
                                       height: DrivetrainDiagram.gearBarHeight)
                        }
                        .frame(height: DrivetrainDiagram.gearBarHeight)

                        Text(String(format: "%.2f", ratio))
                            .font(.system(size: Theme.FontSize.callout, weight: .regular, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: DrivetrainDiagram.chartRightValueWidth, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - Vehicle

struct VehicleStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 22) {
                BuilderSectionHeading(title: "Step 10 · Vehicle")
                Text("How much resistance the engine has to fight to push you forward.\nHeavier + more drag = harder pull; bigger tires + lower diff = taller gearing.")
                    .font(.system(size: Theme.FontSize.control, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .lineSpacing(4)

                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 18) {
                        BuilderSlider(label: "Mass", value: $state.spec.vehicleMassLb,
                                      range: 1500...6000, step: 25, unit: "lb", format: "%.0f")
                        BuilderSlider(label: "Drag coefficient",
                                      value: $state.spec.dragCoefficient,
                                      range: 0.15...0.6, step: 0.01, unit: "Cd", format: "%.2f")
                        BuilderSlider(label: "Frontal width",
                                      value: $state.spec.frontalAreaWidthIn,
                                      range: 50...90, step: 0.5, unit: "in")
                        BuilderSlider(label: "Frontal height",
                                      value: $state.spec.frontalAreaHeightIn,
                                      range: 40...80, step: 0.5, unit: "in")
                    }
                    .frame(maxWidth: 280)

                    VStack(alignment: .leading, spacing: 18) {
                        BuilderSlider(label: "Diff ratio", value: $state.spec.diffRatio,
                                      range: 2.5...5.5, step: 0.01, unit: "", format: "%.2f")
                        BuilderSlider(label: "Tire radius", value: $state.spec.tireRadiusIn,
                                      range: 8...16, step: 0.1, unit: "in")
                        BuilderSlider(label: "Rolling resistance",
                                      value: $state.spec.rollingResistanceN,
                                      range: 100...2000, step: 25, unit: "N", format: "%.0f")
                    }
                    .frame(maxWidth: 280)
                }
                .frame(maxWidth: 600)
            }
            .frame(maxWidth: 620)

            VehicleSilhouette(spec: state.spec)
                .frame(width: DrivetrainDiagram.vehicleSilhouetteWidth,
                       height: DrivetrainDiagram.vehicleSilhouetteHeight)
            Spacer()
        }
    }
}

/// Head-on view of the vehicle: car body rectangle sitting on two
/// rectangular tire tread profiles (tires viewed from the front, so they
/// are rectangles whose height = tire diameter, width = tread).
///
/// Scaling: the canvas represents a fixed real-world bounding box derived
/// from the slider maxima — adjusting one slider only moves its own element.
private struct VehicleSilhouette: View {
    let spec: EngineSpec

    var body: some View {
        VStack(spacing: 10) {
            BuilderSectionHeading(title: "Frontal view")
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height

                let canvasWidthIn = DrivetrainDiagram.maxFrontalWidthIn
                    + DrivetrainDiagram.tireTreadWidthIn * 2 + 8
                let canvasHeightIn = DrivetrainDiagram.maxFrontalHeightIn
                    + DrivetrainDiagram.maxTireRadiusIn * 2
                    + DrivetrainDiagram.vehicleSlackBelowBodyIn
                    + DrivetrainDiagram.vehicleSlackAboveBodyIn

                let scaleX = (w - 24) / CGFloat(canvasWidthIn)
                let scaleY = (h - 24) / CGFloat(canvasHeightIn)
                let scale = min(scaleX, scaleY)

                let centerX = w / 2
                let groundY = h - 16
                let tireDiameter = CGFloat(spec.tireRadiusIn * 2) * scale
                let tireWidth = CGFloat(DrivetrainDiagram.tireTreadWidthIn) * scale
                let tireTopY = groundY - tireDiameter
                let bodyHeight = CGFloat(spec.frontalAreaHeightIn) * scale
                let bodyWidth = CGFloat(spec.frontalAreaWidthIn) * scale
                let bodyBottomY = tireTopY - 1
                let bodyTopY = bodyBottomY - bodyHeight

                ZStack {
                    // Ground
                    Path { p in
                        p.move(to: CGPoint(x: 12, y: groundY))
                        p.addLine(to: CGPoint(x: w - 12, y: groundY))
                    }
                    .stroke(BuilderTheme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    // Car body (front view) — a single rectangle with a small
                    // roof break to read as "front of car" instead of a slab.
                    bodyShape(width: bodyWidth, height: bodyHeight)
                        .stroke(BuilderTheme.accent, lineWidth: 1.5)
                        .frame(width: bodyWidth, height: bodyHeight)
                        .position(x: centerX, y: (bodyTopY + bodyBottomY) / 2)

                    // Frontal area dimension callout
                    Text(String(format: "%.0f×%.0f in", spec.frontalAreaWidthIn, spec.frontalAreaHeightIn))
                        .font(.system(size: Theme.FontSize.body, weight: .bold, design: .monospaced))
                        .foregroundColor(BuilderTheme.accent)
                        .position(x: centerX, y: (bodyTopY + bodyBottomY) / 2)

                    // Tires (front view): vertical rectangles representing
                    // tread sitting on the ground. Width = tread, height = diameter.
                    tireRect(width: tireWidth, height: tireDiameter)
                        .position(x: centerX - bodyWidth / 2 + tireWidth / 2,
                                  y: tireTopY + tireDiameter / 2)
                    tireRect(width: tireWidth, height: tireDiameter)
                        .position(x: centerX + bodyWidth / 2 - tireWidth / 2,
                                  y: tireTopY + tireDiameter / 2)

                    // Tire diameter callout (left tire)
                    Text(String(format: "Ø %.1f", spec.tireRadiusIn * 2))
                        .font(.system(size: Theme.FontSize.caption, weight: .bold, design: .monospaced))
                        .foregroundColor(BuilderTheme.label)
                        .position(x: centerX - bodyWidth / 2 + tireWidth / 2,
                                  y: tireTopY + tireDiameter + 8)

                    // Stats overlay (top-right)
                    VStack(alignment: .trailing, spacing: 4) {
                        statLine("MASS", String(format: "%.0f lb", spec.vehicleMassLb))
                        statLine("AREA", String(format: "%.1f ft²", areaInSqFt(spec)))
                        statLine("Cd", String(format: "%.2f", spec.dragCoefficient))
                        statLine("DIFF", String(format: "%.2f", spec.diffRatio))
                    }
                    .padding(8)
                    .position(x: w - 60, y: 36)
                }
            }
        }
    }

    /// Car body silhouette viewed head-on: rectangle for the cabin/grille area
    /// with a slightly narrower roof line so it reads as "car" not "billboard".
    private func bodyShape(width: CGFloat, height: CGFloat) -> Path {
        Path { p in
            let roofInset: CGFloat = width * 0.18
            let roofHeight: CGFloat = height * 0.32
            // outer body rectangle
            p.move(to: CGPoint(x: 0, y: roofHeight))
            p.addLine(to: CGPoint(x: 0, y: height))
            p.addLine(to: CGPoint(x: width, y: height))
            p.addLine(to: CGPoint(x: width, y: roofHeight))
            // roof (narrower than body)
            p.addLine(to: CGPoint(x: width - roofInset, y: roofHeight))
            p.addLine(to: CGPoint(x: width - roofInset, y: 0))
            p.addLine(to: CGPoint(x: roofInset, y: 0))
            p.addLine(to: CGPoint(x: roofInset, y: roofHeight))
            p.closeSubpath()
        }
    }

    private func tireRect(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .overlay(Rectangle().stroke(Color.white.opacity(0.75), lineWidth: 1.5))
            .overlay(
                // Tread marks across the face — two horizontal lines.
                VStack(spacing: max(2, height * 0.25)) {
                    Rectangle().fill(Color.white.opacity(0.3)).frame(height: 0.5)
                    Rectangle().fill(Color.white.opacity(0.3)).frame(height: 0.5)
                }
                .padding(.horizontal, 2)
            )
            .frame(width: width, height: height)
    }

    private func areaInSqFt(_ spec: EngineSpec) -> Double {
        (spec.frontalAreaWidthIn * spec.frontalAreaHeightIn) / 144.0
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: Theme.FontSize.caption, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(BuilderTheme.label)
                .frame(width: 30, alignment: .leading)
            Text(value)
                .font(.system(size: Theme.FontSize.body, weight: .regular, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Brakes

struct BrakesStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 22) {
                BuilderSectionHeading(title: "Step 11 · Brakes")
                Text("How hard the car can stop. Bigger rotors, grippier pads and more\nclamp force all raise the braking force at the contact patch.")
                    .font(.system(size: Theme.FontSize.control, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .lineSpacing(4)

                VStack(alignment: .leading, spacing: 18) {
                    BuilderSlider(label: "Disc diameter",
                                  value: $state.spec.brakeDiscDiameterIn,
                                  range: BrakeDiagram.discDiameterRange,
                                  step: BrakeDiagram.discDiameterStep, unit: "in")
                    BuilderSlider(label: "Pad friction",
                                  value: $state.spec.brakePadFriction,
                                  range: BrakeDiagram.padFrictionRange,
                                  step: BrakeDiagram.padFrictionStep, unit: "µ", format: "%.2f")
                    BuilderSlider(label: "Clamp force",
                                  value: $state.spec.brakeClampForceN,
                                  range: BrakeDiagram.clampForceRange,
                                  step: BrakeDiagram.clampForceStep, unit: "N", format: "%.0f")
                }
                .frame(maxWidth: 320)

                BrakeDerivedReadout(spec: state.spec)
            }
            .frame(maxWidth: 620)

            BrakeCrossSection(spec: state.spec)
                .frame(width: BrakeDiagram.diagramWidth, height: BrakeDiagram.diagramHeight)
            Spacer()
        }
    }
}

/// The two numbers that matter, derived from the three inputs: the braking
/// force the physics actually uses, and an at-a-glance "stopping power" in g.
private struct BrakeDerivedReadout: View {
    let spec: EngineSpec

    private var maxForceLbf: Double { spec.maxBrakeForceN / BrakeDiagram.newtonsPerLbf }
    private var stoppingG: Double {
        let massKg = spec.vehicleMassLb * BrakeDiagram.lbPerKg
        guard massKg > 0 else { return 0 }
        return spec.maxBrakeForceN / massKg / BrakeDiagram.gravity
    }

    var body: some View {
        HStack(spacing: 28) {
            readout("MAX FORCE", String(format: "%.0f lbf", maxForceLbf))
            readout("STOPPING", String(format: "%.2f g", stoppingG))
        }
        .padding(.top, 4)
    }

    private func readout(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: Theme.FontSize.caption, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(BuilderTheme.label)
            Text(value)
                .font(.system(size: Theme.FontSize.title, weight: .regular, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

/// Face-on rotor with a caliper clamped over the top. The rotor diameter
/// tracks the disc-size slider; pad thickness tracks clamp force and the pads
/// tint with pad friction, so all three inputs read on the drawing.
private struct BrakeCrossSection: View {
    let spec: EngineSpec

    private let metalLight = Color(white: 0.5)
    private let metalMid = Color(white: 0.34)
    private let metalDark = Color(white: 0.2)
    private let outline = Color.white.opacity(0.25)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let center = CGPoint(x: w / 2, y: h * 0.56)

            let discFrac = CGFloat(spec.brakeDiscDiameterIn / BrakeDiagram.maxDiscDiameterIn)
            let outerR = min(w, h) * 0.34 * (0.6 + 0.4 * discFrac)
            let hubR = outerR * 0.32
            let holeRingR = outerR * 0.66
            let holeR = outerR * 0.08

            let clampFrac = CGFloat((spec.brakeClampForceN - BrakeDiagram.clampForceRange.lowerBound)
                / (BrakeDiagram.clampForceRange.upperBound - BrakeDiagram.clampForceRange.lowerBound))
            let padThickness = outerR * (0.10 + 0.10 * clampFrac)
            let frictionFrac = (spec.brakePadFriction - BrakeDiagram.padFrictionRange.lowerBound)
                / (BrakeDiagram.padFrictionRange.upperBound - BrakeDiagram.padFrictionRange.lowerBound)
            let padColor = Color.accentDanger.opacity(0.4 + 0.5 * frictionFrac)

            ZStack {
                // Rotor face.
                Circle()
                    .fill(RadialGradient(colors: [metalMid, metalDark],
                                         center: .center, startRadius: 0, endRadius: outerR))
                    .frame(width: outerR * 2, height: outerR * 2)
                    .overlay(Circle().stroke(outline, lineWidth: 1)
                        .frame(width: outerR * 2, height: outerR * 2))
                    .position(center)

                BrakeRotorFace(center: center, outerR: outerR, hubR: hubR,
                               holeRingR: holeRingR, holeR: holeR,
                               metalLight: metalLight, metalDark: metalDark, outline: outline)

                // Caliper bridging the top of the rim, pads squeezing the disc.
                let rimTopY = center.y - outerR
                let caliperW = outerR * 1.05
                let caliperH = outerR * 0.34
                RoundedRectangle(cornerRadius: 4)
                    .fill(metalMid)
                    .frame(width: caliperW, height: caliperH)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(outline, lineWidth: 1))
                    .position(x: center.x, y: rimTopY)

                // Single near-side pad on the disc face (the back pad is hidden
                // behind the rotor). Thickness grows with clamp force.
                RoundedRectangle(cornerRadius: 1.5).fill(padColor)
                    .frame(width: caliperW * 0.74, height: padThickness)
                    .position(x: center.x, y: rimTopY + outerR * 0.22)

                // Disc-size caption under the rotor.
                Text(String(format: "Ø %.1f in", spec.brakeDiscDiameterIn))
                    .font(.system(size: Theme.FontSize.caption, weight: .bold, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .position(x: center.x, y: center.y + outerR + 16)
            }
            .frame(width: w, height: h)
        }
    }
}

private struct BrakeRotorFace: View {
    let center: CGPoint
    let outerR: CGFloat
    let hubR: CGFloat
    let holeRingR: CGFloat
    let holeR: CGFloat
    let metalLight: Color
    let metalDark: Color
    let outline: Color

    var body: some View {
        Canvas { ctx, _ in
            // Cross-drilled holes.
            let holeCount = 8
            for i in 0..<holeCount {
                let a = Double(i) / Double(holeCount) * 2 * .pi
                let c = CGPoint(x: center.x + holeRingR * CGFloat(cos(a)),
                                y: center.y + holeRingR * CGFloat(sin(a)))
                let dot = Path(ellipseIn: CGRect(x: c.x - holeR, y: c.y - holeR,
                                                 width: holeR * 2, height: holeR * 2))
                ctx.fill(dot, with: .color(.black.opacity(0.55)))
                ctx.stroke(dot, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
            }
            // Hub.
            let hub = Path(ellipseIn: CGRect(x: center.x - hubR, y: center.y - hubR,
                                             width: hubR * 2, height: hubR * 2))
            ctx.fill(hub, with: .color(metalLight.opacity(0.7)))
            ctx.stroke(hub, with: .color(outline), lineWidth: 1)
        }
    }
}
