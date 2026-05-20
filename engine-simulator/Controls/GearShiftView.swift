//
//  GearShiftView.swift
//  engine-simulator
//

import SwiftUI

// Spacing / sizing fractions used by the gate geometry. Tied to the rectangle
// it renders into so the shifter scales with the tile.
private let columnSpacingFraction: CGFloat = 0.2
private let columnSpacingMin: CGFloat = 30
private let travelFraction: CGFloat = 0.30
private let travelMin: CGFloat = 28
private let slotFraction: CGFloat = 0.085
private let slotMin: CGFloat = 11
private let slotMax: CGFloat = 18
private let knobFraction: CGFloat = 0.20
private let knobMin: CGFloat = 24
private let knobMax: CGFloat = 38
// Drag resolution: the knob snaps to the closest column/lane if released
// within this fraction of the column/lane travel; otherwise it returns to
// neutral. Picked so a half-pulled lever still commits to a gear.
private let resolveTargetRadiusFraction: CGFloat = 0.65
private let neutralBandFraction: CGFloat = 0.6
// Paddle layout.
private let paddleHeight: CGFloat = 44
private let paddleReadoutWidth: CGFloat = 36
// Bounds for spec-driven gear count; the builder already clamps to this range.
private let supportedGearMin: Int = 2
private let supportedGearMax: Int = 8

// MARK: - Top-level View

struct GearShiftView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        let count = clampedGearCount(vm.gearCount)
        VStack(spacing: 6) {
            GearHeader(gear: vm.gear)
            HPatternShifter(gear: vm.gear, gearCount: count, onShift: vm.setGear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ShifterPaddles(gear: vm.gear, gearCount: count, onShift: vm.setGear)
                .frame(height: paddleHeight)
        }
        .padding(8)
    }

    private func clampedGearCount(_ raw: Int) -> Int {
        min(max(raw, supportedGearMin), supportedGearMax)
    }
}

// MARK: - Header

