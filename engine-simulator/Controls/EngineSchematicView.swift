//
//  EngineSchematicView.swift
//  engine-simulator
//
//  Stylised engine-block cross-section for the Engine Health tile's
//  damage area. Every row follows the same three-column layout
//
//      [ left col (calloutColumnWidth) | main area | right col (calloutColumnWidth) ]
//
//  so the cylinder bores, the head / crank bars, the main-bearing
//  journals and the pump callouts all stay vertically aligned.
//

import SwiftUI

// MARK: - Palette / constants

private let healthyColor = Color.green
private let warningColor = Color.orange
private let criticalColor = Color.red
private let neutralStroke = Color.white.opacity(0.18)
private let labelColor = Color.white.opacity(0.55)
private let boreEmptyFill = Color.white.opacity(0.05)
private let pumpOffOpacity: Double = 0.30

private let warnThreshold: Double = 0.70
private let critThreshold: Double = 0.30

private let calloutColumnWidth: CGFloat = 64
private let calloutIconSize: CGFloat = 18
private let pumpIconSize: CGFloat = 24
private let mainBrgDot: CGFloat = 7
private let headBarHeight: CGFloat = 8
private let crankBarHeight: CGFloat = 8
private let rowSpacing: CGFloat = 5
private let columnSpacing: CGFloat = 8
private let outerHPadding: CGFloat = 4

// MARK: - Helpers

private func healthColor(_ v: Double) -> Color {
    if v < critThreshold { return criticalColor }
    if v < warnThreshold { return warningColor }
    return healthyColor
}

private func cylinderWorstHealth(_ c: CylinderHealthState) -> Double {
    min(c.headGasket, c.pistonRings, c.piston, c.rod, c.rodBearing,
        c.intakeValve, c.exhaustValve)
}

private func worstAcross(_ healths: [CylinderHealthState],
                         _ extract: (CylinderHealthState) -> Double) -> Double {
    healths.map(extract).min() ?? 1.0
}

// MARK: - EngineSchematicView

struct EngineSchematicView: View {
    let cylinders: [CylinderHealthState]
    let wide: EngineWideHealthState
    let coolantPumpOn: Bool
    let oilPumpOn: Bool

