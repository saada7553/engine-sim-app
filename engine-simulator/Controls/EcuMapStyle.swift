//
//  EcuMapStyle.swift
//  engine-simulator
//
//  Shared presentation helpers for the ECU tuning maps: the heatmap colour
//  ramp, value formatting, and the RPM axis label. Used by the interactive
//  EcuTuningView and the read-only tune preview in the community detail so both
//  colour and format cells identically.
//

import SwiftUI

enum EcuMapStyle {
    /// Cold-blue → green → red ramp over the editable range, matching how
    /// HP Tuners / EFILive colour their tables. Ignition reddens with advance;
    /// fuel reddens as the target AFR falls (richer), so the hot end always
    /// reads as "more fuel / more timing".
    static func heatColor(value: Double, kind: EcuMapKind) -> Color {
        let r = kind == .ignition ? EcuTuneModel.ignitionRange : EcuTuneModel.fuelRange
        let norm = (value - r.lowerBound) / (r.upperBound - r.lowerBound)
        let clamped = max(0.0, min(1.0, norm))
        let hue = kind == .ignition ? (0.62 - clamped * 0.62) : (clamped * 0.62)
        return Color(hue: hue, saturation: 0.62, brightness: 0.58)
    }

    static func format(value: Double, kind: EcuMapKind) -> String {
        switch kind {
        case .ignition: return String(format: "%+.1f", value)
        case .fuel:     return String(format: "%.1f", value)
        }
    }

    static func rpmLabel(_ rpm: Double) -> String {
        rpm >= 1000 ? String(format: "%.1fk", rpm / 1000.0) : String(format: "%.0f", rpm)
    }
}
