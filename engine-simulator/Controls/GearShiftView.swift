//
//  GearShiftView.swift
//  engine-simulator
//

import SwiftUI

// MARK: - Sizing

// Aspect ratio scales with column count: a 2-gear gate is tall-and-narrow,
// an 8-gear gate is more like a wide square. Without this the same fixed
// ratio either squishes the 8-gear case sideways or stretches the 2-gear
// case vertically.
private let gateAspectMinPerColumn: CGFloat = 0.45
private let gateAspectExtraPerColumn: CGFloat = 0.22
private let gateAspectMin: CGFloat = 0.55
private let gateAspectMax: CGFloat = 1.55
// Hard cap on the gate's drawn size — a real shifter is a few inches wide,
// not the whole tile. Past this size we letterbox empty space instead of
// scaling up further.
private let gateMaxWidth: CGFloat = 320
private let gateMaxHeight: CGFloat = 320
private let gatePadFraction: CGFloat = 0.18
private let travelFraction: CGFloat = 0.34
private let columnSpacingMin: CGFloat = 24
private let columnSpacingMax: CGFloat = 60
private let slotFraction: CGFloat = 0.08
private let slotMin: CGFloat = 10
private let slotMax: CGFloat = 16
private let knobFraction: CGFloat = 0.24
private let knobMin: CGFloat = 28
private let knobMax: CGFloat = 44
private let resolveTargetRadiusFraction: CGFloat = 0.65
private let neutralBandFraction: CGFloat = 0.6
private let shiftButtonHeight: CGFloat = 36
private let shiftButtonSpacing: CGFloat = 8
private let supportedGearMin: Int = 2
private let supportedGearMax: Int = 8

// Palette.
private let plateOuterColor = Color(white: 0.15)
private let plateInnerColor = Color(white: 0.07)
private let plateBorderColor = Color.white.opacity(0.18)
private let slotShadowColor = Color.black.opacity(0.55)
private let neutralColor = Color.green
private let activeColor = Color.orange
private let knobFaceColor = Color(white: 0.16)
private let knobFaceBorder = Color.white.opacity(0.30)
private let knobActiveBorder = Color.orange
private let knobNotchColor = Color.white.opacity(0.5)
private let shiftBg = Color.white.opacity(0.05)
private let shiftBgPressed = Color.white.opacity(0.10)
private let shiftBorder = Color.white.opacity(0.20)
private let shiftBorderPressed = Color.orange
private let shiftText = Color(white: 0.65)
private let shiftTextPressed = Color.orange

// MARK: - Top-level View

struct GearShiftView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        let count = clampedGearCount(vm.gearCount)
        VStack(spacing: 10) {
            GearHeader(gear: vm.gear, gearCount: count)
            AspectLockedGate(
                gear: vm.gear,
                gearCount: count,
                onShift: vm.setGear
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ShiftRow(gear: vm.gear, gearCount: count, onShift: vm.setGear)
                .frame(height: shiftButtonHeight)
        }
        .padding(8)
    }

    private func clampedGearCount(_ raw: Int) -> Int {
        min(max(raw, supportedGearMin), supportedGearMax)
    }
}

// MARK: - Header (the sole gear readout)

private struct GearHeader: View {
    let gear: Int
    let gearCount: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("TRANSMISSION").modifier(RetroFont(size: 10)).foregroundColor(.gray)
            Spacer()
            Text("\(gearCount)-SPEED")
                .modifier(RetroFont(size: 9))
                .foregroundColor(Color(white: 0.42))
            Text(gear == -1 ? "N" : "\(gear + 1)")
                .modifier(RetroFont(size: 22, weight: .black))
                .foregroundColor(gear == -1 ? neutralColor : activeColor)
                .shadow(color: (gear == -1 ? neutralColor : activeColor).opacity(0.5), radius: 4)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Aspect-locked gate wrapper

/// Centers the H-pattern inside a fixed-aspect rect. Aspect ratio derives
/// from the column count so the same component reads correctly for a 2-gear
/// and an 8-gear gate. A max-size cap prevents the assembly from ballooning
/// when the parent tile is very tall.
private struct AspectLockedGate: View {
    let gear: Int
    let gearCount: Int
    let onShift: (Int) -> Void

    private var aspectRatio: CGFloat {
        let columns = CGFloat((gearCount + 1) / 2)
        let raw = gateAspectMinPerColumn + gateAspectExtraPerColumn * columns
        return min(max(raw, gateAspectMin), gateAspectMax)
    }

