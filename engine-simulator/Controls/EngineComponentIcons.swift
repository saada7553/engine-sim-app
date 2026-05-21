//
//  EngineComponentIcons.swift
//  engine-simulator
//
//  Hand-drawn icon silhouettes for the engine components that appear on
//  the Engine Health tile's schematic. Each icon is a Shape so the call
//  site picks a colour (e.g. tinted by that component's worst-case
//  health). Style matches GaugeIcons.swift / WarningLightIcons.swift:
//  stroke-based silhouettes, easily readable at ~16-22pt.
//

import SwiftUI

// MARK: - Per-cylinder components

/// Head gasket: a flat horizontal layered shape with notches that read
/// as bolt holes / coolant passages.
struct HeadGasketIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        // Two thin slabs stacked, with two cut-outs along the centre line.
        let outerRect = CGRect(x: w * 0.08, y: h * 0.36,
                               width: w * 0.84, height: h * 0.28)
        p.addRoundedRect(in: outerRect,
                         cornerSize: CGSize(width: h * 0.04, height: h * 0.04))

        // Two bolt-hole circles + a center coolant passage rectangle.
        let holeR = h * 0.05
        let centerY = outerRect.midY
        p.addEllipse(in: CGRect(x: w * 0.22 - holeR, y: centerY - holeR,
                                width: holeR * 2, height: holeR * 2))
        p.addEllipse(in: CGRect(x: w * 0.78 - holeR, y: centerY - holeR,
                                width: holeR * 2, height: holeR * 2))
        let passageW = w * 0.18
        p.addRect(CGRect(x: w / 2 - passageW / 2, y: centerY - holeR * 0.6,
                         width: passageW, height: holeR * 1.2))

        return p
    }
}

/// Piston rings: three concentric ovals (compression rings stacked).
struct PistonRingsIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cx = w / 2

        let ringWidth = w * 0.66
        let ringHeight = h * 0.08
        let spacing = h * 0.18
        let topY = h * 0.30

        for i in 0..<3 {
            let y = topY + spacing * CGFloat(i)
            p.addRoundedRect(in: CGRect(x: cx - ringWidth / 2, y: y,
                                        width: ringWidth, height: ringHeight),
                             cornerSize: CGSize(width: ringHeight / 2,
                                                height: ringHeight / 2))
        }

        return p
    }
}

/// Piston: tall cylindrical body with a wrist-pin hole and a notch on
/// top where the rings would seat.
struct PistonIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cx = w / 2

        let bodyTop = h * 0.20
        let bodyBottom = h * 0.86
        let bodyHalfWidth = w * 0.26

        // Main body.
        p.addRoundedRect(in: CGRect(x: cx - bodyHalfWidth, y: bodyTop,
                                    width: bodyHalfWidth * 2, height: bodyBottom - bodyTop),
                         cornerSize: CGSize(width: w * 0.04, height: w * 0.04))

        // Three thin ring grooves near the top.
        for i in 0..<3 {
            let y = bodyTop + h * 0.06 + h * 0.06 * CGFloat(i)
            p.addRect(CGRect(x: cx - bodyHalfWidth + 1, y: y,
                             width: bodyHalfWidth * 2 - 2, height: 1))
        }

        // Wrist-pin hole (small circle near vertical centre).
        let pinR = w * 0.07
        p.addEllipse(in: CGRect(x: cx - pinR, y: h * 0.58 - pinR,
                                width: pinR * 2, height: pinR * 2))

        return p
    }
}

/// Connecting rod: dogbone-shape with a big end (crank journal) at the
/// bottom and a small end (wrist pin) at the top.
struct ConnectingRodIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cx = w / 2

        // Small end (top): smaller circle.
        let smallR = w * 0.13
        let smallCY = h * 0.18
        p.addEllipse(in: CGRect(x: cx - smallR, y: smallCY - smallR,
                                width: smallR * 2, height: smallR * 2))

        // Big end (bottom): larger circle.
        let bigR = w * 0.22
        let bigCY = h * 0.78
        p.addEllipse(in: CGRect(x: cx - bigR, y: bigCY - bigR,
                                width: bigR * 2, height: bigR * 2))

        // Shaft connecting them (two parallel lines forming the rod beam).
        let beamHalfWidth = w * 0.06
        let beamTop = smallCY + smallR * 0.30
        let beamBottom = bigCY - bigR * 0.30
        p.addRect(CGRect(x: cx - beamHalfWidth, y: beamTop,
                         width: beamHalfWidth * 2, height: beamBottom - beamTop))

        // Inner bores (the rod actually has eyes, draw them lighter).
        p.addEllipse(in: CGRect(x: cx - smallR * 0.55, y: smallCY - smallR * 0.55,
                                width: smallR * 1.1, height: smallR * 1.1))
        p.addEllipse(in: CGRect(x: cx - bigR * 0.55, y: bigCY - bigR * 0.55,
                                width: bigR * 1.1, height: bigR * 1.1))

        return p
    }
}