private struct GearHeader: View {
    let gear: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("TRANSMISSION").modifier(RetroFont(size: 10)).foregroundColor(.gray)
            Spacer()
            Text(gear == -1 ? "N" : "\(gear + 1)")
                .modifier(RetroFont(size: 18))
                .foregroundColor(gear == -1 ? .green : .orange)
                .shadow(color: (gear == -1 ? Color.green : Color.orange).opacity(0.5), radius: 4)
        }
        .padding(.horizontal, 4)
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
                GateTrack(g: g)
                GearLabels(g: g, activeGear: gear)
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
                        // Drop livePos without an animation: knobPos falls back
                        // to g.gearPos(gear), which is exactly where we just
                        // committed. Animating between two identical points
                        // produces the snap-to-middle flicker we want to avoid.
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

    /// Number of columns in the gate: ceil(gearCount / 2).
    var columnCount: Int { (gearCount + 1) / 2 }

    init(size: CGSize, gearCount: Int) {
        self.gearCount = gearCount

        let centerX = size.width / 2
        let centerY = size.height / 2
        cx = centerX
        cy = centerY
        travel = max(size.height * travelFraction, travelMin)

        let ref = min(size.width, size.height)
        slotWidth = min(max(ref * slotFraction, slotMin), slotMax)
        knob = min(max(ref * knobFraction, knobMin), knobMax)

        let columns = (gearCount + 1) / 2
        let availableWidth = size.width - knob
        let evenSpacing = columns > 1 ? availableWidth / CGFloat(columns - 1) : 0
        let spacing = max(min(evenSpacing, size.width * columnSpacingFraction * 1.5),
                          columnSpacingMin)

        let totalSpan = spacing * CGFloat(columns - 1)
        let firstX = centerX - totalSpan / 2
        cols = (0..<columns).map { firstX + CGFloat($0) * spacing }
    }

    /// Returns the resting position of `gear` in the gate. For the last
    /// column when gearCount is odd, only the top slot is occupied.
    func gearPos(_ gear: Int) -> CGPoint {
        guard gear >= 0 && gear < gearCount else { return CGPoint(x: cx, y: cy) }
        let col = gear / 2
        let onTop = gear % 2 == 0
        return CGPoint(x: cols[col], y: onTop ? topY : botY)
    }

    /// Constrains the user's pointer to the gate's permitted travel: along
    /// columns that have a slot at that lane, or along the neutral cross-bar.
    func constrain(_ raw: CGPoint) -> CGPoint {
        let hw = slotWidth / 2
        let (nearColIdx, nearCol, colDist) = nearestColumn(to: raw.x)
        let onNeutral = abs(raw.y - cy) <= hw
        let onColumn = colDist <= hw
        let goingUp = raw.y < cy

        if onColumn && !onNeutral {
            // Last column has no bottom slot when gearCount is odd.
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

    /// Returns the gear index the pointer best matches at release. Anything
    /// near the neutral cross-bar resolves to -1 (N).
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

    /// True if the slot at `colIdx` on the top/bottom row exists.
    /// Odd gear counts leave the bottom of the final column empty.
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

private struct GateTrack: View {
    let g: Gate

    var body: some View {
        ZStack {
            GatePath(g: g)
                .stroke(Color(white: 0.18), style: StrokeStyle(lineWidth: g.slotWidth, lineCap: .round))
            GatePath(g: g)
                .stroke(Color(white: 0.08), style: StrokeStyle(lineWidth: g.slotWidth - 2, lineCap: .round))
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

private struct GearLabels: View {
    let g: Gate
    let activeGear: Int

    var body: some View {
        ForEach(0..<g.gearCount, id: \.self) { i in
            let pos = g.gearPos(i)
            let onTop = i % 2 == 0
            let offset = g.slotWidth / 2 + 9

            Text("\(i + 1)")
                .modifier(RetroFont(size: 9, weight: .bold))
                .foregroundColor(activeGear == i ? .orange : Color(white: 0.28))
                .position(x: pos.x, y: pos.y + (onTop ? -offset : offset))
        }
    }
}

// MARK: - Shifter Knob

private struct ShifterKnob: View {
    let size: CGFloat
    let dragging: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.35))
                .frame(width: size + 8, height: size * 0.45)
                .offset(y: size * 0.35)
                .blur(radius: 3)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.65), Color(white: 0.35), Color(white: 0.18)],
                        center: .init(x: 0.38, y: 0.32),
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle().stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(dragging ? 0.6 : 0.3), radius: dragging ? 5 : 3, y: dragging ? 3 : 2)
                .scaleEffect(dragging ? 1.08 : 1.0)
        }
    }
}

// MARK: - Paddle Shifters
//
// Aesthetic: dark flat fills (matches RetroPanel), single hairline border,
// no body gradient. Pressed state replaces the fill with a desaturated orange
// wash and lights up a notch indicator on the inner edge. Shape is a slim
// asymmetric blade with one beveled inner corner — reads as a paddle without
// leaning on glossy gradients.

private let paddleStrokeColor = Color.white.opacity(0.18)
private let paddlePressedStrokeColor = Color.orange.opacity(0.6)
private let paddleIdleFill = Color(white: 0.10)
private let paddlePressedFill = Color(red: 0.22, green: 0.10, blue: 0.0)
private let paddleAccentIdle = Color(white: 0.35)
private let paddleAccentActive = Color.orange
private let paddleBevelDepthFraction: CGFloat = 0.18
private let paddleCornerRadius: CGFloat = 3

private struct ShifterPaddles: View {
    let gear: Int
    let gearCount: Int
    let onShift: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Paddle(side: .left, enabled: gear > -1) {
                onShift(max(-1, gear - 1))
            }
            PaddleGearReadout(gear: gear)
                .frame(width: paddleReadoutWidth)
            Paddle(side: .right, enabled: gear < gearCount - 1) {
                onShift(min(gearCount - 1, gear + 1))
            }
        }
    }
}

private struct PaddleGearReadout: View {
    let gear: Int

    var body: some View {
        VStack(spacing: 1) {
            Text(gear == -1 ? "N" : "\(gear + 1)")
                .modifier(RetroFont(size: 14))
                .foregroundColor(gear == -1 ? .green : .orange)
            Text("GEAR").modifier(RetroFont(size: 7)).foregroundColor(Color(white: 0.3))
        }
    }
}

