//
//  BuilderAdvancedSteps.swift
//  engine-simulator
//
//  Advanced flat editor + final review/save step. Long-tail fields live here;
//  the cinematic steps cover the headline choices.
//

import SwiftUI

// MARK: - Advanced

struct AdvancedStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BuilderSectionHeading(title: "Step 9 · Advanced")
            Text("These knobs round out the spec. Defaults give a running engine — change them only if you want a specific behaviour.")
                .font(.system(size: Theme.FontSize.control, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.label)
                .lineSpacing(4)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AdvancedSection(title: "Masses & friction") {
                        BuilderSlider(label: "Piston mass", value: $state.spec.pistonMassG,
                                      range: 100...600, step: 5, unit: "g", format: "%.0f")
                        BuilderSlider(label: "Rod mass", value: $state.spec.rodMassG,
                                      range: 200...900, step: 10, unit: "g", format: "%.0f")
                        BuilderSlider(label: "Crank mass", value: $state.spec.crankMassKg,
                                      range: 5...40, step: 0.5, unit: "kg")
                        BuilderSlider(label: "Flywheel mass", value: $state.spec.flywheelMassKg,
                                      range: 2...30, step: 0.5, unit: "kg")
                        BuilderSlider(label: "Flywheel radius", value: $state.spec.flywheelRadiusIn,
                                      range: 4...12, step: 0.25, unit: "in")
                        BuilderSlider(label: "Crank friction torque", value: $state.spec.crankFrictionLbFt,
                                      range: 1...30, step: 0.5, unit: "lb-ft")
                    }

                    AdvancedSection(title: "Cylinder head") {
                        BuilderSlider(label: "Chamber volume", value: $state.spec.chamberVolumeCc,
                                      range: 30...120, step: 1, unit: "cc", format: "%.0f")
                        BuilderSlider(label: "Intake runner volume",
                                      value: $state.spec.intakeRunnerVolumeCc,
                                      range: 50...500, step: 5, unit: "cc", format: "%.0f")
                        BuilderSlider(label: "Intake runner CSA",
                                      value: $state.spec.intakeRunnerAreaInSq,
                                      range: 1.0...6.0, step: 0.05, unit: "in²", format: "%.2f")
                        BuilderSlider(label: "Exhaust runner volume",
                                      value: $state.spec.exhaustRunnerVolumeCc,
                                      range: 20...300, step: 5, unit: "cc", format: "%.0f")
                        BuilderSlider(label: "Exhaust runner CSA",
                                      value: $state.spec.exhaustRunnerAreaInSq,
                                      range: 0.5...4.0, step: 0.05, unit: "in²", format: "%.2f")
                        BuilderSlider(label: "Port flow scale", value: $state.spec.portFlowScale,
                                      range: 0.5...1.6, step: 0.02, unit: "×", format: "%.2f")
                        BuilderSlider(label: "Cam base radius", value: $state.spec.camBaseRadiusIn,
                                      range: 0.4...1.2, step: 0.01, unit: "in", format: "%.2f")
                    }

                    AdvancedSection(title: "Idle / Intake fine-tuning") {
                        BuilderSlider(label: "Idle CFM", value: $state.spec.idleCfm,
                                      range: 0...10, step: 0.1, unit: "", format: "%.1f")
                    }

                    AdvancedSection(title: "Starter & condition") {
                        BuilderSlider(label: "Starter torque", value: $state.spec.starterTorqueLbFt,
                                      range: 50...600, step: 5, unit: "lb-ft", format: "%.0f")
                        BuilderSlider(label: "Starter speed", value: $state.spec.starterSpeedRpm,
                                      range: 80...400, step: 5, unit: "rpm", format: "%.0f")
                        BuilderSlider(label: "Blowby (ring wear)", value: $state.spec.blowby,
                                      range: 0...2, step: 0.05, unit: "", format: "%.2f")
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }
}

private struct AdvancedSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(title.uppercased())
                    .font(.system(size: Theme.FontSize.callout, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.white)
                Rectangle().fill(BuilderTheme.line).frame(height: 1)
            }
            content
        }
    }
}

// MARK: - Review

struct ReviewStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 18) {
                BuilderSectionHeading(title: "Step 10 · Review and save")

                Text(state.spec.name.isEmpty ? "Untitled" : state.spec.name)
                    .font(.system(size: 40, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)

                Text("\(state.spec.layout.displayName) · \(String(format: "%.2f", state.spec.displacementLitres)) L · \(Int(state.spec.redlineRpm)) rpm")
                    .font(.system(size: Theme.FontSize.headline, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.accent)

                Spacer().frame(height: 12)

                Text("When you save, this engine will join the sidebar and the simulation will swap to it automatically. The car body, transmission and gearing use the standard placeholder.")
                    .font(.system(size: Theme.FontSize.control, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .lineSpacing(4)
                    .frame(maxWidth: 460)

                if !state.nameIsValid {
                    Text("⚠ Engine needs a name before it can be saved.")
                        .font(.system(size: Theme.FontSize.callout, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentWarn)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)

            Spacer()

            SpecSheet(spec: state.spec)
                .frame(width: 320)
        }
    }
}

private struct SpecSheet: View {
    let spec: EngineSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SPEC SHEET")
                    .font(.system(size: Theme.FontSize.body, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.black)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(BuilderTheme.accent)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 0) {
                row("LAYOUT", spec.layout.displayName)
                row("CYLINDERS", "\(spec.layout.cylinderCount)")
                row("DISPLACEMENT", String(format: "%.2f L", spec.displacementLitres))
                row("BORE × STROKE", String(format: "%.1f × %.1f mm", spec.boreMm, spec.strokeMm))
                row("ROD LENGTH", String(format: "%.1f mm", spec.rodLengthMm))
                row("CAM DURATION", String(format: "%.0f°", spec.camDurationDeg))
                row("CAM LIFT", String(format: "%.2f mm", spec.camLiftMm))
                row("INTAKE", String(format: "%.0f CFM", spec.intakeCfm))
                row("REDLINE", "\(Int(spec.redlineRpm)) rpm")
                row("REV LIMIT", "\(Int(spec.revLimitRpm)) rpm")
                row("FUEL", spec.fuel.displayName)
                if spec.vtecEnabled {
                    row("VTEC", "on · \(Int(spec.vtecCrossoverRpm)) rpm crossover")
                }
                row("STARTER", String(format: "%.0f lb-ft · %.0f rpm", spec.starterTorqueLbFt, spec.starterSpeedRpm))
                row("BLOWBY", String(format: "%.2f", spec.blowby))
            }
            .padding(12)
            .overlay(Rectangle().stroke(BuilderTheme.line))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: Theme.FontSize.body, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(BuilderTheme.label)
            Spacer()
            Text(value)
                .font(.system(size: Theme.FontSize.callout, weight: .regular, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.vertical, 6)
        .overlay(Rectangle().fill(BuilderTheme.line.opacity(0.4)).frame(height: 0.5),
                 alignment: .bottom)
    }
}