/// Rod bearing: two crescent-shaped bearing shells facing each other.
struct RodBearingIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cx = w / 2
        let cy = h / 2

        let outerR = min(w, h) * 0.38
        let innerR = outerR * 0.72
        let gap = h * 0.05

        // Upper shell: arc spanning roughly 180° plus a flat closing edge.
        p.move(to: CGPoint(x: cx - outerR, y: cy - gap / 2))
        p.addArc(center: CGPoint(x: cx, y: cy - gap / 2), radius: outerR,
                 startAngle: .degrees(180), endAngle: .degrees(360),
                 clockwise: false)
        p.addLine(to: CGPoint(x: cx + innerR, y: cy - gap / 2))
        p.addArc(center: CGPoint(x: cx, y: cy - gap / 2), radius: innerR,
                 startAngle: .degrees(360), endAngle: .degrees(180),
                 clockwise: true)
        p.closeSubpath()

        // Lower shell: mirror.
        p.move(to: CGPoint(x: cx - outerR, y: cy + gap / 2))
        p.addArc(center: CGPoint(x: cx, y: cy + gap / 2), radius: outerR,
                 startAngle: .degrees(180), endAngle: .degrees(0),
                 clockwise: true)
        p.addLine(to: CGPoint(x: cx + innerR, y: cy + gap / 2))
        p.addArc(center: CGPoint(x: cx, y: cy + gap / 2), radius: innerR,
                 startAngle: .degrees(0), endAngle: .degrees(180),
                 clockwise: false)
        p.closeSubpath()

        return p
    }
}

/// Intake valve: a filled valve head (the engine "pulls" air in here).
struct IntakeValveIcon: Shape {
    func path(in rect: CGRect) -> Path {
        valveShape(in: rect, hollow: false)
    }
}

/// Exhaust valve: a hollow / outlined valve head, visually distinguished
/// from the intake icon at a glance.
struct ExhaustValveIcon: Shape {
    func path(in rect: CGRect) -> Path {
        valveShape(in: rect, hollow: true)
    }
}

private func valveShape(in rect: CGRect, hollow: Bool) -> Path {
    var p = Path()
    let w = rect.width
    let h = rect.height
    let cx = w / 2

    let headTopY = h * 0.50
    let headBottomY = h * 0.84
    let headHalfWidth = w * 0.32

    // Valve head: trapezoidal disc (wider at top, narrows toward stem
    // at bottom — but in this top-down rendering the head is the disc
    // that seats against the port).
    p.move(to: CGPoint(x: cx - headHalfWidth, y: headTopY))
    p.addLine(to: CGPoint(x: cx + headHalfWidth, y: headTopY))
    p.addLine(to: CGPoint(x: cx + headHalfWidth * 0.55, y: headBottomY))
    p.addLine(to: CGPoint(x: cx - headHalfWidth * 0.55, y: headBottomY))
    p.closeSubpath()

    // Stem rising from the head's centre.
    let stemHalfWidth = w * 0.06
    let stemTopY = h * 0.14
    p.addRect(CGRect(x: cx - stemHalfWidth, y: stemTopY,
                     width: stemHalfWidth * 2, height: headTopY - stemTopY))

    // Retainer at the top of the stem.
    let retW = w * 0.18
    let retH = h * 0.04
    p.addRect(CGRect(x: cx - retW / 2, y: stemTopY,
                     width: retW, height: retH))

    // Hollow exhaust valves get an inner cut-out to look like an
    // outline instead of a filled disc.
    if hollow {
        let cutPad = headHalfWidth * 0.25
        p.move(to: CGPoint(x: cx - headHalfWidth + cutPad, y: headTopY + h * 0.04))
        p.addLine(to: CGPoint(x: cx + headHalfWidth - cutPad, y: headTopY + h * 0.04))
        p.addLine(to: CGPoint(x: cx + headHalfWidth * 0.55 - cutPad * 0.55,
                              y: headBottomY - h * 0.04))
        p.addLine(to: CGPoint(x: cx - headHalfWidth * 0.55 + cutPad * 0.55,
                              y: headBottomY - h * 0.04))
        p.closeSubpath()
    }

    return p
}

