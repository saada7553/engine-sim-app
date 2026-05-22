//
//  GaugeIcons.swift
//  engine-simulator
//
//  Hand-drawn icons used in the top-bar warning-light cluster. Each icon is
//  a `Shape` so the call site can stroke + fill it with whatever color the
//  light is currently lit in. The silhouettes lean on real-car warning-light
//  conventions (battery, starter motor, clutch disc, dyno roller, lock)
//  rather than generic geometric shapes.
//

import SwiftUI

// MARK: - IGN (battery)

struct IgnitionIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let bodyTop = h * 0.30
        let bodyHeight = h * 0.55
        let bodyRect = CGRect(x: w * 0.10, y: bodyTop, width: w * 0.80, height: bodyHeight)
        p.addRoundedRect(in: bodyRect, cornerSize: CGSize(width: w * 0.06, height: w * 0.06))

        // Two raised terminal nubs on top.
        let termW = w * 0.18
        let termH = h * 0.12
        p.addRoundedRect(in: CGRect(x: w * 0.22, y: bodyTop - termH, width: termW, height: termH + 1),
                         cornerSize: CGSize(width: 1, height: 1))
        p.addRoundedRect(in: CGRect(x: w - w * 0.22 - termW, y: bodyTop - termH, width: termW, height: termH + 1),
                         cornerSize: CGSize(width: 1, height: 1))

        // Polarity markers: + on the right cell, − on the left.
        let cellY = bodyTop + bodyHeight * 0.50
        let minusLen = w * 0.16
        let plusLen = w * 0.16
        // Minus
        p.move(to: CGPoint(x: w * 0.22, y: cellY))
        p.addLine(to: CGPoint(x: w * 0.22 + minusLen, y: cellY))
        // Plus (horizontal)
        p.move(to: CGPoint(x: w - w * 0.22 - plusLen, y: cellY))
        p.addLine(to: CGPoint(x: w - w * 0.22, y: cellY))
        // Plus (vertical)
        p.move(to: CGPoint(x: w - w * 0.22 - plusLen / 2, y: cellY - plusLen / 2))
        p.addLine(to: CGPoint(x: w - w * 0.22 - plusLen / 2, y: cellY + plusLen / 2))

        return p
    }
}

// MARK: - START (starter motor)

struct StarterIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cx = w / 2
        let cy = h / 2
        let outerR = min(w, h) * 0.40

        // Toothed gear: alternating outer and inner radii produce the teeth.
        let toothCount = 10
        let innerR = outerR * 0.78
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

        // Central bore and lightning bolt (cranking power).
        p.addEllipse(in: CGRect(x: cx - outerR * 0.18, y: cy - outerR * 0.18,
                                width: outerR * 0.36, height: outerR * 0.36))

        let boltTop = CGPoint(x: cx - outerR * 0.18, y: cy - outerR * 0.50)
        let boltMidR = CGPoint(x: cx + outerR * 0.10, y: cy - outerR * 0.05)
        let boltMidL = CGPoint(x: cx - outerR * 0.04, y: cy + outerR * 0.05)
        let boltBottom = CGPoint(x: cx + outerR * 0.20, y: cy + outerR * 0.50)
        p.move(to: boltTop)
        p.addLine(to: boltMidR)
        p.addLine(to: boltMidL)
        p.addLine(to: boltBottom)

        return p
    }
}

// MARK: - DYNO (roller drum)

