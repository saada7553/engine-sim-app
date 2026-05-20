//
//  EcuTuneModel.swift
//  engine-simulator
//
//  The Swift-side "ECU" that drives the C++ engine's scalar ignition offset
//  and fuel trim. Holds two 2D maps (RPM × MAP-load), each editable by the
//  user. On every polling tick EngineViewModel asks this model for the
//  values that correspond to the current operating point and writes them
//  through to the engine via setIgnitionOffset / setFuelTrim — the same
//  mechanism a real ECU uses when looking up a tune.
//
//  Axes match common tuner conventions:
//    X = engine speed (RPM, 8 bins between 500 and redline)
//    Y = manifold absolute pressure in kPa (6 bins, idle vacuum → WOT)
//

import Foundation
import Combine

private let ignitionStep: Double = 0.5         // degrees per bump
private let fuelStep: Double = 0.02            // multiplier per bump
// Cells store absolute spark advance (degrees BTDC). Range covers retard
// territory and aggressive race timing without clamping reasonable engines.
private let ignitionMin: Double = -10.0
private let ignitionMax: Double = 60.0
private let fuelMin: Double = 0.6
private let fuelMax: Double = 1.5
private let trailDuration: TimeInterval = 3.0
private let trailMaxSamples: Int = 90          // 30 Hz × 3 s
private let standardLoadBins: [Double] = [30, 45, 60, 75, 90, 100]   // kPa absolute
private let rpmFloor: Double = 500.0           // bin 0
private let redlineFloor: Double = 4000.0      // safety: don't degenerate bins for tiny engines
private let rpmPerBinTarget: Double = 750.0    // density target: ~one bin every 750 rpm
private let minRpmBinCount: Int = 6            // never collapse below this
private let maxRpmBinCount: Int = 14           // visual cap so cells stay readable

struct EcuTraceSample: Identifiable {
    let id = UUID()
    let rpm: Double
    let loadKpa: Double
    let time: Date
}

enum EcuMapKind {
    case ignition
    case fuel
}

/// Coordinates in the map grid. `loadIndex` and `rpmIndex` both reference the
/// underlying storage order (loadIndex 0 = lowest load, loadIndex N-1 = WOT;
/// rpmIndex 0 = lowest rpm).
struct EcuCellCoord: Equatable, Hashable {
    let loadIndex: Int
    let rpmIndex: Int
}

/// Closure that returns the engine's base spark advance (deg BTDC) at a given
/// rpm. Backed by the C++ ignition-module curve via the EngineWrapper.
typealias EcuBaseTimingProvider = (Double) -> Double

final class EcuTuneModel: ObservableObject {
    let rpmBins: [Double]
    let loadBins: [Double] = standardLoadBins

    /// Base spark advance (deg) sampled once at each rpm bin when this model
    /// is built. The single source of truth that seeds the ignition map; also
    /// used at runtime to compute the delta we push into the C++ engine.
    let baseTimingByRpmBin: [Double]

    @Published var ignitionMap: [[Double]]    // [loadIdx][rpmIdx] → absolute deg BTDC
    @Published var fuelMap: [[Double]]        // [loadIdx][rpmIdx] → trim multiplier
    @Published var tracerTrail: [EcuTraceSample] = []

    /// Last sampled operating point — used by the view to draw the live dot
    /// without subscribing to high-frequency rpm changes through every cell.
    @Published var currentRpm: Double = 0.0
    @Published var currentLoadKpa: Double = 0.0

