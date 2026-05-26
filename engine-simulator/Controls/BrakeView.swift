//
//  BrakeView.swift
//  engine-simulator
//
//  Live brake control surface: a cross-drilled rotor that spins with road
//  speed and a floating caliper whose pads squeeze the disc as brake pressure
//  rises (glowing hot under hard braking), paired with the precision brake
//  slider. Drawn from SwiftUI primitives to match the clutch/intake
//  cross-sections in ThrottleView.
//

import SwiftUI

// MARK: - Layout constants

private let rotorAspectRatio: CGFloat = 1.0
private let rotorPadding: CGFloat = 6

// Disc geometry (fractions of the square drawing rect).
private let discOuterFraction: CGFloat = 0.86
private let discInnerFraction: CGFloat = 0.30   // hub
private let discRimFraction: CGFloat = 0.70     // where the swept friction face begins
private let drillHoleCount: Int = 10
private let drillHoleRadiusFraction: CGFloat = 0.035
private let drillRingFraction: CGFloat = 0.55    // radius the drill-hole ring sits on
private let ventSlotCount: Int = 28
private let hubBoltCount: Int = 5
private let hubBoltRadiusFraction: CGFloat = 0.018
private let hubBoltRingFraction: CGFloat = 0.20

// Caliper geometry. Real calipers are wider than tall — a low bracket clamping
// the rim, not a tall block.
private let caliperWidthFraction: CGFloat = 0.34
private let caliperHeightFraction: CGFloat = 0.18
// Single near-side pad. At rest it sits proud toward the camera; under braking
// it recedes "into" the rotor (shrinks + tilts away + loses its shadow).
private let padWidthFraction: CGFloat = 0.22
private let padHeightFraction: CGFloat = 0.09
private let padInsetFraction: CGFloat = 0.22     // how far below the rim the pad sits
private let padReceineScale: CGFloat = 0.24      // how much it shrinks when fully pressed
private let padReceineTiltDeg: Double = 24       // perspective tilt when fully pressed

// Spin behavior. Scaled well below true wheel speed so the rotation reads as a
// legible spin instead of a strobe, then clamped so it never flickers.
private let degPerSecondPerMph: Double = 12.0
private let minSpeedForMotionMph: Double = 0.4
private let maxSpinDegPerSecond: Double = 900.0

// Colors — rotor metal grays kept local (mirrors the metal palette ThrottleView
// defines for its own cross-sections); accents reuse the shared dash palette.
private let rotorFaceColor = Color(white: 0.38)
private let rotorFaceDarkColor = Color(white: 0.22)
private let rotorRimColor = Color(white: 0.52)
private let rotorOutlineColor = Color.white.opacity(0.22)
private let hubColor = Color(white: 0.30)
private let ventColor = Color.black.opacity(0.40)
private let caliperBodyColor = Color(white: 0.26)
private let caliperBoltColor = Color(white: 0.5)

struct BrakeView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        VStack(spacing: 6) {
            BrakeRotorVisualizer(
                speedMph: vm.vehicleSpeed,
                brakePressure: vm.brakePressure,
                now: vm.frameDate.timeIntervalSinceReferenceDate
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if os(macOS)
            PrecisionBrakeSlider(value: vm.brakeInput)
            #endif
        }
        .padding(8)
    }
}

/// iOS Track tile: the brake rotor beside the intake cross-section. Replaces the
/// clutch/intake pairing on the track screen where braking matters more than the
/// (top-bar toggled) clutch.
struct BrakeIntakeView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        HStack(spacing: 0) {
            BrakeView(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            IntakePanelView(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Rotor + caliper drawing

private struct BrakeRotorVisualizer: View {
    let speedMph: Double
    let brakePressure: Double
    let now: TimeInterval

    private var spinAngle: Double {
        let active = max(speedMph - minSpeedForMotionMph, 0)
        let degPerSec = min(active * degPerSecondPerMph, maxSpinDegPerSecond)
        return (now * degPerSec).truncatingRemainder(dividingBy: 360)
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) - rotorPadding * 2
            let rect = CGRect(
                x: (geo.size.width - side) / 2,
                y: (geo.size.height - side) / 2,
                width: side, height: side
            )

            // The caliper protrudes above the disc, so centering the disc alone
            // would leave the whole assembly looking top-heavy / shifted up next
            // to the other (symmetric) diagrams. Nudge the group down by half the
            // caliper's overhang so the disc+caliper bounding box is centered.
            let caliperOverhang = side * caliperHeightFraction * 0.5
            let groupY = rect.midY + caliperOverhang * 0.5

            ZStack {
                RotorDisc(angle: spinAngle, brakePressure: brakePressure)
                    .frame(width: side, height: side)
                    .position(x: rect.midX, y: groupY)

                Caliper(brakePressure: brakePressure)
                    .frame(width: side, height: side)
                    .position(x: rect.midX, y: groupY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The cross-drilled, vented disc. The face + holes rotate as one layer; the
/// outer rim picks up a hot glow that intensifies with brake pressure.
private struct RotorDisc: View {
    let angle: Double
    let brakePressure: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let center = CGPoint(x: w / 2, y: w / 2)
            let outerR = w * discOuterFraction / 2

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [rotorFaceColor, rotorFaceDarkColor],
                        center: .center, startRadius: 0, endRadius: outerR))
                    .frame(width: outerR * 2, height: outerR * 2)
                    .position(center)
                    .overlay(
                        Circle()
                            .stroke(rotorOutlineColor, lineWidth: 1)
                            .frame(width: outerR * 2, height: outerR * 2)
                            .position(center)
                    )

                RotorMarks(brakePressure: brakePressure)
                    .frame(width: w, height: w)
                    .rotationEffect(.degrees(angle), anchor: .center)

                // Hot rim glow under braking — a friction-orange ring whose
                // intensity tracks pressure.
                Circle()
                    .stroke(Color.accentHeat.opacity(brakePressure * 0.9),
                            lineWidth: max(2, w * 0.03))
                    .frame(width: outerR * 2, height: outerR * 2)
                    .position(center)
                    .blur(radius: 2)
            }
        }
    }
}

/// Rotating detail: the swept-face ring, cross-drilled holes, cooling-vane
/// slots and the hub with its bolt circle. Separated so only this layer spins.
private struct RotorMarks: View {
    let brakePressure: Double

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let center = CGPoint(x: w / 2, y: w / 2)
            let outerR = w * discOuterFraction / 2
            let rimR = w * discRimFraction / 2
            let hubR = w * discInnerFraction / 2

