//
//  GearShiftView.swift
//  engine-simulator
//

import SwiftUI

// MARK: - Top-level View

struct GearShiftView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 6) {
                GearHeader(gear: vm.gear)
                HPatternShifter(gear: vm.gear, onShift: vm.setGear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ShifterPaddles(gear: vm.gear, onShift: vm.setGear)
                    .frame(height: 44)
            }
            .padding(8)
        }
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
    let onShift: (Int) -> Void
    @State private var livePos: CGPoint? = nil
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let g = Gate(size: geo.size)
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
                        let pos = g.constrain(v.location)
                        let resolved = g.resolveGear(at: pos)
                        onShift(resolved)
                        withAnimation(.interpolatingSpring(stiffness: 500, damping: 25)) {
                            livePos = nil
                        }
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

    var topY: CGFloat { cy - travel }
    var botY: CGFloat { cy + travel }

    init(size: CGSize) {
        let _cx = size.width / 2
        let _cy = size.height / 2
        let spacing = max(size.width * 0.2, 32)
        cx = _cx
        cy = _cy
        travel = max(size.height * 0.32, 28)
        let ref = min(size.width, size.height)
        slotWidth = max(ref * 0.1, 12)
        knob = max(ref * 0.22, 26)
        cols = [-1, 0, 1].map { _cx + CGFloat($0) * spacing }
    }

    func gearPos(_ gear: Int) -> CGPoint {
        guard gear >= 0 else { return CGPoint(x: cx, y: cy) }
        return CGPoint(x: cols[gear / 2], y: gear % 2 == 0 ? topY : botY)
    }

    func constrain(_ raw: CGPoint) -> CGPoint {
        let hw = slotWidth / 2
        let (nearCol, colDist) = nearestColumn(to: raw.x)
        let onNeutral = abs(raw.y - cy) <= hw
        let onColumn = colDist <= hw

        if onColumn && !onNeutral {
            return CGPoint(x: nearCol, y: min(max(raw.y, topY), botY))
        }
        if onNeutral {
            return CGPoint(x: clampX(raw.x), y: cy)
        }
        if abs(raw.y - cy) < colDist {
            return CGPoint(x: clampX(raw.x), y: cy)
        }
        return CGPoint(x: nearCol, y: min(max(raw.y, topY), botY))
    }

    func resolveGear(at pos: CGPoint) -> Int {
        let nearCenter = abs(pos.y - cy) < slotWidth * 0.6
        if nearCenter { return -1 }

        var best = -1
        var bestD: CGFloat = .infinity
        for i in 0..<6 {
            let t = gearPos(i)
            let d = hypot(pos.x - t.x, pos.y - t.y)
            if d < bestD { bestD = d; best = i }
        }
        return bestD <= travel * 0.65 ? best : -1
    }

    private func nearestColumn(to x: CGFloat) -> (CGFloat, CGFloat) {
        var nearCol = cols[0]
        var nearDist = CGFloat.infinity
        for c in cols {
            let d = abs(x - c)
            if d < nearDist { nearDist = d; nearCol = c }
        }
        return (nearCol, nearDist)
    }

    private func clampX(_ x: CGFloat) -> CGFloat {
        min(max(x, cols.first!), cols.last!)
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
        for col in g.cols {
            p.move(to: CGPoint(x: col, y: g.topY))
            p.addLine(to: CGPoint(x: col, y: g.botY))
        }
        return p
    }
}

private struct GearLabels: View {
    let g: Gate
    let activeGear: Int