    init(redlineRpm: Double, baseTiming: EcuBaseTimingProvider) {
        // Build RPM bins evenly between rpmFloor and the engine's redline.
        // Bin count scales with redline (~one bin per 750 RPM of usable range)
        // and is clamped so a tiny engine still has resolution and a huge one
        // doesn't blow the grid out to 30 columns.
        let topRpm = max(redlineRpm, redlineFloor)
        let usableSpan = topRpm - rpmFloor
        let scaled = Int(round(usableSpan / rpmPerBinTarget)) + 1
        let binCount = max(minRpmBinCount, min(maxRpmBinCount, scaled))
        let stepCount = binCount - 1
        var rpms: [Double] = []
        rpms.reserveCapacity(binCount)
        for i in 0..<binCount {
            let frac = Double(i) / Double(stepCount)
            rpms.append(rpmFloor + frac * (topRpm - rpmFloor))
        }
        self.rpmBins = rpms

        // Sample the engine's base curve once at every bin. These become both
        // the initial map values and the runtime baseline for delta computation.
        var bases: [Double] = []
        bases.reserveCapacity(binCount)
        for rpm in rpms {
            bases.append(baseTiming(rpm))
        }
        self.baseTimingByRpmBin = bases

        let cols = rpmBins.count
        let rows = loadBins.count
        var ig = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        for rpmIdx in 0..<cols {
            let base = bases[rpmIdx]
            for loadIdx in 0..<rows {
                ig[loadIdx][rpmIdx] = base
            }
        }
        self.ignitionMap = ig
        self.fuelMap = Array(repeating: Array(repeating: 1.0, count: cols), count: rows)
    }

    /// Linearly-interpolated base curve sample for any rpm. Used by
    /// EngineViewModel to compute the offset = mapValue − baseAtRpm that gets
    /// pushed into the C++ ignition module.
    func baseTiming(at rpm: Double) -> Double {
        let (low, high, frac) = bracket(value: rpm, bins: rpmBins)
        let lo = baseTimingByRpmBin[low]
        let hi = baseTimingByRpmBin[high]
        return lo + frac * (hi - lo)
    }

    // MARK: - Lookup (bilinear)

    /// Absolute spark advance (deg BTDC) at the given operating point. The
    /// engine receives delta = ignitionAdvance(rpm, loadKpa) − baseTiming(rpm).
    func ignitionAdvance(rpm: Double, loadKpa: Double) -> Double {
        return lookup(map: ignitionMap, rpm: rpm, loadKpa: loadKpa)
    }

    func fuelTrim(rpm: Double, loadKpa: Double) -> Double {
        return lookup(map: fuelMap, rpm: rpm, loadKpa: loadKpa)
    }

    private func lookup(map: [[Double]], rpm: Double, loadKpa: Double) -> Double {
        let (xLow, xHigh, xFrac) = bracket(value: rpm, bins: rpmBins)
        let (yLow, yHigh, yFrac) = bracket(value: loadKpa, bins: loadBins)
        let v00 = map[yLow][xLow]
        let v10 = map[yLow][xHigh]
        let v01 = map[yHigh][xLow]
        let v11 = map[yHigh][xHigh]
        let v0 = v00 + xFrac * (v10 - v00)
        let v1 = v01 + xFrac * (v11 - v01)
        return v0 + yFrac * (v1 - v0)
    }

    private func bracket(value: Double, bins: [Double]) -> (low: Int, high: Int, frac: Double) {
        guard let first = bins.first, let last = bins.last else { return (0, 0, 0) }
        if value <= first { return (0, 0, 0) }
        if value >= last { let n = bins.count - 1; return (n, n, 0) }
        for i in 0..<(bins.count - 1) {
            let lo = bins[i]
            let hi = bins[i + 1]
            if value >= lo && value < hi {
                let frac = (value - lo) / (hi - lo)
                return (i, i + 1, frac)
            }
        }
        let n = bins.count - 1
        return (n, n, 0)
    }

    // MARK: - Trail recording

    /// Stores the current operating point and trims old samples. Called once
    /// per polling tick from EngineViewModel.
    func recordSample(rpm: Double, loadKpa: Double) {
        currentRpm = rpm
        currentLoadKpa = loadKpa
        let now = Date()
        tracerTrail.append(EcuTraceSample(rpm: rpm, loadKpa: loadKpa, time: now))
        let cutoff = now.addingTimeInterval(-trailDuration)
        while let first = tracerTrail.first, first.time < cutoff {
            tracerTrail.removeFirst()
        }
        if tracerTrail.count > trailMaxSamples {
            tracerTrail.removeFirst(tracerTrail.count - trailMaxSamples)
        }
    }

    // MARK: - Cell editing

