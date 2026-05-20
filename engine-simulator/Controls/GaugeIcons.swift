//
//  GaugeIcons.swift
//  engine-simulator
//
//  Custom drawn icons for the engine status lights, mimicking car gauge cluster warning lights.
//

import SwiftUI

struct IgnitionIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Battery body
        path.addRoundedRect(in: CGRect(x: w * 0.1, y: h * 0.3, width: w * 0.8, height: h * 0.55), cornerSize: CGSize(width: 2, height: 2))
        
        // Battery terminals
        path.addRect(CGRect(x: w * 0.2, y: h * 0.2, width: w * 0.2, height: h * 0.1))
        path.addRect(CGRect(x: w * 0.6, y: h * 0.2, width: w * 0.2, height: h * 0.1))
        
        // Plus and Minus signs
        // Minus (left)
        path.move(to: CGPoint(x: w * 0.2, y: h * 0.575))
        path.addLine(to: CGPoint(x: w * 0.4, y: h * 0.575))
        
        // Plus (right)
        path.move(to: CGPoint(x: w * 0.6, y: h * 0.575))
        path.addLine(to: CGPoint(x: w * 0.8, y: h * 0.575))
        path.move(to: CGPoint(x: w * 0.7, y: h * 0.475))
        path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.675))
        
        return path
    }
}

struct StarterIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let center = CGPoint(x: w/2, y: h/2)
        
        // Circular arrow (Starter motor / circular movement)
        path.addArc(center: center, radius: w * 0.35, startAngle: .degrees(45), endAngle: .degrees(315), clockwise: false)
        
        // Arrow head
        path.move(to: CGPoint(x: w * 0.6, y: h * 0.1))
        path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.25))
        path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.45))
        
        // Inner "S" or bolt to suggest motor
        path.move(to: CGPoint(x: w * 0.4, y: h * 0.4))
        path.addLine(to: CGPoint(x: w * 0.6, y: h * 0.4))
        path.addLine(to: CGPoint(x: w * 0.4, y: h * 0.6))
        path.addLine(to: CGPoint(x: w * 0.6, y: h * 0.6))
        
        return path
    }
}

struct ClutchIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let center = CGPoint(x: w/2, y: h/2)
        
        // Clutch Pressure Plate / Disc Look
        path.addEllipse(in: CGRect(x: w * 0.1, y: h * 0.1, width: w * 0.8, height: h * 0.8))
        path.addEllipse(in: CGRect(x: w * 0.3, y: h * 0.3, width: w * 0.4, height: h * 0.4))
        
        // Friction material sections
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3
            let inner = CGPoint(x: center.x + cos(angle) * w * 0.2, y: center.y + sin(angle) * h * 0.2)
            let outer = CGPoint(x: center.x + cos(angle) * w * 0.4, y: center.y + sin(angle) * h * 0.4)
            path.move(to: inner)
            path.addLine(to: outer)
        }
        
        // Dashed outer ring for a more mechanical feel
        for i in 0..<12 {
            let angle = CGFloat(i) * .pi / 6
            let start = CGPoint(x: center.x + cos(angle) * w * 0.42, y: center.y + sin(angle) * h * 0.42)
            let end = CGPoint(x: center.x + cos(angle + 0.2) * w * 0.42, y: center.y + sin(angle + 0.2) * h * 0.42)
            path.move(to: start)
            path.addLine(to: end)
        }
        
        return path
    }
}

struct DynoIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // "Check Engine" / Engine Block silhouette (common for Dyno/Engine status)
        path.move(to: CGPoint(x: w * 0.2, y: h * 0.4))
        path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.4))
        path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.6, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.6, y: h * 0.4))
        path.addLine(to: CGPoint(x: w * 0.8, y: h * 0.4))
        path.addLine(to: CGPoint(x: w * 0.8, y: h * 0.7))
        path.addLine(to: CGPoint(x: w * 0.2, y: h * 0.7))
        path.closeSubpath()
        
        // Fan/Pulley circle
        path.addEllipse(in: CGRect(x: w * 0.35, y: h * 0.45, width: w * 0.2, height: h * 0.2))
        
        // Lightning bolt overlay to suggest "Power/Dyno"
        path.move(to: CGPoint(x: w * 0.65, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.55))
        path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.55))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.8))
        
        return path
    }
}

struct HoldIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let center = CGPoint(x: w/2, y: h * 0.6)
        
        // Speedometer-like "Cruise Control" / "Hold" icon
        path.addArc(center: center, radius: w * 0.4, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        
        // Tick marks
        for i in 0...4 {
            let angle = CGFloat(i) * .pi / 4 + .pi
            let start = CGPoint(x: center.x + cos(angle) * w * 0.3, y: center.y + sin(angle) * h * 0.3)
            let end = CGPoint(x: center.x + cos(angle) * w * 0.4, y: center.y + sin(angle) * h * 0.4)
            path.move(to: start)
            path.addLine(to: end)
        }
        
        // Needle pointing at a fixed position
        let needleAngle: CGFloat = -.pi / 4
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + cos(needleAngle) * w * 0.35, y: center.y + sin(needleAngle) * h * 0.35))
        
        // "HOLD" lock base
        path.addRoundedRect(in: CGRect(x: w * 0.4, y: h * 0.65, width: w * 0.2, height: h * 0.15), cornerSize: CGSize(width: 1, height: 1))
        
        return path
    }
}

struct CheckEngineIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Classic "Check Engine" silhouette
        path.move(to: CGPoint(x: w * 0.15, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.15, y: h * 0.75))
        path.closeSubpath()
        
        // Air filter / intake box
        path.addRect(CGRect(x: w * 0.3, y: h * 0.25, width: w * 0.3, height: h * 0.1))
        
        // Fan / pulley circle
        path.addEllipse(in: CGRect(x: w * 0.4, y: h * 0.5, width: w * 0.15, height: h * 0.15))
        
        return path
    }
}

