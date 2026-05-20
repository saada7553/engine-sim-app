//
//  BuilderCinematicSteps.swift
//  engine-simulator
//
//  Cinematic steps for the engine builder. Each step does one thing with
//  room to breathe — slider + live visual readout, not a form grid.
//

import SwiftUI

// MARK: - Identity

struct IdentityStep: View {
    @ObservedObject var state: EngineBuilderState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 64) {
            VStack(alignment: .leading, spacing: 28) {
                BuilderSectionHeading(title: "Step 1 · Name your engine")
                Text("Every great engine starts with a name.\nIt'll show in the sidebar once you save.")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .lineSpacing(4)

                ZStack(alignment: .leading) {
                    if state.spec.name.isEmpty {
                        Text("e.g. Skyline RB26")
                            .font(.system(size: 36, weight: .regular, design: .monospaced))
                            .foregroundColor(BuilderTheme.dim.opacity(0.3))
                    }
                    TextField("", text: $state.spec.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 36, weight: .regular, design: .monospaced))
                        .foregroundColor(.white)
                        .focused($focused)
                }
                Rectangle()
                    .fill(BuilderTheme.accent)
                    .frame(height: 1)

                Spacer().frame(height: 12)

                BuilderSlider(label: "Redline",
                              value: $state.spec.redlineRpm,
                              range: 3000...12000,
                              step: 100,
                              unit: "rpm",
                              format: "%.0f")
                    .frame(maxWidth: 380)
            }
            Spacer()

            EnginePlaceholderArt()
                .frame(width: 280, height: 280)
        }
        .onAppear { focused = true }
    }
}

private struct EnginePlaceholderArt: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Rectangle()
                    .stroke(BuilderTheme.line, lineWidth: 1)
                    .frame(width: CGFloat(220 - i * 30), height: CGFloat(220 - i * 30))
            }
            Rectangle()
                .stroke(BuilderTheme.accent, lineWidth: 1.5)
                .frame(width: 90, height: 90)
            Text("V8")
                .font(.system(size: 24, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.accent)
        }
    }
}

// MARK: - Layout

struct LayoutStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            BuilderSectionHeading(title: "Step 2 · Pick the architecture")

            Text("Each layout sets bank count, bank angle, and the firing order.\nEverything downstream — cam timing, intake routing — derives from this choice.")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.label)
                .lineSpacing(4)

            ScrollView {
                CardGrid(items: EngineLayout.allCases,
                         columns: 4,
                         isSelected: { state.spec.layout == $0 },
                         onSelect: { state.spec.layout = $0 }) { layout, selected in
                    LayoutCard(layout: layout, selected: selected)
                }
            }
        }
    }
}

private struct LayoutCard: View {
    let layout: EngineLayout
    let selected: Bool

    var body: some View {
        VStack(spacing: 12) {
            LayoutSilhouette(layout: layout, accent: selected)
                .frame(width: 90, height: 60)
            Text(layout.shortLabel)
                .font(.system(size: 22, weight: .regular, design: .monospaced))
                .foregroundColor(selected ? BuilderTheme.accent : .white)
            Text(layout.displayName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(BuilderTheme.label)
        }
    }
}

private struct LayoutSilhouette: View {
    let layout: EngineLayout
    let accent: Bool

    var body: some View {
        let color = accent ? BuilderTheme.accent : Color.white.opacity(0.75)
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let n = layout.cylinderCount
            let banks = layout.bankCount

            if banks == 1 {
                let cylW = w / CGFloat(n) * 0.7
                let gap = (w - cylW * CGFloat(n)) / CGFloat(n + 1)
                HStack(spacing: gap) {
                    ForEach(0..<n, id: \.self) { _ in
                        Rectangle().stroke(color, lineWidth: 1)
                            .frame(width: cylW, height: h * 0.7)
                    }
                }
                .padding(.horizontal, gap)
                .frame(maxHeight: .infinity, alignment: .center)
            } else {
                // V or flat: two rows
                let perBank = n / 2
                let cylW = w / CGFloat(perBank) * 0.7
                let gap = (w - cylW * CGFloat(perBank)) / CGFloat(perBank + 1)
                let tilt = layout.bankHalfAngleDeg / 90.0   // 0..1
                VStack(spacing: 0) {
                    HStack(spacing: gap) {
                        ForEach(0..<perBank, id: \.self) { _ in
                            Rectangle().stroke(color, lineWidth: 1)
                                .frame(width: cylW, height: h * 0.32)
                                .rotationEffect(.degrees(-15 * tilt))
                        }
                    }
                    HStack(spacing: gap) {
                        ForEach(0..<perBank, id: \.self) { _ in
                            Rectangle().stroke(color, lineWidth: 1)
                                .frame(width: cylW, height: h * 0.32)
                                .rotationEffect(.degrees(15 * tilt))
                        }
                    }
                }
                .padding(.horizontal, gap)
            }
        }
    }
}

// MARK: - Bottom End

struct BottomEndStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 22) {
                BuilderSectionHeading(title: "Step 3 · Bottom end")

