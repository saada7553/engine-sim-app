//
//  PlatformColor.swift
//  engine-simulator
//
//  SceneKit materials accept either NSColor or UIColor for `diffuse.contents`,
//  but the procedural geometry code was written against NSColor and
//  `NSColor(calibratedRed:…)` — which doesn't exist on UIColor. This file
//  provides a `PlatformColor` typealias plus a single `calibrated(...)`
//  factory so the geometry files can stay platform-agnostic.
//

import SwiftUI
#if os(macOS)
import AppKit
public typealias PlatformColor = NSColor
#else
import UIKit
public typealias PlatformColor = UIColor
#endif

/// SceneKit `SCNVector3` and SCN node scalar fields (`position.x`,
/// `eulerAngles.y`, etc.) use `CGFloat` on macOS but `Float` on iOS. Using
/// `SCNFloat(...)` everywhere we'd reach for `CGFloat(...)` lets the same
/// procedural geometry code compile against both SceneKit variants.
#if os(macOS)
public typealias SCNFloat = CGFloat
#else
public typealias SCNFloat = Float
#endif

#if os(macOS)
public typealias PlatformBezierPath = NSBezierPath

extension NSBezierPath {
    /// Mirror UIBezierPath's `addCurve(to:controlPoint1:controlPoint2:)` API
    /// on macOS so geometry code can stay platform-agnostic. NSBezierPath
    /// already has the same semantics — just spelled `curve(...)`.
    func addCurve(to endPoint: NSPoint, controlPoint1: NSPoint, controlPoint2: NSPoint) {
        curve(to: endPoint, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
    }
}
#else
public typealias PlatformBezierPath = UIBezierPath
#endif

extension PlatformColor {
    /// Match the macOS `NSColor(calibratedRed:green:blue:alpha:)` call site so
    /// both platforms get the same straight sRGB-ish behavior. On iOS this
    /// falls through to `UIColor(red:green:blue:alpha:)`, which is what
    /// SceneKit expects anyway.
    static func calibrated(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat
    ) -> PlatformColor {
        #if os(macOS)
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
        #else
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }
}