struct DynoIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        // Horizontal drum: an oval cap on each end and a body rectangle between.
        let drumLeft = w * 0.10
        let drumRight = w * 0.90
        let drumTop = h * 0.36
        let drumBottom = h * 0.78
        let drumHeight = drumBottom - drumTop
        let capWidth = drumHeight * 0.45
        let drumMid = (drumTop + drumBottom) / 2

        // Drum body sides.
        p.move(to: CGPoint(x: drumLeft + capWidth / 2, y: drumTop))
        p.addLine(to: CGPoint(x: drumRight - capWidth / 2, y: drumTop))
        p.move(to: CGPoint(x: drumLeft + capWidth / 2, y: drumBottom))
        p.addLine(to: CGPoint(x: drumRight - capWidth / 2, y: drumBottom))
        // End caps.
        p.addEllipse(in: CGRect(x: drumLeft, y: drumTop, width: capWidth, height: drumHeight))
        p.addEllipse(in: CGRect(x: drumRight - capWidth, y: drumTop, width: capWidth, height: drumHeight))

        // Rotation indicator: curved arrow over the drum.
        let arcCenter = CGPoint(x: w / 2, y: drumMid)
        let arcR = drumHeight * 1.05
        p.addArc(center: arcCenter, radius: arcR,
                 startAngle: .degrees(195), endAngle: .degrees(345), clockwise: false)
        // Arrowhead at the right end of the arc.
        let tipAngle: CGFloat = -.pi / 9  // ≈ -20°
        let tip = CGPoint(x: arcCenter.x + cos(tipAngle) * arcR,
                          y: arcCenter.y + sin(tipAngle) * arcR)
        let arrowSize = drumHeight * 0.35
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x - arrowSize, y: tip.y - arrowSize * 0.4))
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x - arrowSize * 0.3, y: tip.y + arrowSize))

        // Small stand legs under the drum.
        let legY = h * 0.90
        p.move(to: CGPoint(x: drumLeft + capWidth / 2, y: drumBottom))
        p.addLine(to: CGPoint(x: drumLeft + capWidth / 2 - capWidth * 0.4, y: legY))
        p.move(to: CGPoint(x: drumRight - capWidth / 2, y: drumBottom))
        p.addLine(to: CGPoint(x: drumRight - capWidth / 2 + capWidth * 0.4, y: legY))

        return p
    }
}

// MARK: - HOLD (throttle latch)

struct HoldIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        // Padlock body.
        let bodyW = w * 0.55
        let bodyH = h * 0.40
        let bodyX = (w - bodyW) / 2
        let bodyY = h * 0.50
        p.addRoundedRect(in: CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
                         cornerSize: CGSize(width: w * 0.05, height: w * 0.05))

        // Shackle (closed loop above the body).
        let shackleCenterX = w / 2
        let shackleR = bodyW * 0.32
        let shackleCY = bodyY
        p.move(to: CGPoint(x: shackleCenterX - shackleR, y: shackleCY))
        p.addArc(center: CGPoint(x: shackleCenterX, y: shackleCY), radius: shackleR,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: shackleCenterX + shackleR, y: shackleCY + bodyH * 0.10))
        p.move(to: CGPoint(x: shackleCenterX - shackleR, y: shackleCY))
        p.addLine(to: CGPoint(x: shackleCenterX - shackleR, y: shackleCY + bodyH * 0.10))

        // Keyhole inside the body.
        let kx = w / 2
        let ky = bodyY + bodyH * 0.45
        p.addEllipse(in: CGRect(x: kx - bodyW * 0.06, y: ky - bodyW * 0.06,
                                width: bodyW * 0.12, height: bodyW * 0.12))
        p.move(to: CGPoint(x: kx, y: ky))
        p.addLine(to: CGPoint(x: kx, y: bodyY + bodyH * 0.85))

        return p
    }
}

// MARK: - CHECK ENGINE (engine block)

struct CheckEngineIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        // Stylised engine-block silhouette (rocker cover + sump).
        p.move(to: CGPoint(x: w * 0.18, y: h * 0.40))
        p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.40))
        p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.28))
        p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.28))
        p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.40))
        p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.40))
        p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.72))
        p.addLine(to: CGPoint(x: w * 0.74, y: h * 0.72))
        p.addLine(to: CGPoint(x: w * 0.74, y: h * 0.84))
        p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.84))
        p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.72))
        p.addLine(to: CGPoint(x: w * 0.14, y: h * 0.72))
        p.closeSubpath()

        // Intake snorkel sticking out the top.
        p.addRect(CGRect(x: w * 0.42, y: h * 0.20, width: w * 0.16, height: h * 0.10))

        // Pulley / fan circle.
        p.addEllipse(in: CGRect(x: w * 0.42, y: h * 0.50, width: w * 0.16, height: h * 0.16))

        // "Check" indicator: small exclamation mark in the lower-right.
        let exX = w * 0.66
        let exTop = h * 0.50
        let exBottom = h * 0.66
        p.move(to: CGPoint(x: exX, y: exTop))
        p.addLine(to: CGPoint(x: exX, y: exBottom))
        p.addEllipse(in: CGRect(x: exX - 1, y: exBottom + 2, width: 2, height: 2))

        return p
    }
}