    var body: some View {
        if cylinders.isEmpty {
            emptyState
        } else {
            VStack(spacing: rowSpacing) {
                topCalloutRow
                cylHeadBar
                engineBodyRow
                crankBar
                mainBearingRow
                Spacer(minLength: 4)
                pumpsRow
            }
            .padding(.vertical, 6)
            .padding(.horizontal, outerHPadding)
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("NO ENGINE LOADED")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(labelColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Three-column row builder

    /// Every row in the schematic is a HStack of:
    ///   [ left (calloutColumnWidth) | main (flex) | right (calloutColumnWidth) ]
    private func row<Left: View, Main: View, Right: View>(
        leftAlign: Alignment = .center,
        rightAlign: Alignment = .center,
        @ViewBuilder left: () -> Left,
        @ViewBuilder main: () -> Main,
        @ViewBuilder right: () -> Right
    ) -> some View {
        HStack(spacing: columnSpacing) {
            left()
                .frame(width: calloutColumnWidth, alignment: leftAlign)
            main()
                .frame(maxWidth: .infinity)
            right()
                .frame(width: calloutColumnWidth, alignment: rightAlign)
        }
    }

    // MARK: Rows

    private var topCalloutRow: some View {
        row(leftAlign: .leading, rightAlign: .trailing) {
            calloutChip(label: "GASKET",
                        shape: AnyShape(HeadGasketIcon()),
                        health: worstAcross(cylinders, { $0.headGasket }))
        } main: {
            Color.clear.frame(height: 1)
        } right: {
            calloutChip(label: "CAM",
                        shape: AnyShape(CamshaftIcon()),
                        health: wide.camshaft,
                        labelOnLeft: true)
        }
    }

    private var cylHeadBar: some View {
        row(leftAlign: .trailing, rightAlign: .leading) {
            Text("CYL HEAD")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(labelColor)
        } main: {
            barRect(color: healthColor(wide.cylinderHead),
                    barHeight: headBarHeight)
        } right: {
            Color.clear.frame(height: 1)
        }
    }

    private var engineBodyRow: some View {
        row(leftAlign: .trailing, rightAlign: .leading) {
            VStack(alignment: .trailing, spacing: 6) {
                calloutChip(label: "RINGS",
                            shape: AnyShape(PistonRingsIcon()),
                            health: worstAcross(cylinders, { $0.pistonRings }),
                            labelOnLeft: true)
                calloutChip(label: "PISTON",
                            shape: AnyShape(PistonIcon()),
                            health: worstAcross(cylinders, { $0.piston }),
                            labelOnLeft: true)
                calloutChip(label: "ROD",
                            shape: AnyShape(ConnectingRodIcon()),
                            health: worstAcross(cylinders, { $0.rod }),
                            labelOnLeft: true)
            }
        } main: {
            HStack(spacing: 3) {
                ForEach(0..<cylinders.count, id: \.self) { i in
                    CylinderBore(cylinder: cylinders[i],
                                 cylinderNumber: i + 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        } right: {
            VStack(alignment: .leading, spacing: 6) {
                calloutChip(label: "IN.VLV",
                            shape: AnyShape(IntakeValveIcon()),
                            health: worstAcross(cylinders, { $0.intakeValve }))
                calloutChip(label: "EX.VLV",
                            shape: AnyShape(ExhaustValveIcon()),
                            health: worstAcross(cylinders, { $0.exhaustValve }))
                calloutChip(label: "R.BRG",
                            shape: AnyShape(RodBearingIcon()),
                            health: worstAcross(cylinders, { $0.rodBearing }))
            }
        }
    }

    private var crankBar: some View {
        row(leftAlign: .trailing, rightAlign: .leading) {
            Text("CRANK")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(labelColor)
        } main: {
            barRect(color: healthColor(wide.crankshaft),
                    barHeight: crankBarHeight)
        } right: {
            Color.clear.frame(height: 1)
        }
    }

    /// Main-bearing journals: n+1 dots equally spaced across the
    /// same width as the cylinder bores above.
    private var mainBearingRow: some View {
        row(leftAlign: .trailing, rightAlign: .leading) {
            Text("MAIN BRG")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(labelColor)
        } main: {
            HStack(spacing: 0) {
                ForEach(0..<(cylinders.count + 1), id: \.self) { i in
                    Circle()
                        .fill(healthColor(wide.mainBearing))
                        .overlay(Circle().stroke(neutralStroke, lineWidth: 0.5))
                        .frame(width: mainBrgDot, height: mainBrgDot)
                    if i < cylinders.count {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: 12)
        } right: {
            Color.clear.frame(height: 1)
        }
    }

    private var pumpsRow: some View {
        row(leftAlign: .center, rightAlign: .center) {
            pumpCallout(label: "COOLANT",
                        shape: AnyShape(WaterPumpIcon()),
                        health: wide.waterPump,
                        on: coolantPumpOn)
        } main: {
            Color.clear.frame(height: 1)
        } right: {
            pumpCallout(label: "OIL",
                        shape: AnyShape(OilPumpIcon()),
                        health: wide.oilPump,
                        on: oilPumpOn)
        }
    }

    // MARK: Building blocks

    private func barRect(color: Color, barHeight: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(neutralStroke, lineWidth: 0.5)
            )
            .frame(height: barHeight)
    }

    /// `labelOnLeft` puts the text to the left of the icon (use this
    /// for callouts that live in the *right-hand* column — the label
    /// reads "outward" and the icon points toward the engine block).
    /// Default `labelOnLeft: false` puts the icon first, label after.
    private func calloutChip(label: String,
                             shape: AnyShape,
                             health: Double,
                             labelOnLeft: Bool = false) -> some View {
        let color = healthColor(health)
        return HStack(spacing: 4) {
            if labelOnLeft {
                Text(label)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                shape
                    .fill(color)
                    .frame(width: calloutIconSize, height: calloutIconSize)
            } else {
                shape
                    .fill(color)
                    .frame(width: calloutIconSize, height: calloutIconSize)
                Text(label)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(labelColor)
                    .lineLimit(1)
            }
        }
    }

    private func pumpCallout(label: String,
                             shape: AnyShape,
                             health: Double,
                             on: Bool) -> some View {
        VStack(spacing: 2) {
            shape
                .fill(healthColor(health))
                .frame(width: pumpIconSize, height: pumpIconSize)
                .opacity(on ? 1.0 : pumpOffOpacity)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundColor(labelColor)
                .lineLimit(1)
        }
    }
}

// MARK: - Cylinder bore

private struct CylinderBore: View {
    let cylinder: CylinderHealthState
    let cylinderNumber: Int

    var body: some View {
        GeometryReader { geo in
            let h = cylinder.seized ? 0.0 : cylinderWorstHealth(cylinder)
            let baseColor = cylinder.seized ? criticalColor : healthColor(h)
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(boreEmptyFill)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(
                        colors: [baseColor.opacity(0.65), baseColor.opacity(0.25)],
                        startPoint: .top, endPoint: .bottom
                    ))
                RoundedRectangle(cornerRadius: 3)
                    .stroke(cylinder.seized
                            ? criticalColor
                            : baseColor.opacity(0.7),
                            lineWidth: cylinder.seized ? 1.5 : 0.75)

                if cylinder.seized {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 0))
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    }
                    .stroke(criticalColor.opacity(0.85), lineWidth: 1.5)
                }

                VStack(spacing: 1) {
                    Text("C\(cylinderNumber)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                    Text("\(Int(cylinder.wallTempC.rounded()))°")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.65))
                }
            }
        }
    }
}