    static var ignitionRange: ClosedRange<Double> { ignitionMin ... ignitionMax }
    static var fuelRange: ClosedRange<Double> { fuelMin ... fuelMax }
    static var ignitionBumpStep: Double { ignitionStep }
    static var fuelBumpStep: Double { fuelStep }

    func value(in kind: EcuMapKind, at coord: EcuCellCoord) -> Double {
        let safe = clampToBounds(coord)
        switch kind {
        case .ignition: return ignitionMap[safe.loadIndex][safe.rpmIndex]
        case .fuel:     return fuelMap[safe.loadIndex][safe.rpmIndex]
        }
    }

    func setCell(in kind: EcuMapKind, at coord: EcuCellCoord, to value: Double) {
        let safe = clampToBounds(coord)
        switch kind {
        case .ignition:
            ignitionMap[safe.loadIndex][safe.rpmIndex] = value.clamped(to: EcuTuneModel.ignitionRange)
        case .fuel:
            fuelMap[safe.loadIndex][safe.rpmIndex] = value.clamped(to: EcuTuneModel.fuelRange)
        }
    }

    func bumpCell(in kind: EcuMapKind, at coord: EcuCellCoord, by delta: Double) {
        let current = value(in: kind, at: coord)
        setCell(in: kind, at: coord, to: current + delta)
    }

    /// Clamp a cell coord to valid bin indices so a stale coord left over from
    /// a previous engine's larger grid can't crash an array lookup.
    func clampToBounds(_ coord: EcuCellCoord) -> EcuCellCoord {
        let load = max(0, min(loadBins.count - 1, coord.loadIndex))
        let rpm = max(0, min(rpmBins.count - 1, coord.rpmIndex))
        return EcuCellCoord(loadIndex: load, rpmIndex: rpm)
    }

    func bumpAll(in kind: EcuMapKind, by delta: Double) {
        switch kind {
        case .ignition:
            for i in 0..<ignitionMap.count {
                for j in 0..<ignitionMap[i].count {
                    ignitionMap[i][j] = (ignitionMap[i][j] + delta).clamped(to: EcuTuneModel.ignitionRange)
                }
            }
        case .fuel:
            for i in 0..<fuelMap.count {
                for j in 0..<fuelMap[i].count {
                    fuelMap[i][j] = (fuelMap[i][j] + delta).clamped(to: EcuTuneModel.fuelRange)
                }
            }
        }
    }

    /// Snap cells back to their factory baseline. Ignition restores to the
    /// engine's base timing curve (per-rpm value, flat across load). Fuel
    /// restores to a 1.0 trim everywhere (no enrichment / no enleanment).
    func reset(_ kind: EcuMapKind) {
        switch kind {
        case .ignition:
            for loadIdx in 0..<ignitionMap.count {
                for rpmIdx in 0..<ignitionMap[loadIdx].count {
                    ignitionMap[loadIdx][rpmIdx] = baseTimingByRpmBin[rpmIdx]
                }
            }
        case .fuel:
            for i in 0..<fuelMap.count {
                for j in 0..<fuelMap[i].count { fuelMap[i][j] = 1.0 }
            }
        }
    }

    /// 3×3 box blur with edge-aware averaging. Mimics the "smooth" action in
    /// real tuner software after you sweep a few cells.
    func smooth(_ kind: EcuMapKind) {
        switch kind {
        case .ignition: ignitionMap = boxBlur(ignitionMap)
        case .fuel:     fuelMap     = boxBlur(fuelMap)
        }
    }

    private func boxBlur(_ map: [[Double]]) -> [[Double]] {
        let rows = map.count
        let cols = map[0].count
        var out = map
        for r in 0..<rows {
            for c in 0..<cols {
                var sum = 0.0
                var n = 0.0
                for dr in -1...1 {
                    for dc in -1...1 {
                        let rr = r + dr, cc = c + dc
                        if rr >= 0 && rr < rows && cc >= 0 && cc < cols {
                            sum += map[rr][cc]
                            n += 1
                        }
                    }
                }
                out[r][c] = sum / n
            }
        }
        return out
    }
}

// MARK: - Helpers

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