// MARK: - Engine-wide components

/// Cylinder head: a flat block silhouette with bolt-hole dots along the
/// top edge (head bolts) and two valve circles.
struct CylHeadIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        // Block outline.
        let blockRect = CGRect(x: w * 0.10, y: h * 0.30,
                               width: w * 0.80, height: h * 0.50)
        p.addRoundedRect(in: blockRect,
                         cornerSize: CGSize(width: h * 0.05, height: h * 0.05))

        // Head bolts along the top edge (small dots).
        let boltR = h * 0.04
        let boltY = blockRect.minY + h * 0.06
        for frac in stride(from: 0.18, through: 0.82, by: 0.16) {
            let bx = w * frac
            p.addEllipse(in: CGRect(x: bx - boltR, y: boltY - boltR,
                                    width: boltR * 2, height: boltR * 2))
        }

        // Two valve circles inside.
        let valveR = h * 0.07
        let valveY = blockRect.midY + h * 0.04
        p.addEllipse(in: CGRect(x: w * 0.34 - valveR, y: valveY - valveR,
                                width: valveR * 2, height: valveR * 2))
        p.addEllipse(in: CGRect(x: w * 0.66 - valveR, y: valveY - valveR,
                                width: valveR * 2, height: valveR * 2))

        return p
    }
}

/// Camshaft: long horizontal shaft with three lobes spaced along it.
struct CamshaftIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cy = h * 0.55

        // Shaft (thin horizontal bar).
        let shaftHalfThickness = h * 0.05
        p.addRect(CGRect(x: w * 0.08, y: cy - shaftHalfThickness,
                         width: w * 0.84, height: shaftHalfThickness * 2))

        // Three teardrop-ish lobes sticking up from the shaft.
        let lobeXs: [CGFloat] = [w * 0.25, w * 0.50, w * 0.75]
        let lobeHeight = h * 0.30
        let lobeWidth = w * 0.10
        for lx in lobeXs {
            p.move(to: CGPoint(x: lx - lobeWidth / 2, y: cy))
            p.addQuadCurve(to: CGPoint(x: lx, y: cy - lobeHeight),
                           control: CGPoint(x: lx - lobeWidth / 2,
                                            y: cy - lobeHeight * 0.40))
            p.addQuadCurve(to: CGPoint(x: lx + lobeWidth / 2, y: cy),
                           control: CGPoint(x: lx + lobeWidth / 2,
                                            y: cy - lobeHeight * 0.40))
            p.closeSubpath()
        }

        return p
    }
}

/// Crankshaft: horizontal shaft with offset crank-throws (the journals
/// the rods bolt onto, alternating up/down for realism).
struct CrankshaftIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cy = h * 0.55

        // Main shaft at the centre line.
        let shaftHalfThickness = h * 0.04
        p.addRect(CGRect(x: w * 0.06, y: cy - shaftHalfThickness,
                         width: w * 0.88, height: shaftHalfThickness * 2))

        // Crank throws: alternating bumps above / below the centre line.
        let throws_: [(CGFloat, CGFloat)] = [
            (w * 0.22, -1), (w * 0.42, 1), (w * 0.62, -1), (w * 0.82, 1)
        ]
        let throwOffsetY = h * 0.16
        let throwHalfWidth = w * 0.04
        let throwR = h * 0.06

        for (tx, dir) in throws_ {
            let journalCY = cy + throwOffsetY * dir
            // Web connecting shaft to journal.
            let webTop = min(cy, journalCY) - shaftHalfThickness
            let webBottom = max(cy, journalCY) + shaftHalfThickness
            p.addRect(CGRect(x: tx - throwHalfWidth, y: webTop,
                             width: throwHalfWidth * 2, height: webBottom - webTop))
            // Journal end-cap.
            p.addEllipse(in: CGRect(x: tx - throwR, y: journalCY - throwR,
                                    width: throwR * 2, height: throwR * 2))
        }

        return p
    }
}

