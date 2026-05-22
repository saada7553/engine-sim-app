//
//  BuilderVtecControls.swift
//  engine-simulator
//
//  VTEC controls + graphic for the camshaft step, plus a reusable dash-style
//  toggle. The graphic overlays the two cam lobes — the mild low-rpm profile
//  and the high-lift VTEC profile that engages above the crossover RPM — so
//  the two-stage idea reads at a glance, in the same instrument language as
//  the rest of the builder.
//

import SwiftUI

// MARK: - Reusable toggle

struct BuilderToggle: View {
    let label: String
    @Binding var isOn: Bool

    private let trackWidth: CGFloat = 42
    private let trackHeight: CGFloat = 22
    private let knob: CGFloat = 16

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 12) {
                Text(label.uppercased())
                    .font(.system(size: Theme.FontSize.body, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(isOn ? .white : BuilderTheme.label)
                Spacer()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Color.accentLive.opacity(0.22) : Color.surfaceLow)
                        .overlay(Capsule().stroke(isOn ? Color.accentLive.opacity(0.7) : BuilderTheme.line,
                                                  lineWidth: Theme.Stroke.thin))
                        .frame(width: trackWidth, height: trackHeight)
                    Circle()
                        .fill(isOn ? Color.accentLive : BuilderTheme.label)
                        .frame(width: knob, height: knob)
                        .padding(.horizontal, (trackHeight - knob) / 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

// MARK: - VTEC section (drop into the cam step)

struct VtecSection: View {
    @ObservedObject var state: EngineBuilderState

    private var on: Bool { state.spec.vtecEnabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BuilderToggle(label: "VTEC · variable valvetrain", isOn: $state.spec.vtecEnabled)

            // The graphic and pitch are always visible — the two-stage lobe is
            // the whole appeal, so the user sees it before deciding to switch on.
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 10) {
                    VtecLobeProfile(lowDurationDeg: state.spec.camDurationDeg,
                                    lowLiftMm: state.spec.camLiftMm,
                                    highDurationDeg: state.spec.vtecCamDurationDeg,
                                    highLiftMm: state.spec.vtecCamLiftMm,
                                    active: on)
                        .frame(width: 150, height: 150)
                    VtecLegend()
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Two cams in one. A calm street lobe down low that snaps to a high-lift, high-flow race lobe once the revs cross the threshold.")
                        .font(.system(size: Theme.FontSize.callout, weight: .regular, design: .monospaced))
                        .foregroundColor(BuilderTheme.label)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if on {
                        BuilderSlider(label: "Crossover", value: $state.spec.vtecCrossoverRpm,
                                      range: 3000...10000, step: 100, unit: "rpm", format: "%.0f")
                        BuilderSlider(label: "VTEC duration", value: $state.spec.vtecCamDurationDeg,
                                      range: 220...300, step: 1, unit: "°", format: "%.0f")
                        BuilderSlider(label: "VTEC lift", value: $state.spec.vtecCamLiftMm,
                                      range: 9...16, step: 0.1, unit: "mm")
                        BuilderSlider(label: "VTEC lobe separation", value: $state.spec.vtecCamLobeSeparationDeg,
                                      range: 98...116, step: 0.5, unit: "°")
                    } else {
                        Text("Flip the switch to set the crossover and grind the second cam.")
                            .font(.system(size: Theme.FontSize.footnote, weight: .regular, design: .monospaced))
                            .foregroundColor(BuilderTheme.dim)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: on)
    }
}

// MARK: - Legend

private struct VtecLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            swatch(dashed: true, color: BuilderTheme.label, label: "STREET")
            swatch(dashed: false, color: .accentLive, label: "VTEC")
        }
    }

    private func swatch(dashed: Bool, color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1)
                .stroke(color, style: StrokeStyle(lineWidth: 1.4, dash: dashed ? [2.5, 2.5] : []))
                .frame(width: 14, height: 6)
            Text(label)
                .font(.system(size: Theme.FontSize.micro, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(BuilderTheme.label)
        }
    }
}

// MARK: - Dual-lobe graphic

private struct VtecLobeProfile: View {
    let lowDurationDeg: Double
    let lowLiftMm: Double
    let highDurationDeg: Double
    let highLiftMm: Double
    var active: Bool = true

    // The largest lift the slider allows. The drawing scales so even a
    // max-lift lobe stays inside the frame and never collides with the title.
    private let maxLiftMm: CGFloat = 16
    private let framePadding: CGFloat = 8

    private var vtecColor: Color { active ? .accentLive : BuilderTheme.dim }

    var body: some View {
        GeometryReader { proxy in
            let c = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let outer = min(proxy.size.width, proxy.size.height) / 2 - framePadding
            let base = outer * 0.42
            let scale = (outer - base) / maxLiftMm   // max-lift lobe just reaches `outer`
            ZStack {
                Circle()
                    .stroke(BuilderTheme.line, lineWidth: 1)
                    .frame(width: base * 2, height: base * 2)
                    .position(c)

                // Low-rpm (mild) street lobe.
                lobePath(center: c, base: base, scale: scale, durationDeg: lowDurationDeg, liftMm: lowLiftMm)
                    .stroke(BuilderTheme.label, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))

                // VTEC (high-lift) lobe — accent when on, muted when off.
                lobePath(center: c, base: base, scale: scale, durationDeg: highDurationDeg, liftMm: highLiftMm)
                    .fill(vtecColor.opacity(0.18))
                lobePath(center: c, base: base, scale: scale, durationDeg: highDurationDeg, liftMm: highLiftMm)
                    .stroke(vtecColor, lineWidth: 1.4)
            }
        }
    }

    private func lobePath(center: CGPoint, base: CGFloat, scale: CGFloat, durationDeg: Double, liftMm: Double) -> Path {
        let liftPx = CGFloat(liftMm) * scale
        let baseRadius = base
        let halfBump = durationDeg / 2
        return Path { p in
            let steps = 220
            for i in 0...steps {
                let angle = -90.0 + Double(i) / Double(steps) * 360.0
                let delta = abs(angularDelta(angle, -90))
                let r: CGFloat
                if delta <= halfBump {
                    let bump = pow(cos((delta / halfBump) * .pi / 2), 2)
                    r = baseRadius + liftPx * CGFloat(bump)
                } else {
                    r = baseRadius
                }
                let rad = angle * .pi / 180
                let pt = CGPoint(x: center.x + r * CGFloat(cos(rad)),
                                 y: center.y + r * CGFloat(sin(rad)))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }

    /// Signed smallest angular difference (degrees) between two angles.
    private func angularDelta(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}