    var body: some View {
        GeometryReader { geo in
            let (w, h) = fittedSize(in: geo.size)
            HPatternShifter(gear: gear, gearCount: gearCount, onShift: onShift)
                .frame(width: w, height: h)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Pick the largest rect that fits inside `available`, respects the
    /// computed aspect ratio, and never exceeds the hard size cap.
    private func fittedSize(in available: CGSize) -> (CGFloat, CGFloat) {
        let cappedWidth = min(available.width, gateMaxWidth)
        let cappedHeight = min(available.height, gateMaxHeight)
        let widthDrivenHeight = cappedWidth / aspectRatio
        if widthDrivenHeight <= cappedHeight {
            return (cappedWidth, widthDrivenHeight)
        }
        return (cappedHeight * aspectRatio, cappedHeight)
    }
}

// MARK: - H-Pattern Shifter

private struct HPatternShifter: View {
    let gear: Int
    let gearCount: Int
    let onShift: (Int) -> Void
    @State private var livePos: CGPoint? = nil
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let g = Gate(size: geo.size, gearCount: gearCount)
            let knobPos = livePos ?? g.gearPos(gear)

            ZStack {
                GatePlate(g: g)
                GateTrack(g: g)
                SlotEndCaps(g: g)
                ShifterKnob(size: g.knob, dragging: isDragging)
                    .position(knobPos)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        isDragging = true
                        livePos = g.constrain(v.location)
                    }
                    .onEnded { v in
                        isDragging = false
                        let resolved = g.resolveGear(at: g.constrain(v.location))
                        onShift(resolved)
                        livePos = nil
                    }
            )
        }
    }
}

// MARK: - Gate Geometry

private struct Gate {
    let cx, cy: CGFloat
    let travel: CGFloat
    let slotWidth: CGFloat
    let knob: CGFloat
    let cols: [CGFloat]
    let gearCount: Int

    var topY: CGFloat { cy - travel }
    var botY: CGFloat { cy + travel }
    var columnCount: Int { (gearCount + 1) / 2 }

    init(size: CGSize, gearCount: Int) {
        self.gearCount = gearCount
        let centerX = size.width / 2
        let centerY = size.height / 2
        cx = centerX
        cy = centerY
        travel = size.height * travelFraction

        let ref = min(size.width, size.height)
        slotWidth = min(max(ref * slotFraction, slotMin), slotMax)
        knob = min(max(ref * knobFraction, knobMin), knobMax)

        let columns = (gearCount + 1) / 2
        let pad = knob * 0.8
        let usableWidth = max(size.width - pad * 2, columnSpacingMin)
        let spacing: CGFloat = columns > 1
            ? min(max(usableWidth / CGFloat(columns - 1), columnSpacingMin), columnSpacingMax)
            : 0

        let totalSpan = spacing * CGFloat(columns - 1)
        let firstX = centerX - totalSpan / 2
        cols = (0..<columns).map { firstX + CGFloat($0) * spacing }
    }

    func gearPos(_ gear: Int) -> CGPoint {
        guard gear >= 0 && gear < gearCount else { return CGPoint(x: cx, y: cy) }
        let col = gear / 2
        let onTop = gear % 2 == 0
        return CGPoint(x: cols[col], y: onTop ? topY : botY)
    }

    func constrain(_ raw: CGPoint) -> CGPoint {
        let hw = slotWidth / 2
        let (nearColIdx, nearCol, colDist) = nearestColumn(to: raw.x)
        let onNeutral = abs(raw.y - cy) <= hw
        let onColumn = colDist <= hw
        let goingUp = raw.y < cy

        if onColumn && !onNeutral {
            if columnHasSlot(at: nearColIdx, onTop: goingUp) {
                return CGPoint(x: nearCol, y: clampY(raw.y))
            }
            return CGPoint(x: nearCol, y: cy)
        }
        if onNeutral || abs(raw.y - cy) < colDist {
            return CGPoint(x: clampX(raw.x), y: cy)
        }
        if columnHasSlot(at: nearColIdx, onTop: goingUp) {
            return CGPoint(x: nearCol, y: clampY(raw.y))
        }
        return CGPoint(x: nearCol, y: cy)
    }

    func resolveGear(at pos: CGPoint) -> Int {
        if abs(pos.y - cy) < slotWidth * neutralBandFraction { return -1 }

        var best = -1
        var bestDist: CGFloat = .infinity
        for i in 0..<gearCount {
            let t = gearPos(i)
            let d = hypot(pos.x - t.x, pos.y - t.y)
            if d < bestDist { bestDist = d; best = i }
        }
        return bestDist <= travel * resolveTargetRadiusFraction ? best : -1
    }

    func columnHasSlot(at colIdx: Int, onTop: Bool) -> Bool {
        let isOddLastColumn = (gearCount % 2 == 1) && (colIdx == columnCount - 1)
        return onTop || !isOddLastColumn
    }

    private func nearestColumn(to x: CGFloat) -> (Int, CGFloat, CGFloat) {
        var bestIdx = 0
        var bestDist = CGFloat.infinity
        for (i, c) in cols.enumerated() {
            let d = abs(x - c)
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        return (bestIdx, cols[bestIdx], bestDist)
    }

    private func clampX(_ x: CGFloat) -> CGFloat {
        min(max(x, cols.first!), cols.last!)
    }

    private func clampY(_ y: CGFloat) -> CGFloat {
        min(max(y, topY), botY)
    }
}

// MARK: - Gate Visuals

/// Outer plate that holds the slots — the shifter "boot" sits on this.
/// Drawn as a rounded rectangle with a hairline border so the gate reads as
/// a recessed dash insert.
private struct GatePlate: View {
    let g: Gate