/// Main bearing: a single bearing shell (like RodBearing but solo, more
/// of a half-moon silhouette).
struct MainBearingIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cx = w / 2
        let cy = h * 0.55

        let outerR = min(w, h) * 0.36
        let innerR = outerR * 0.62

        // Half-moon shell open at the bottom.
        p.move(to: CGPoint(x: cx - outerR, y: cy))
        p.addArc(center: CGPoint(x: cx, y: cy), radius: outerR,
                 startAngle: .degrees(180), endAngle: .degrees(360),
                 clockwise: false)
        p.addLine(to: CGPoint(x: cx + innerR, y: cy))
        p.addArc(center: CGPoint(x: cx, y: cy), radius: innerR,
                 startAngle: .degrees(360), endAngle: .degrees(180),
                 clockwise: true)
        p.closeSubpath()

        // A small "tab" notch on the top to make this read as a bearing
        // shell rather than just a half-disc.
        let tabW = w * 0.08
        let tabH = h * 0.05
        p.addRect(CGRect(x: cx - tabW / 2, y: cy - outerR - tabH * 0.4,
                         width: tabW, height: tabH))

        return p
    }
}

/// Water pump: impeller circle with three curved fins inside, plus a
/// little inlet/outlet stub on each side.
struct WaterPumpIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cx = w / 2
        let cy = h / 2

        let outerR = min(w, h) * 0.34

        // Pump housing (circle).
        p.addEllipse(in: CGRect(x: cx - outerR, y: cy - outerR,
                                width: outerR * 2, height: outerR * 2))

        // Hub at the centre.
        let hubR = outerR * 0.16
        p.addEllipse(in: CGRect(x: cx - hubR, y: cy - hubR,
                                width: hubR * 2, height: hubR * 2))

        // Three curved impeller fins.
        let finCount = 3
        let finInnerR = hubR * 1.4
        let finOuterR = outerR * 0.82
        for i in 0..<finCount {
            let baseA = CGFloat(i) * 2.0 * .pi / CGFloat(finCount) - .pi / 2
            let sweep: CGFloat = .pi / 3.5
            let aStart = baseA
            let aEnd = baseA + sweep
            let s = CGPoint(x: cx + cos(aStart) * finInnerR,
                            y: cy + sin(aStart) * finInnerR)
            let e = CGPoint(x: cx + cos(aEnd) * finOuterR,
                            y: cy + sin(aEnd) * finOuterR)
            let cMid = CGPoint(x: cx + cos((aStart + aEnd) / 2) * (finOuterR + finInnerR) / 2 - finOuterR * 0.20,
                               y: cy + sin((aStart + aEnd) / 2) * (finOuterR + finInnerR) / 2 - finOuterR * 0.20)
            p.move(to: s)
            p.addQuadCurve(to: e, control: cMid)
        }

        // Inlet / outlet stubs (small rectangles either side).
        let stubW = w * 0.08
        let stubH = h * 0.10
        p.addRect(CGRect(x: cx - outerR - stubW * 0.4, y: cy - stubH / 2,
                         width: stubW, height: stubH))
        p.addRect(CGRect(x: cx + outerR - stubW * 0.6, y: cy - stubH / 2,
                         width: stubW, height: stubH))

        return p
    }
}

/// Oil pump: gerotor-style silhouette — two interlocking gears.
struct OilPumpIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cy = h / 2

        let outerR = min(w, h) * 0.24
        let toothCount = 8
        let cx1 = w * 0.36
        let cx2 = w * 0.64

        // Two gear circles.
        for cx in [cx1, cx2] {
            // Outer gear silhouette via alternating outer / inner radii.
            let innerR = outerR * 0.82
            for i in 0..<(toothCount * 2) {
                let frac = CGFloat(i) / CGFloat(toothCount * 2)
                let angle: CGFloat = frac * 2.0 * .pi - .pi / 2
                let r = (i % 2 == 0) ? outerR : innerR
                let x = cx + cos(angle) * r
                let y = cy + sin(angle) * r
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            p.closeSubpath()

            // Central bore.
            let boreR = outerR * 0.30
            p.addEllipse(in: CGRect(x: cx - boreR, y: cy - boreR,
                                    width: boreR * 2, height: boreR * 2))
        }

        return p
    }
}