                BigReadout(value: String(format: "%.2f", state.spec.displacementLitres),
                           unit: "L", label: "Displacement")
                    .padding(.bottom, 12)

                BuilderSlider(label: "Bore", value: $state.spec.boreMm,
                              range: 60...110, step: 0.5, unit: "mm")
                BuilderSlider(label: "Stroke", value: $state.spec.strokeMm,
                              range: 50...110, step: 0.5, unit: "mm")
                BuilderSlider(label: "Rod length", value: $state.spec.rodLengthMm,
                              range: 100...200, step: 0.5, unit: "mm")
                BuilderSlider(label: "Compression height", value: $state.spec.compressionHeightMm,
                              range: 20...50, step: 0.1, unit: "mm")
            }
            .frame(maxWidth: 480)

            VStack(spacing: 12) {
                BuilderSectionHeading(title: "Cylinder")
                CylinderSection(boreMm: state.spec.boreMm,
                                 strokeMm: state.spec.strokeMm,
                                 rodLengthMm: state.spec.rodLengthMm)
                    .frame(width: 220, height: 320)
                HStack {
                    StatBox(label: "B / S", value: String(format: "%.2f", state.spec.boreMm / state.spec.strokeMm))
                    StatBox(label: "R / S", value: String(format: "%.2f", state.spec.rodLengthMm / state.spec.strokeMm))
                }
                .frame(width: 220)
            }
            Spacer()
        }
    }
}

private struct CylinderSection: View {
    let boreMm: Double
    let strokeMm: Double
    let rodLengthMm: Double

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let scale = min(w / boreMm, h / (rodLengthMm + strokeMm)) * 0.85
            let bore = boreMm * scale
            let stroke = strokeMm * scale
            let rod = rodLengthMm * scale

            ZStack {
                Rectangle()
                    .stroke(BuilderTheme.line, lineWidth: 1)
                    .frame(width: bore, height: stroke + rod * 0.3)

                Rectangle()
                    .fill(BuilderTheme.accent.opacity(0.25))
                    .frame(width: bore * 0.92, height: stroke * 0.35)
                    .offset(y: -rod * 0.05)

                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: bore * 0.12, height: rod)
                    .offset(y: rod * 0.4)
            }
            .frame(width: w, height: h)
        }
    }
}

private struct StatBox: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(BuilderTheme.label)
            Text(value)
                .font(.system(size: 18, weight: .regular, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .overlay(Rectangle().stroke(BuilderTheme.line, lineWidth: 1))
    }
}

// MARK: - Cam

struct CamStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 22) {
                BuilderSectionHeading(title: "Step 4 · Camshaft")
                Text("Bigger duration and lift trade idle quality and low-end\ntorque for top-end horsepower.")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .lineSpacing(4)

                BuilderSlider(label: "Duration at 0.050″",
                              value: $state.spec.camDurationDeg,
                              range: 180...290, step: 1, unit: "°", format: "%.0f")
                BuilderSlider(label: "Max lift", value: $state.spec.camLiftMm,
                              range: 6...14, step: 0.1, unit: "mm")
                BuilderSlider(label: "Lobe separation",
                              value: $state.spec.camLobeSeparationDeg,
                              range: 100...124, step: 0.5, unit: "°")
                BuilderSlider(label: "Cam advance",
                              value: $state.spec.camAdvanceDeg,
                              range: -10...10, step: 0.5, unit: "°")
            }
            .frame(maxWidth: 480)

            VStack(spacing: 14) {
                BuilderSectionHeading(title: "Lobe profile")
                CamLobeGraph(durationDeg: state.spec.camDurationDeg,
                             liftMm: state.spec.camLiftMm)
                    .frame(width: 320, height: 220)
            }
            Spacer()
        }
    }
}

private struct CamLobeGraph: View {
    let durationDeg: Double
    let liftMm: Double

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let samples = 60