    var body: some View {
        let pad: CGFloat = max(g.knob * 0.55, gatePadFraction * g.slotWidth * 8)
        let plateWidth = (g.cols.last! - g.cols.first!) + pad * 2
        let plateHeight = (g.botY - g.topY) + pad * 2

        RoundedRectangle(cornerRadius: 8)
            .fill(plateOuterColor)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(plateBorderColor, lineWidth: 1))
            .frame(width: plateWidth, height: plateHeight)
            .position(x: g.cx, y: g.cy)
    }
}

/// Slots themselves — drawn as a single rounded path so the joins between
/// the H's crossbar and verticals are clean.
private struct GateTrack: View {
    let g: Gate

    var body: some View {
        ZStack {
            GatePath(g: g)
                .stroke(plateInnerColor, style: StrokeStyle(lineWidth: g.slotWidth, lineCap: .round))
            GatePath(g: g)
                .stroke(slotShadowColor, style: StrokeStyle(lineWidth: g.slotWidth - 3, lineCap: .round))
        }
    }
}

private struct GatePath: Shape {
    let g: Gate

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: g.cols.first!, y: g.cy))
        p.addLine(to: CGPoint(x: g.cols.last!, y: g.cy))
        for (idx, col) in g.cols.enumerated() {
            let topReachable = g.columnHasSlot(at: idx, onTop: true)
            let botReachable = g.columnHasSlot(at: idx, onTop: false)
            if topReachable {
                p.move(to: CGPoint(x: col, y: g.cy))
                p.addLine(to: CGPoint(x: col, y: g.topY))
            }
            if botReachable {
                p.move(to: CGPoint(x: col, y: g.cy))
                p.addLine(to: CGPoint(x: col, y: g.botY))
            }
        }
        return p
    }
}

/// Subtle detent markers at the terminations of each slot — gives the gate
/// some texture without printing "1 2 3 4 5 6" next to the rails, which is
/// not how a real gate plate looks.
private struct SlotEndCaps: View {
    let g: Gate

    var body: some View {
        Canvas { ctx, _ in
            let dotRadius: CGFloat = max(g.slotWidth * 0.15, 1.0)
            for (idx, col) in g.cols.enumerated() {
                if g.columnHasSlot(at: idx, onTop: true) {
                    addDot(ctx: ctx, x: col, y: g.topY, radius: dotRadius)
                }
                if g.columnHasSlot(at: idx, onTop: false) {
                    addDot(ctx: ctx, x: col, y: g.botY, radius: dotRadius)
                }
            }
        }
    }

    private func addDot(ctx: GraphicsContext, x: CGFloat, y: CGFloat, radius: CGFloat) {
        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.25)))
    }
}

// MARK: - Shifter Knob

/// Clean dark disc with a small notch suggesting where the lever points.
/// No text on the face — the gear readout lives in the header where it
/// belongs. Border lights up when the user is dragging.
private struct ShifterKnob: View {
    let size: CGFloat
    let dragging: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.45))
                .frame(width: size + 4, height: size + 4)
                .blur(radius: 2)

            Circle()
                .fill(knobFaceColor)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(dragging ? knobActiveBorder : knobFaceBorder,
                                lineWidth: dragging ? 1.6 : 1)
                )
                .overlay(
                    Circle()
                        .fill(knobNotchColor)
                        .frame(width: size * 0.16, height: size * 0.16)
                        .offset(y: -size * 0.25)
                )
        }
        .scaleEffect(dragging ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.12), value: dragging)
    }
}

// MARK: - Shift Row (UP / DOWN dashboard buttons)

private struct ShiftRow: View {
    let gear: Int
    let gearCount: Int
    let onShift: (Int) -> Void

    var body: some View {
        HStack(spacing: shiftButtonSpacing) {
            ShiftButton(
                direction: .down,
                enabled: gear > -1,
                action: { onShift(max(-1, gear - 1)) }
            )
            ShiftButton(
                direction: .up,
                enabled: gear < gearCount - 1,
                action: { onShift(min(gearCount - 1, gear + 1)) }
            )
        }
    }
}

private struct ShiftButton: View {
    enum Direction { case up, down }
    let direction: Direction
    let enabled: Bool
    let action: () -> Void
    @State private var pressed = false

    private var chevron: String { direction == .up ? "chevron.right" : "chevron.left" }
    private var label: String { direction == .up ? "UPSHIFT" : "DOWNSHIFT" }

    var body: some View {
        Button(action: {
            pressed = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { pressed = false }
        }) {
            HStack(spacing: 6) {
                if direction == .down {
                    Image(systemName: chevron).font(.system(size: 12, weight: .black))
                    Text(label).modifier(RetroFont(size: 9))
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    Text(label).modifier(RetroFont(size: 9))
                    Image(systemName: chevron).font(.system(size: 12, weight: .black))
                }
            }
            .padding(.horizontal, 12)
            .foregroundColor(pressed ? shiftTextPressed : shiftText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(pressed ? shiftBgPressed : shiftBg)
            .overlay(Rectangle().stroke(
                pressed ? shiftBorderPressed : shiftBorder,
                lineWidth: 1
            ))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.35)
        .animation(.easeOut(duration: 0.1), value: pressed)
    }
}