    var body: some View {
        ForEach(0..<6, id: \.self) { i in
            let pos = g.gearPos(i)
            let above = i % 2 == 0
            let offset = g.slotWidth / 2 + 9

            Text("\(i + 1)")
                .modifier(RetroFont(size: 9, weight: .bold))
                .foregroundColor(activeGear == i ? .orange : Color(white: 0.28))
                .position(x: pos.x, y: pos.y + (above ? -offset : offset))
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

private struct ShifterPaddles: View {
    let gear: Int
    let onShift: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Paddle(side: .left) { onShift(max(-1, gear - 1)) }
            PaddleGearReadout(gear: gear)
                .frame(width: 36)
            Paddle(side: .right) { onShift(min(5, gear + 1)) }
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
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: {
            pressed = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { pressed = false }
        }) {
            GeometryReader { geo in
                PaddleContent(side: side, pressed: pressed, height: geo.size.height)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .scaleEffect(x: 1.0, y: pressed ? 0.94 : 1.0, anchor: side == .left ? .trailing : .leading)
            .animation(.easeOut(duration: 0.08), value: pressed)
        }
        .buttonStyle(.plain)
    }
}

private struct PaddleContent: View {
    let side: Paddle.Side
    let pressed: Bool
    let height: CGFloat

    var body: some View {
        ZStack {
            PaddleShape(side: side)
                .fill(paddleFill)
                .overlay(PaddleShape(side: side).stroke(paddleStroke, lineWidth: 1))
                .shadow(
                    color: pressed ? Color.orange.opacity(0.3) : .black.opacity(0.5),
                    radius: pressed ? 4 : 2,
                    x: side == .left ? 2 : -2,
                    y: 0
                )

            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color.orange.opacity(pressed ? 0.2 : 0.06))
                        .frame(width: 1, height: height * 0.4)
                }
            }

            VStack(spacing: 2) {
                Image(systemName: side == .left ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12, weight: .black))
                Text(side == .left ? "DN" : "UP")
                    .modifier(RetroFont(size: 7))
            }
            .foregroundColor(pressed ? .orange : Color(white: 0.45))
        }
    }

    private var paddleFill: LinearGradient {
        LinearGradient(
            colors: pressed
                ? [Color(red: 0.35, green: 0.18, blue: 0.0), Color(red: 0.2, green: 0.08, blue: 0.0)]
                : [Color(white: 0.16), Color(white: 0.07)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var paddleStroke: LinearGradient {
        LinearGradient(
            colors: [
                pressed ? Color.orange.opacity(0.5) : Color.white.opacity(0.1),
                Color.white.opacity(0.02)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

private struct PaddleShape: Shape {
    let side: Paddle.Side

    func path(in r: CGRect) -> Path {
        let cr: CGFloat = 4
        let taper = r.height * 0.12

        var p = Path()
        if side == .left {
            p.move(to: CGPoint(x: cr, y: taper))
            p.addLine(to: CGPoint(x: r.width - cr, y: 0))
            p.addQuadCurve(to: CGPoint(x: r.width, y: cr), control: CGPoint(x: r.width, y: 0))
            p.addLine(to: CGPoint(x: r.width, y: r.height - cr))
            p.addQuadCurve(to: CGPoint(x: r.width - cr, y: r.height), control: CGPoint(x: r.width, y: r.height))
            p.addLine(to: CGPoint(x: cr, y: r.height - taper))
            p.addQuadCurve(to: CGPoint(x: 0, y: r.height - taper - cr), control: CGPoint(x: 0, y: r.height - taper))
            p.addLine(to: CGPoint(x: 0, y: taper + cr))
            p.addQuadCurve(to: CGPoint(x: cr, y: taper), control: CGPoint(x: 0, y: taper))
        } else {
            p.move(to: CGPoint(x: cr, y: 0))
            p.addQuadCurve(to: CGPoint(x: 0, y: cr), control: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: r.height - cr))
            p.addQuadCurve(to: CGPoint(x: cr, y: r.height), control: CGPoint(x: 0, y: r.height))
            p.addLine(to: CGPoint(x: r.width - cr, y: r.height - taper))
            p.addQuadCurve(to: CGPoint(x: r.width, y: r.height - taper - cr), control: CGPoint(x: r.width, y: r.height - taper))
            p.addLine(to: CGPoint(x: r.width, y: taper + cr))
            p.addQuadCurve(to: CGPoint(x: r.width - cr, y: taper), control: CGPoint(x: r.width, y: taper))
            p.closeSubpath()
        }
        return p
    }
}