private struct Paddle: View {
    nonisolated enum Side: Equatable { case left, right }
    let side: Side
    let enabled: Bool
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: {
            pressed = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { pressed = false }
        }) {
            PaddleContent(side: side, pressed: pressed)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.35)
        .scaleEffect(x: 1.0, y: pressed ? 0.94 : 1.0, anchor: side == .left ? .trailing : .leading)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

private struct PaddleContent: View {
    let side: Paddle.Side
    let pressed: Bool

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height

            ZStack {
                PaddleShape(side: side)
                    .fill(pressed ? paddlePressedFill : paddleIdleFill)
                    .overlay(PaddleShape(side: side).stroke(
                        pressed ? paddlePressedStrokeColor : paddleStrokeColor,
                        lineWidth: 1
                    ))

                // Inner-edge accent line — runs along the inboard side of the
                // paddle and lights up on press. Replaces the old gradient.
                Rectangle()
                    .fill(pressed ? paddleAccentActive : paddleAccentIdle)
                    .frame(width: 1.5, height: h * 0.55)
                    .frame(maxWidth: .infinity, alignment: side == .left ? .trailing : .leading)
                    .padding(.horizontal, 6)
                    .opacity(pressed ? 1.0 : 0.5)

                VStack(spacing: 2) {
                    Image(systemName: side == .left ? "chevron.left" : "chevron.right")
                        .font(.system(size: 12, weight: .black))
                    Text(side == .left ? "DN" : "UP")
                        .modifier(RetroFont(size: 7))
                }
                .foregroundColor(pressed ? paddleAccentActive : Color(white: 0.55))
            }
        }
    }
}

private struct PaddleShape: Shape {
    let side: Paddle.Side

    func path(in r: CGRect) -> Path {
        let cr: CGFloat = paddleCornerRadius
        let bevel = r.height * paddleBevelDepthFraction
        var p = Path()

        if side == .left {
            // Inboard (right) edge tapers in at the top — reads like a blade.
            p.move(to: CGPoint(x: cr, y: 0))
            p.addLine(to: CGPoint(x: r.width - bevel - cr, y: 0))
            p.addQuadCurve(to: CGPoint(x: r.width - bevel, y: cr),
                           control: CGPoint(x: r.width - bevel, y: 0))
            p.addLine(to: CGPoint(x: r.width, y: r.height - cr))
            p.addQuadCurve(to: CGPoint(x: r.width - cr, y: r.height),
                           control: CGPoint(x: r.width, y: r.height))
            p.addLine(to: CGPoint(x: cr, y: r.height))
            p.addQuadCurve(to: CGPoint(x: 0, y: r.height - cr),
                           control: CGPoint(x: 0, y: r.height))
            p.addLine(to: CGPoint(x: 0, y: cr))
            p.addQuadCurve(to: CGPoint(x: cr, y: 0),
                           control: CGPoint(x: 0, y: 0))
        } else {
            // Inboard (left) edge tapers in at the top.
            p.move(to: CGPoint(x: bevel + cr, y: 0))
            p.addLine(to: CGPoint(x: r.width - cr, y: 0))
            p.addQuadCurve(to: CGPoint(x: r.width, y: cr),
                           control: CGPoint(x: r.width, y: 0))
            p.addLine(to: CGPoint(x: r.width, y: r.height - cr))
            p.addQuadCurve(to: CGPoint(x: r.width - cr, y: r.height),
                           control: CGPoint(x: r.width, y: r.height))
            p.addLine(to: CGPoint(x: cr, y: r.height))
            p.addQuadCurve(to: CGPoint(x: 0, y: r.height - cr),
                           control: CGPoint(x: 0, y: r.height))
            p.addLine(to: CGPoint(x: 0, y: bevel + cr))
            p.addQuadCurve(to: CGPoint(x: bevel, y: bevel),
                           control: CGPoint(x: 0, y: bevel))
            p.addLine(to: CGPoint(x: bevel + cr, y: 0))
        }
        p.closeSubpath()
        return p
    }
}
