//
//  EcuTuneModel.swift
//  engine-simulator
//
//  The Swift-side "ECU" that drives the C++ engine's scalar ignition offset
//  and fuel trim. Holds two 2D maps (RPM × MAP-load), each editable by the
//  user: an absolute spark-advance map and a target-AFR map. On every polling
//  tick EngineViewModel asks this model for the values at the current
//  operating point and writes them through to the engine via
//  setIgnitionOffset / setFuelTrim — the same mechanism a real ECU uses when
//  looking up a tune. The fuel map stores a target AFR; the model converts
//  that to the fuel-trim multiplier the engine actually consumes.
//
//  Axes match common tuner conventions:
//    X = engine speed (RPM, 8 bins between 500 and redline)
//    Y = manifold absolute pressure in kPa (6 bins, idle vacuum → WOT)
//

import Foundation
import Combine

private let ignitionStep: Double = 0.5         // degrees per bump
private let fuelStep: Double = 0.1             // target-AFR per bump
// Ignition cells store absolute spark advance (degrees BTDC). This range is
// ONLY the heatmap colour-ramp domain and the factory-reset envelope — it is
// not an edit clamp. The user can dial a cell past either end (the colour just
// saturates), the way desktop tuner software lets you enter any value.
private let ignitionMin: Double = -10.0
private let ignitionMax: Double = 60.0
// Fuel cells store a TARGET air-fuel ratio on the same ~10-18 scale the AFR
// gauge reads. The ECU converts the looked-up target into a fuel-trim
// multiplier (trim = stoichAfr / target) before pushing it to the engine, so
// the map shows the user's intent in familiar units while the gauge keeps
// showing the engine's real measured AFR.
private let afrMin: Double = 10.0
private let afrMax: Double = 18.0
private let stoichAfr: Double = 14.7           // target AFR that maps to trim 1.0 (stock fuelling)
private let trimMin: Double = 0.5              // physics-safe clamp on the derived trim
private let trimMax: Double = 1.6
// Factory fuel curve: hold stoich at light load for economy, richen toward
// the WOT target at full load for power + charge cooling.
private let cruiseTargetAfr: Double = 14.7
private let wotTargetAfr: Double = 12.8
private let cruiseLoadCeilingKpa: Double = 45.0  // at/below this load, run stoich
private let wotLoadKpa: Double = 100.0
// "Known bad tune" extremes. Neighbouring cells alternate hard between a lean
// and a rich target (and heavy advance / retard for ignition) so the operating
// point swings through wildly different fuelling as revs drift — the engine
// hunts and the rpm bounces instead of merely running rich/lean/sluggish.
private let badLeanAfr: Double = 17.5
private let badRichAfr: Double = 10.5
private let badAdvanceDeg: Double = 45.0
private let badRetardDeg: Double = -8.0
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
    @Published var fuelMap: [[Double]]        // [loadIdx][rpmIdx] → target AFR
    @Published var tracerTrail: [EcuTraceSample] = []

    /// Factory target-AFR table captured at init. Used to restore the fuel
    /// map on reset, the same way baseTimingByRpmBin restores ignition.
    private let factoryFuelMap: [[Double]]

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

        // Seed the fuel map with the factory target-AFR curve. Targets vary by
        // manifold load only (flat across rpm) so the stock tune reads as clean
        // bands the user can then reshape.
        var fm = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        for loadIdx in 0..<rows {
            let afr = Self.factoryTargetAfr(loadKpa: loadBins[loadIdx])
            for rpmIdx in 0..<cols { fm[loadIdx][rpmIdx] = afr }
        }
        self.fuelMap = fm
        self.factoryFuelMap = fm
    }

    /// Build a read-only model for previewing an engine's tune without a live
    /// C++ engine (the community detail). The base ignition curve is sampled by
    /// interpolating the spec's own `ignitionTiming`, then the saved `ecuTune`
    /// is layered on if present — so the preview shows the author's tune, or the
    /// factory tune for an untuned engine.
    static func forDisplay(spec: EngineSpec) -> EcuTuneModel {
        let curve = spec.ignitionTiming.sorted { $0.rpm < $1.rpm }
        let provider: EcuBaseTimingProvider = { rpm in
            Self.interpolatedAdvance(curve, atRpm: rpm)
        }
        let model = EcuTuneModel(redlineRpm: spec.redlineRpm, baseTiming: provider)
        if let tune = spec.ecuTune { model.apply(tune) }
        return model
    }

    /// Linear interpolation of an ascending (rpm, advance) curve, clamped at the
    /// ends. Mirrors what the C++ ignition module does between control points.
    private static func interpolatedAdvance(_ curve: [TimingPoint], atRpm rpm: Double) -> Double {
        guard let first = curve.first else { return 0 }
        if rpm <= first.rpm { return first.advanceDeg }
        guard let last = curve.last else { return first.advanceDeg }
        if rpm >= last.rpm { return last.advanceDeg }
        for i in 0..<(curve.count - 1) {
            let lo = curve[i], hi = curve[i + 1]
            if rpm >= lo.rpm && rpm < hi.rpm {
                let frac = (rpm - lo.rpm) / (hi.rpm - lo.rpm)
                return lo.advanceDeg + frac * (hi.advanceDeg - lo.advanceDeg)
            }
        }
        return last.advanceDeg
    }

    /// Factory target AFR for a manifold load: flat stoich up to the cruise
    /// ceiling, then linearly richening to the WOT target at full load.
    private static func factoryTargetAfr(loadKpa: Double) -> Double {
        if loadKpa <= cruiseLoadCeilingKpa { return cruiseTargetAfr }
        let span = wotLoadKpa - cruiseLoadCeilingKpa
        let frac = min(1.0, (loadKpa - cruiseLoadCeilingKpa) / span)
        return cruiseTargetAfr + frac * (wotTargetAfr - cruiseTargetAfr)
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

    /// Bilinearly-interpolated target AFR at the operating point — the value
    /// the fuel map cells hold, used for display and tune diagnostics.
    func targetAfr(rpm: Double, loadKpa: Double) -> Double {
        return lookup(map: fuelMap, rpm: rpm, loadKpa: loadKpa)
    }

    /// Fuel-trim multiplier the engine receives. Derived from the target AFR:
    /// a richer target (lower AFR) needs more fuel → trim > 1, leaner → trim < 1.
    /// Clamped to a physics-safe band so an extreme target can't break the sim.
    func fuelTrim(rpm: Double, loadKpa: Double) -> Double {
        let target = targetAfr(rpm: rpm, loadKpa: loadKpa)
        let trim = stoichAfr / max(target, afrMin)
        return min(max(trim, trimMin), trimMax)
    }

    /// Mean absolute AFR difference between adjacent fuel cells. Near zero for a
    /// smooth tune, large for a jagged one (the "bad tune" checkerboard runs
    /// ~7). EngineViewModel uses this to decide how hard to surge the engine:
    /// a real ECU fed a wildly inconsistent map delivers erratic fuelling that
    /// makes the idle hunt, which a single interpolated trim value can't capture.
    func fuelMapRoughness() -> Double {
        return mapRoughness(fuelMap)
    }

    /// Same roughness measure for the ignition map (degrees). The "bad tune"
    /// ignition checkerboard runs huge; a normal timing curve is near zero.
    func ignitionMapRoughness() -> Double {
        return mapRoughness(ignitionMap)
    }

    /// Mean absolute difference between adjacent cells of a map.
    private func mapRoughness(_ map: [[Double]]) -> Double {
        var sum = 0.0
        var count = 0.0
        for loadIdx in 0..<map.count {
            for rpmIdx in 0..<map[loadIdx].count {
                let v = map[loadIdx][rpmIdx]
                if rpmIdx + 1 < map[loadIdx].count {
                    sum += abs(v - map[loadIdx][rpmIdx + 1]); count += 1
                }
                if loadIdx + 1 < map.count {
                    sum += abs(v - map[loadIdx + 1][rpmIdx]); count += 1
                }
            }
        }
        return count > 0 ? sum / count : 0
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

    // MARK: - Persistence (save / restore a tune onto the engine spec)

    /// Snapshot the current maps and axes for persisting onto the EngineSpec.
    func export() -> EcuTune {
        EcuTune(rpmBins: rpmBins, loadBins: loadBins,
                ignitionMap: ignitionMap, fuelMap: fuelMap)
    }

    /// Restore a saved tune. Applied only when the grid dimensions match this
    /// model's (they will for the same engine, since the rpm axis is derived
    /// from the redline) — a mismatch is ignored so the freshly-seeded factory
    /// tune stands rather than crashing on a stale grid.
    func apply(_ tune: EcuTune) {
        guard tune.ignitionMap.count == ignitionMap.count,
              tune.fuelMap.count == fuelMap.count,
              tune.ignitionMap.allSatisfy({ $0.count == rpmBins.count }),
              tune.fuelMap.allSatisfy({ $0.count == rpmBins.count }) else {
            print("EcuTuneModel: saved tune grid mismatch; keeping factory tune.")
            return
        }
        ignitionMap = tune.ignitionMap
        fuelMap = tune.fuelMap
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
    static var fuelRange: ClosedRange<Double> { afrMin ... afrMax }
    static var ignitionBumpStep: Double { ignitionStep }
    static var fuelBumpStep: Double { fuelStep }
    /// Target AFR that maps to a 1.0 trim. Lets the UI convert a live applied
    /// fuel-trim back into an AFR for display (inverse of `fuelTrim`).
    static var stoichReferenceAfr: Double { stoichAfr }

    func value(in kind: EcuMapKind, at coord: EcuCellCoord) -> Double {
        let safe = clampToBounds(coord)
        switch kind {
        case .ignition: return ignitionMap[safe.loadIndex][safe.rpmIndex]
        case .fuel:     return fuelMap[safe.loadIndex][safe.rpmIndex]
        }
    }

    /// Cell values are intentionally NOT clamped to the colour range — the user
    /// can tune to any value. (`coord` is still bounds-checked so a stale grid
    /// index can't crash the array.) Physics safety lives downstream: `fuelTrim`
    /// clamps the derived trim to a sim-safe band regardless of the AFR entered.
    func setCell(in kind: EcuMapKind, at coord: EcuCellCoord, to value: Double) {
        let safe = clampToBounds(coord)
        switch kind {
        case .ignition: ignitionMap[safe.loadIndex][safe.rpmIndex] = value
        case .fuel:     fuelMap[safe.loadIndex][safe.rpmIndex] = value
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
                    ignitionMap[i][j] += delta
                }
            }
        case .fuel:
            for i in 0..<fuelMap.count {
                for j in 0..<fuelMap[i].count {
                    fuelMap[i][j] += delta
                }
            }
        }
    }

    /// Snap cells back to their factory baseline. Ignition restores to the
    /// engine's base timing curve (per-rpm value, flat across load). Fuel
    /// restores to the factory target-AFR table captured at init.
    func reset(_ kind: EcuMapKind) {
        switch kind {
        case .ignition:
            for loadIdx in 0..<ignitionMap.count {
                for rpmIdx in 0..<ignitionMap[loadIdx].count {
                    ignitionMap[loadIdx][rpmIdx] = baseTimingByRpmBin[rpmIdx]
                }
            }
        case .fuel:
            fuelMap = factoryFuelMap
        }
    }

    /// Load a deliberately broken tune into the map. Neighbouring cells
    /// alternate between extremes in a checkerboard (lean ↔ rich for fuel,
    /// advance ↔ retard for ignition) with a deterministic per-cell jitter so
    /// the result is reproducible — the same "known bad" tune every press — yet
    /// erratic enough that the engine hunts and the rpm bounces around as the
    /// operating point crosses wildly different cells, rather than just running
    /// flatly rich, lean, or sluggish.
    func corrupt(_ kind: EcuMapKind) {
        switch kind {
        case .ignition:
            forEachCell(in: &ignitionMap) { rpmIdx, loadIdx in
                let j = Self.cellJitter(rpmIdx, loadIdx)
                let value = isLeanCell(rpmIdx, loadIdx)
                    ? badAdvanceDeg - j * 10.0
                    : badRetardDeg + j * 6.0
                return value.clamped(to: EcuTuneModel.ignitionRange)
            }
        case .fuel:
            forEachCell(in: &fuelMap) { rpmIdx, loadIdx in
                let j = Self.cellJitter(rpmIdx, loadIdx)
                let value = isLeanCell(rpmIdx, loadIdx)
                    ? badLeanAfr - j * 1.5
                    : badRichAfr + j * 1.5
                return value.clamped(to: EcuTuneModel.fuelRange)
            }
        }
    }

    /// Checkerboard parity: which diagonal of cells gets the lean / high-advance
    /// extreme. Alternating on (rpm + load) means a small drift in either axis
    /// flips the target, so the engine can't settle.
    private func isLeanCell(_ rpmIdx: Int, _ loadIdx: Int) -> Bool {
        (rpmIdx + loadIdx) % 2 == 0
    }

    /// Deterministic per-cell value in [0,1). Looks random but is stable across
    /// presses so the "bad tune" is the same every time.
    private static func cellJitter(_ rpmIdx: Int, _ loadIdx: Int) -> Double {
        let h = (rpmIdx &* 73856093) ^ (loadIdx &* 19349663)
        return Double((h & 0x7fffffff) % 1000) / 1000.0
    }

    /// Rewrite every cell of `map` from a transform of its (rpmIdx, loadIdx).
    private func forEachCell(in map: inout [[Double]], _ transform: (Int, Int) -> Double) {
        for loadIdx in 0..<map.count {
            for rpmIdx in 0..<map[loadIdx].count {
                map[loadIdx][rpmIdx] = transform(rpmIdx, loadIdx)
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