            // Cooling vane slots in the friction band.
            for i in 0..<ventSlotCount {
                let a = Double(i) / Double(ventSlotCount) * 2 * .pi
                let p1 = point(center, rimR, a)
                let p2 = point(center, outerR * 0.97, a)
                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                ctx.stroke(path, with: .color(ventColor), lineWidth: 1)
            }

            // Cross-drilled holes around the disc.
            let drillR = w * drillRingFraction / 2
            let holeR = w * drillHoleRadiusFraction
            for i in 0..<drillHoleCount {
                let a = Double(i) / Double(drillHoleCount) * 2 * .pi
                let c = point(center, drillR, a)
                let dot = Path(ellipseIn: CGRect(x: c.x - holeR, y: c.y - holeR,
                                                 width: holeR * 2, height: holeR * 2))
                ctx.fill(dot, with: .color(.black.opacity(0.55)))
                ctx.stroke(dot, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
            }

            // Hub face + bolt circle.
            let hub = Path(ellipseIn: CGRect(x: center.x - hubR, y: center.y - hubR,
                                             width: hubR * 2, height: hubR * 2))
            ctx.fill(hub, with: .color(hubColor))
            ctx.stroke(hub, with: .color(.white.opacity(0.2)), lineWidth: 1)

            let boltRingR = w * hubBoltRingFraction / 2
            let boltR = w * hubBoltRadiusFraction
            for i in 0..<hubBoltCount {
                let a = Double(i) / Double(hubBoltCount) * 2 * .pi - .pi / 2
                let c = point(center, boltRingR, a)
                let bolt = Path(ellipseIn: CGRect(x: c.x - boltR, y: c.y - boltR,
                                                  width: boltR * 2, height: boltR * 2))
                ctx.fill(bolt, with: .color(caliperBoltColor))
            }
        }
    }

    private func point(_ c: CGPoint, _ r: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: c.x + r * CGFloat(cos(angle)), y: c.y + r * CGFloat(sin(angle)))
    }
}

/// Fixed caliper straddling the disc rim at the top, with the single near-side
/// pad visible on the disc face. We only ever see the front pad (the back one is
/// hidden behind the rotor), so as the brake bites the visible pad recedes "into"
/// the rotor — it shrinks, tilts away from the camera and loses its proud shadow
/// — and glows with friction heat.
private struct Caliper: View {
    let brakePressure: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let outerR = w * discOuterFraction / 2
            let bodyW = w * caliperWidthFraction
            let bodyH = w * caliperHeightFraction
            let rimY = w / 2 - outerR
            let glow = Color.accentHeat.opacity(brakePressure)

            ZStack {
                // Caliper body bridging the rim (fixed).
                RoundedRectangle(cornerRadius: 4)
                    .fill(caliperBodyColor)
                    .frame(width: bodyW, height: bodyH)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(glow, lineWidth: 1.5).blur(radius: 1.5))
                    .position(x: w / 2, y: rimY)

                CaliperPad(brakePressure: brakePressure,
                           width: w * padWidthFraction,
                           height: w * padHeightFraction)
                    .position(x: w / 2, y: rimY + outerR * padInsetFraction)
            }
        }
    }
}

/// The one visible friction pad. At rest it sits proud toward the camera (full
/// size, dropped shadow). As pressure rises it scales down and tilts back about
/// its top edge, reading as the pad pressing away from us into the rotor.
private struct CaliperPad: View {
    let brakePressure: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let press = CGFloat(brakePressure)
        let scale = 1.0 - padReceineScale * press
        let glow = Color.accentHeat.opacity(brakePressure)
        let face = Color.accentDanger.opacity(0.45 + 0.45 * Double(press))

        RoundedRectangle(cornerRadius: 2)
            .fill(face)
            .frame(width: width, height: height)
            .overlay(RoundedRectangle(cornerRadius: 2)
                .stroke(glow, lineWidth: 1.2).blur(radius: 1))
            .scaleEffect(scale)
            .rotation3DEffect(.degrees(Double(press) * padReceineTiltDeg),
                              axis: (x: 1, y: 0, z: 0),
                              anchor: .top, perspective: 0.6)
            .shadow(color: .black.opacity(0.5 * Double(1 - press)),
                    radius: 4 * (1 - press), x: 0, y: 3 * (1 - press))
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: brakePressure)
    }
}