            ZStack {
                Rectangle().stroke(BuilderTheme.line, lineWidth: 1)

                // Grid
                ForEach(1..<4, id: \.self) { i in
                    Path { p in
                        let y = h * CGFloat(i) / 4
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(BuilderTheme.line.opacity(0.6), lineWidth: 0.5)
                }

                // Lobe curve (cos^gamma scaled to lift)
                Path { p in
                    for i in 0...samples {
                        let t = Double(i) / Double(samples)
                        let angle = (t - 0.5) * durationDeg  // ° from centerline
                        let halfDuration = durationDeg / 2
                        let normalized = abs(angle) / halfDuration
                        let lift = max(0, pow(cos(normalized * .pi / 2), 1.5))
                        let x = CGFloat(t) * w
                        let y = h - CGFloat(lift) * h * 0.85
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(BuilderTheme.accent, lineWidth: 1.5)

                VStack {
                    HStack {
                        Spacer()
                        Text(String(format: "%.1f mm", liftMm))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(BuilderTheme.accent)
                            .padding(6)
                    }
                    Spacer()
                    HStack {
                        Text("\(Int(durationDeg))° @ 0.050″")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(BuilderTheme.label)
                            .padding(6)
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - Induction

struct InductionStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            BuilderSectionHeading(title: "Step 5 · Induction")
            Text("How much air the engine can swallow at full throttle.\nIntake CFM is the headline number; the rest fine-tunes plenum response.")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.label)
                .lineSpacing(4)

            HStack(alignment: .top, spacing: 64) {
                VStack(alignment: .leading, spacing: 20) {
                    BigReadout(value: "\(Int(state.spec.intakeCfm))",
                               unit: "cfm", label: "Intake")
                        .padding(.bottom, 8)

                    BuilderSlider(label: "Intake CFM", value: $state.spec.intakeCfm,
                                  range: 200...1200, step: 10, unit: "", format: "%.0f")
                    BuilderSlider(label: "Runner CFM", value: $state.spec.runnerCfm,
                                  range: 50...600, step: 5, unit: "", format: "%.0f")
                    BuilderSlider(label: "Runner length",
                                  value: $state.spec.intakeRunnerLengthIn,
                                  range: 4...40, step: 0.5, unit: "in")
                }
                .frame(maxWidth: 480)

                VStack(alignment: .leading, spacing: 20) {
                    BuilderSlider(label: "Plenum volume",
                                  value: $state.spec.intakePlenumVolumeL,
                                  range: 0.5...4.0, step: 0.05, unit: "L", format: "%.2f")
                    BuilderSlider(label: "Plenum CSA",
                                  value: $state.spec.intakePlenumAreaCm2,
                                  range: 5...60, step: 0.5, unit: "cm²")
                    BuilderSlider(label: "Idle throttle",
                                  value: $state.spec.idleThrottlePosition,
                                  range: 0.985...0.999, step: 0.0005, unit: "", format: "%.4f")
                }
                .frame(maxWidth: 380)
            }
            Spacer()
        }
    }
}

// MARK: - Exhaust

struct ExhaustStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            BuilderSectionHeading(title: "Step 6 · Exhaust & sound")

            HStack(alignment: .top, spacing: 64) {
                VStack(alignment: .leading, spacing: 20) {
                    BuilderSlider(label: "Primary length",
                                  value: $state.spec.exhaustPrimaryLengthIn,
                                  range: 8...50, step: 0.5, unit: "in")
                    BuilderSlider(label: "Collector bore",
                                  value: $state.spec.exhaustCollectorBoreIn,
                                  range: 1.5...4.0, step: 0.1, unit: "in")
                    BuilderSlider(label: "Total length",
                                  value: $state.spec.exhaustLengthIn,
                                  range: 30...200, step: 1, unit: "in")
                    BuilderSlider(label: "Audio volume",
                                  value: $state.spec.exhaustAudioVolume,
                                  range: 0.05...4.0, step: 0.05, unit: "", format: "%.2f")
                }
                .frame(maxWidth: 480)

                VStack(alignment: .leading, spacing: 14) {
                    BuilderSectionHeading(title: "Impulse response")
                    ForEach(ImpulseResponseChoice.allCases) { choice in
                        let selected = state.spec.impulseResponse == choice
                        Button(action: { state.spec.impulseResponse = choice }) {
                            HStack {
                                Rectangle()
                                    .fill(selected ? BuilderTheme.accent : Color.clear)
                                    .overlay(Rectangle().stroke(selected ? BuilderTheme.accent : BuilderTheme.line))
                                    .frame(width: 10, height: 10)
                                Text(choice.displayName)
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundColor(selected ? .white : BuilderTheme.label)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 280)
            }
            Spacer()
        }
    }
}

// MARK: - Ignition + Fuel

struct IgnitionFuelStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            BuilderSectionHeading(title: "Step 7 · Ignition & Fuel")

            HStack(alignment: .top, spacing: 64) {
                VStack(alignment: .leading, spacing: 20) {
                    BigReadout(value: "\(Int(state.spec.revLimitRpm))",
                               unit: "rpm", label: "Rev Limit")
                        .padding(.bottom, 8)

                    BuilderSlider(label: "Rev limit", value: $state.spec.revLimitRpm,
                                  range: 4000...12000, step: 100, unit: "rpm", format: "%.0f")
                    BuilderSlider(label: "Limiter duration",
                                  value: $state.spec.limiterDurationSec,
                                  range: 0.02...0.5, step: 0.01, unit: "s", format: "%.2f")
                }
                .frame(maxWidth: 420)

                VStack(alignment: .leading, spacing: 14) {
                    BuilderSectionHeading(title: "Fuel")
                    CardGrid(items: FuelPreset.allCases, columns: 2,
                             isSelected: { state.spec.fuel == $0 },
                             onSelect: { state.spec.fuel = $0 }) { fuel, selected in
                        VStack(spacing: 6) {
                            Text(fuel.displayName.uppercased())
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(selected ? BuilderTheme.accent : .white)
                        }
                        .padding(.vertical, 16)
                    }
                }
                .frame(maxWidth: 320)
            }
            Spacer()
        }
    }
}
