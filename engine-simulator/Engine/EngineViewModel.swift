//
//  EngineViewModel.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import Foundation
import SwiftUI
import Combine

/// Convert manifold pressure (gauge inches of mercury, ≤ 0 for vacuum) to
/// absolute kPa — the conventional Y axis on a tuner's fuel/spark map.
private func manifoldPressureToAbsoluteKpa(_ gaugeInHg: Double) -> Double {
    let kPaPerInHg = 3.386389
    let atmKpa = 101.325
    let absolute = atmKpa + gaugeInHg * kPaPerInHg
    return max(10.0, min(absolute, 250.0))
}

// Rev ramp smoothing: each polling tick the throttle moves this fraction of
// the remaining distance toward its target, so revs ease in and out smoothly.
private let revAveragingFactor: Double = 0.35
// Throttle below this is treated as fully idle and snapped to zero.
private let revIdleThreshold: Double = 0.001
// Native clutchPressure ≥ this means the clutch is engaged (power flows);
// "pressed" in the UI is the inverse — the pedal is down so the clutch is disengaged.
private let clutchEngagedThreshold: Double = 0.5
// Fallback gear count used when no spec is available for the active engine.
private let defaultGearCount: Int = 6
// Fallback cylinders-per-bank when no spec is available (typical 4-cyl bank).
private let defaultCylindersPerBank: Int = 4
// rpm above which (with ignition on) the engine counts as "running" — used to
// stamp runningSince so diagnostics can grace start-up transients.
private let engineRunningRpmFloor: Double = 400.0
// Map roughness (mean adjacent-cell gap) above which a tune is "jagged" enough
// to destabilise the engine, plus the extra roughness over that mapping to full
// chaos. Fuel is in AFR, ignition in degrees, so they're scaled separately. A
// factory/smooth tune sits well under both thresholds.
private let fuelRoughnessThreshold: Double = 2.0
private let fuelRoughnessSpan: Double = 5.0
private let ignitionRoughnessThreshold: Double = 6.0
private let ignitionRoughnessSpan: Double = 25.0
// Peak disturbance at full chaos. The spark swing is the heavy hitter — ±28°
// drags timing into deep retard (torque collapses, rpm sags) and back, so the
// engine bucks and you struggle to keep it lit. Fuel is surged in parallel
// across a misfire-lean / flood-rich band so the mixture lurches too.
private let ignitionChaosAmplitudeDeg: Double = 28.0
private let fuelChaosAmplitude: Double = 0.9
private let chaosTrimMin: Double = 0.25
private let chaosTrimMax: Double = 1.80

class EngineViewModel: ObservableObject {
    private var engine: EngineWrapper?

    // Live Data
    @Published var rpm: Double = 0.0
    @Published var gear: Int = 0 // 0=Neutral, -1=Reverse, 1-6=Gears
    @Published var isIgnitionOn: Bool = false
    @Published var isStarterOn: Bool = false

    /// Wall-clock time the engine last began running (ignition on + rpm above
    /// the running floor), or nil while it isn't running. Diagnostics read this
    /// to grace start-up transients — e.g. oil pressure that hasn't built yet —
    /// rather than firing a fault the instant the engine catches.
    @Published var runningSince: Date? = nil
    @Published var vehicleSpeed: Double = 0.0
    @Published var distanceTravelled: Double = 0.0
    @Published var fuelConsumed: Double = 0.0
    @Published var redline: Double
    /// Mirror of EngineLibrary.shared.selectedEngineId. Views that need to
    /// hard-reset when the engine changes can use `.id(engineVm.engineId)`.
    @Published var engineId: UUID?

    /// Set when the most-recent engine load failed (compile error / null
    /// engine). RootView observes this to surface a user-facing alert. Carries
    /// the name of the engine that failed so the alert can reference it.
    @Published var failedEngineName: String?

    /// User-editable 2D ignition + fuel maps. Sampled at the current
    /// operating point (RPM × MAP load) on every polling tick and pushed
    /// into the C++ engine via setIgnitionOffset / setFuelTrim — the EcuTuningView
    /// renders + edits this in-place.
    @Published var ecu: EcuTuneModel

    // Dynamometer sweep
    @Published var dynoEnabled: Bool = false

    /// Captured best results (dyno peaks + launch times) for the active engine,
    /// used to post to the leaderboard. Reset whenever the engine changes.
    let runResults = RunResultsStore()

    // Throttle hold: latches the throttle so it stops decaying back to idle
    @Published var throttleHeld: Bool = false

    // Rev-engine ramp state
    private var revTarget: Double = 0.0
    private var revActive: Bool = false

    // Gauge Data
    @Published var manifoldPressure: Double = 0.0      // inHg (gauge pressure)
    @Published var intakeFlowRate: Double = 0.0        // SCFM
    @Published var volumetricEfficiency: Double = 0.0  // Percentage (calculated)
    @Published var cylinderPressure: Double = 0.0      // PSI
    @Published var intakeAFR: Double = 0.0             // Air-Fuel Ratio
    @Published var exhaustO2: Double = 0.0             // O2 percentage
    
    // ECU Tuning Data
    @Published var ignitionOffset: Double = 0.0
    @Published var fuelTrim: Double = 1.0
    /// Live tune-chaos level (0 = stable, 1 = maximally jagged) currently being
    /// applied. Drives the ECU map's live-cell jitter so a bad tune is visible
    /// on the grid, not just in the readouts. Zero whenever the engine is off.
    @Published var tuneChaosLevel: Double = 0.0
    @Published var ignitionMap: [ScopePoint] = []

    // Thermal + damage state
    @Published var coolantTempC: Double = 90.0
    @Published var oilTempC: Double = 80.0
    @Published var oilPressurePsi: Double = 0.0
    @Published var coolantPumpOn: Bool = true
    @Published var oilPumpOn: Bool = true
    @Published var topEndHealth: Double = 1.0
    @Published var midHealth: Double = 1.0
    @Published var bottomEndHealth: Double = 1.0
    @Published var cylinderHealths: [CylinderHealthState] = []
    @Published var engineWideHealth: EngineWideHealthState = EngineWideHealthState()
    @Published var rodKnocking: Bool = false

    /// Bumped every time the engine is repaired. Views holding stored state
    /// (e.g. the OBD2 scanner's accumulated trouble-code log) observe this to
    /// reset themselves, since a repair clears every fault at once.
    @Published var repairToken: Int = 0

    /// Per-cylinder spark state. Index i is `true` while cylinder i fires,
    /// `false` when the user has cut ignition to it from the Cylinder Control
    /// tile. Mirrors the C++ ignition module each poll.
    @Published var cylinderIgnitionEnabled: [Bool] = []
    
    // Inputs
    @Published var throttlePosition: Double = 0.0 {
        didSet { engine?.setThrottle(throttlePosition) }
    }
    
    @Published var clutchPressed: Bool = true

    /// Native clutch engagement (0.0 = fully disengaged, 1.0 = fully engaged).
    /// Source of truth for both the cross-section visualizer and the
    /// precision slider. `clutchPressed` is derived from this on each poll.
    @Published var clutchPressure: Double = 0.0

    /// Number of forward gears available on the active engine's transmission.
    /// Sourced from the EngineSpec when present; falls back to defaultGearCount
    /// for built-ins with no editable spec.
    @Published var gearCount: Int = defaultGearCount

    /// Final-drive ratio per forward gear (1st → top). Lets driver-tool tiles
    /// (shift light, etc.) reason about post-shift RPM without going back
    /// through EngineLibrary every frame.
    @Published var gearRatios: [Double] = []

    /// Runners per bank — how many intake runners are visualized on the
    /// manifold cross-section. cylinderCount / bankCount.
    @Published var cylindersPerBank: Int = defaultCylindersPerBank

    /// Set by setGear() to the gear the user just selected. Polling will not
    /// overwrite `gear` until the native side reports the same value — this
    /// prevents the shifter from snapping back through old states while the
    /// sim thread catches up.
    private var pendingGear: Int?

    /// Latched once the starter has been auto-cut at the moment a cylinder
    /// seizes, so we cut it exactly once — the user is then free to re-engage
    /// it. Cleared when the engine is no longer seized (repair / swap) so a
    /// fresh failure re-arms the one-shot.
    private var autoKilledStarterOnSeizure = false

    /// Count of consecutive polling ticks where pollState returned nil while
    /// an engine is supposedly mounted. Used to surface the load-failure
    /// alert when the sim thread silently produces nothing (e.g. crashed on
    /// its first step) but loadSucceeded was already set true.
    private var emptyPollStreak: Int = 0
    /// 30 Hz polling means ~30 ticks per second; ~60 ticks ≈ 2 s with no
    /// state is plenty of evidence the sim isn't actually running.
    private static let stalledPollLimit: Int = 60
    /// Friendly name of the most-recently-loaded engine, used when we have
    /// to surface a "load failed" alert after stall detection.
    private var mostRecentEngineName: String?

    let oscilloscopeManager: OscilloscopeManager
    private var timer: Timer?
    private var selectionCancellable: AnyCancellable?
    private var ecuCancellables = Set<AnyCancellable>()

    init(oscillioscopeManager: OscilloscopeManager) {
        self.oscilloscopeManager = oscillioscopeManager
        let initialEntry = EngineLibrary.shared.selectedEntry
        let newEngine = initialEntry.map { EngineWrapper(mrPath: $0.mrPath) } ?? EngineWrapper()
        self.engine = newEngine
        self.redline = newEngine?.getEngineRedline() ?? 6500.0
        self.engineId = EngineLibrary.shared.selectedEngineId
        self.gearCount = initialEntry.map(Self.gearCount(for:)) ?? defaultGearCount
        self.gearRatios = initialEntry.flatMap { $0.effectiveSpec?.gearRatios } ?? []
        self.cylindersPerBank = initialEntry.map(Self.cylindersPerBank(for:)) ?? defaultCylindersPerBank
        self.ecu = Self.makeEcuModel(for: newEngine)
        self.mostRecentEngineName = initialEntry?.name
        if let engine = newEngine, !engine.loadSucceeded {
            self.failedEngineName = initialEntry?.name ?? "engine"
        }
        // Bind to the freshly-built ECU so edits push through immediately
        // rather than waiting for the next 30 Hz polling tick.
        bindToEcu()

        // Rebuild the EngineWrapper whenever the user picks a different engine.
        self.selectionCancellable = EngineLibrary.shared.$selectedEngineId
            .dropFirst()
            .sink { [weak self] newId in
                guard let self = self, let id = newId,
                      let entry = EngineLibrary.shared.entry(for: id) else { return }
                self.swapEngine(to: entry)
            }

        // Setup Polling Timer (30 Hz) that runs even during UI interactions
        let timer = Timer(timeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self, let engine = self.engine else { return }
            
            if let state = engine.pollState() {
                self.emptyPollStreak = 0
                self.rpm = state.rpm
                self.applyPolledGear(Int(state.gear))
                self.clutchPressure = state.clutchPressure
                self.clutchPressed = state.clutchPressure < clutchEngagedThreshold
                self.isIgnitionOn = state.isIgnitionOn
                self.isStarterOn = state.isStarterOn
                // Stamp the moment the engine catches and clear it when it
                // stops, so diagnostics can measure how long it's been running.
                let running = state.isIgnitionOn && state.rpm > engineRunningRpmFloor
                self.runningSince = running ? (self.runningSince ?? Date()) : nil
                self.vehicleSpeed = state.vehicleSpeed
                self.distanceTravelled = state.distanceTravelled
                self.fuelConsumed = state.fuelConsumed
                self.dynoEnabled = state.dynoEnabled

                // Gauge data
                self.manifoldPressure = state.manifoldPressure
                self.intakeFlowRate = state.intakeFlowRate
                self.volumetricEfficiency = state.volumetricEfficiency
                self.cylinderPressure = state.cylinderPressure
                self.intakeAFR = state.intakeAFR
                self.exhaustO2 = state.exhaustO2

                // Tuning data
                self.ignitionOffset = state.ignitionOffset
                self.fuelTrim = state.fuelTrim
                self.ignitionMap = state.ignitionMap

                // Thermal + damage
                self.coolantTempC = state.coolantTempC
                self.oilTempC = state.oilTempC
                self.oilPressurePsi = state.oilPressurePsi
                self.coolantPumpOn = state.coolantPumpOn
                self.oilPumpOn = state.oilPumpOn
                self.topEndHealth = state.topEndHealth
                self.midHealth = state.midHealth
                self.bottomEndHealth = state.bottomEndHealth
                self.cylinderHealths = state.cylinderHealths ?? []
                if let wide = state.engineWideHealth {
                    self.engineWideHealth = wide
                }
                self.rodKnocking = state.rodKnocking
                self.cylinderIgnitionEnabled =
                    (state.cylinderIgnitionEnabled ?? []).map { $0.boolValue }

                // Crash haptics: a strong one-shot kick when a damaging
                // money-shift fires, then a continuous rumble that tracks the
                // live crash-audio envelope so the haptic follows the sound.
                if state.moneyshiftJustFired {
                    HapticManager.shared.beginMoneyshift(severity: state.moneyshiftSeverity)
                }
                HapticManager.shared.updateMoneyshift(level: state.catastropheHapticLevel,
                                                      peak: state.catastropheHapticPeak)

                // A seized cylinder means the engine has mechanically failed.
                // Cut the starter once at the moment of failure (cranking a
                // locked engine just grinds it); after that one-shot the user
                // is free to re-engage the starter. The latch re-arms once the
                // engine is no longer seized.
                let anySeized = (state.cylinderHealths ?? []).contains(where: { $0.seized })
                if anySeized {
                    if state.isStarterOn && !self.autoKilledStarterOnSeizure {
                        self.toggleStarter()
                        self.isStarterOn = false
                    }
                    self.autoKilledStarterOnSeizure = true
                } else {
                    self.autoKilledStarterOnSeizure = false
                }

                // Pass engine wrapper to oscilloscope manager for sampling
                self.oscilloscopeManager.sample(from: engine)

                // Track dyno-sweep peaks for the leaderboard. The power/torque
                // scopes only carry data while sweeping, so this is a no-op
                // outside a dyno run.
                self.runResults.ingestDyno(power: self.oscilloscopeManager.power,
                                           torque: self.oscilloscopeManager.torque,
                                           dynoActive: state.dynoEnabled)

                // Sample the user's ECU maps at the live operating point and
                // push the resulting offset/trim into the engine.
                self.applyEcuTune(engine: engine)
            } else if self.failedEngineName == nil {
                // pollState returning nil means the simulator hasn't produced
                // a frame yet. If we go many ticks in a row with no state
                // while we believe the engine is loaded, treat it as a
                // silently-stalled load and surface the error.
                self.emptyPollStreak += 1
                if self.emptyPollStreak >= Self.stalledPollLimit,
                   let name = self.mostRecentEngineName {
                    self.failedEngineName = name
                }
            }

            self.advanceRevRamp()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    
    // Tuning Methods
    func setIgnitionOffset(_ offset: Double) {
        engine?.setIgnitionOffset(offset)
        ignitionOffset = offset
    }

    func setFuelTrim(_ trim: Double) {
        engine?.setFuelTrim(trim)
        fuelTrim = trim
    }

    /// Read the live operating point, look the absolute spark advance + fuel
    /// trim out of the ECU maps, and push them into the C++ engine. Since
    /// the engine's own timing curve already supplies a base, we send only
    /// the delta (mapValue − baseAtRpm) — the engine then computes
    /// total = base + delta which equals the map value. Single source of
    /// truth: the cell.
    private func applyEcuTune(engine: EngineWrapper) {
        let loadKpa = manifoldPressureToAbsoluteKpa(manifoldPressure)
        let targetAdvance = ecu.ignitionAdvance(rpm: rpm, loadKpa: loadKpa)
        let baseAdvance = ecu.baseTiming(at: rpm)
        var delta = targetAdvance - baseAdvance
        var trim = ecu.fuelTrim(rpm: rpm, loadKpa: loadKpa)

        // A jagged map runs the engine erratically. Fuel trim alone has weak
        // torque authority at idle, so the dominant disturbance is a violent,
        // ever-shifting swing in spark timing — yanking it deep into retard
        // kills torque and the rpm sags, then it snaps back, so the engine
        // bucks and hunts and you fight to keep it lit. The fuel trim is surged
        // in parallel (out of phase) so the mixture lurches too.
        //
        // Only while the engine is actually running: the surge is time-based,
        // so applying it with the engine off would leave ADV / Δ / trim (and the
        // spark chart) oscillating on a dead, stationary car.
        let chaos = (runningSince != nil) ? tuneChaos() : 0.0
        if chaos > 0 {
            let t = Date().timeIntervalSinceReferenceDate
            delta += chaosWave(t, phase: 0.0) * chaos * ignitionChaosAmplitudeDeg
            trim += chaosWave(t, phase: 2.3) * chaos * fuelChaosAmplitude
            trim = min(chaosTrimMax, max(chaosTrimMin, trim))
        }
        if tuneChaosLevel != chaos { tuneChaosLevel = chaos }

        engine.setIgnitionOffset(delta)
        engine.setFuelTrim(trim)
        ecu.recordSample(rpm: rpm, loadKpa: loadKpa)
    }

    /// 0 (clean tune) → 1 (wildly jagged). Whichever map is more broken wins,
    /// so corrupting either the fuel or the ignition tab destabilises the engine.
    private func tuneChaos() -> Double {
        let fuel = chaosFraction(ecu.fuelMapRoughness(),
                                 threshold: fuelRoughnessThreshold, span: fuelRoughnessSpan)
        let ignition = chaosFraction(ecu.ignitionMapRoughness(),
                                     threshold: ignitionRoughnessThreshold, span: ignitionRoughnessSpan)
        return max(fuel, ignition)
    }

    private func chaosFraction(_ roughness: Double, threshold: Double, span: Double) -> Double {
        guard roughness > threshold else { return 0 }
        return min(1.0, (roughness - threshold) / span)
    }

    /// Erratic wave in roughly [-1, 1]. Summed incommensurate sines divided by
    /// less than their count, so it saturates at the rails often — the engine
    /// spends real time pinned lean/retarded rather than gently wobbling.
    private func chaosWave(_ t: Double, phase: Double) -> Double {
        let s = sin(t * 5.0 + phase)
              + sin(t * 12.1 + phase * 1.7)
              + sin(t * 8.3 + phase * 0.5)
        return max(-1.0, min(1.0, s / 2.0))
    }
    
    deinit {
        timer?.invalidate()
        engine?.shutdown()
    }

    /// Tear down the current EngineWrapper and bring up a fresh one bound to
    /// the selected entry's .mr file. Resets transient UI state so the gauges
    /// don't carry stale values across the swap.
    private func swapEngine(to entry: EngineEntry) {
        engine?.shutdown()
        engine = nil

        // Captured leaderboard results belong to the outgoing engine.
        runResults.resetForEngineChange()

        // Reset transient state so old values don't bleed through during the swap.
        rpm = 0
        gear = 0
        isIgnitionOn = false
        isStarterOn = false
        runningSince = nil
        autoKilledStarterOnSeizure = false
        vehicleSpeed = 0
        distanceTravelled = 0
        fuelConsumed = 0
        throttlePosition = 0
        throttleHeld = false
        revActive = false
        revTarget = 0

        let newEngine = EngineWrapper(mrPath: entry.mrPath)
        engine = newEngine
        redline = newEngine?.getEngineRedline() ?? 6500.0
        engineId = entry.id
        gearCount = Self.gearCount(for: entry)
        gearRatios = entry.effectiveSpec?.gearRatios ?? []
        cylindersPerBank = Self.cylindersPerBank(for: entry)
        pendingGear = nil
        // Rebuild the ECU map: bin range + seed values come from the new
        // engine's redline and base timing curve.
        ecu = Self.makeEcuModel(for: newEngine)
        bindToEcu()

        // Surface load failures so the UI can prompt the user to pick a
        // different engine instead of silently sitting on a dead simulator.
        mostRecentEngineName = entry.name
        emptyPollStreak = 0
        failedEngineName = (newEngine?.loadSucceeded == true) ? nil : entry.name
    }

    /// Build an EcuTuneModel seeded from the engine's current redline and
    /// base spark-advance curve. The model captures the curve values at init
    /// time so the user gets to see real timing numbers in every cell instead
    /// of a sea of 0°.
    private static func makeEcuModel(for engine: EngineWrapper?) -> EcuTuneModel {
        let redline = engine?.getEngineRedline() ?? 6500.0
        let provider: EcuBaseTimingProvider = { [weak engine] rpm in
            return engine?.getBaseTimingAdvance(forRpm: rpm) ?? 0.0
        }
        return EcuTuneModel(redlineRpm: redline, baseTiming: provider)
    }

    /// Subscribe to ECU map changes so that edits push to the C++ engine on
    /// the next runloop tick instead of waiting for the 30 Hz polling cycle.
    private func bindToEcu() {
        ecuCancellables.removeAll()
        Publishers.CombineLatest(ecu.$ignitionMap, ecu.$fuelMap)
            .dropFirst()  // initial publish on subscribe — no engine call yet
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, let engine = self.engine else { return }
                self.applyEcuTune(engine: engine)
            }
            .store(in: &ecuCancellables)
    }

    /// Forward gear count for the entry, preferring the editable spec and
    /// falling back to the canned built-in spec when present.
    private static func gearCount(for entry: EngineEntry) -> Int {
        entry.effectiveSpec?.gearRatios.count ?? defaultGearCount
    }

    /// Cylinders per bank for the entry, derived from the engine layout.
    private static func cylindersPerBank(for entry: EngineEntry) -> Int {
        guard let layout = entry.effectiveSpec?.layout else { return defaultCylindersPerBank }
        let banks = max(layout.bankCount, 1)
        return max(1, layout.cylinderCount / banks)
    }

    /// Adopt the gear value reported by polling, unless we're still waiting
    /// for the native side to catch up to a user-initiated shift.
    private func applyPolledGear(_ polled: Int) {
        if let pending = pendingGear {
            if polled == pending {
                pendingGear = nil
                gear = polled
            }
            // Else: keep the locally-set gear; the next poll will reconcile.
        } else {
            gear = polled
        }
    }

    func toggleIgnition() { engine?.toggleIgnition() }
    func toggleStarter() { engine?.toggleStarter() }

    func toggleDyno() {
        let newValue = !dynoEnabled
        engine?.setDynoEnabled(newValue)
        dynoEnabled = newValue

        // Drop into neutral on enable so the dyno isn't fighting the drivetrain;
        // the run reads only what the engine itself can produce.
        if newValue { setGear(-1) }
    }

    /// Latches the throttle at its current position so it no longer decays.
    func toggleHold() {
        throttleHeld.toggle()
        if throttleHeld {
            revActive = false   // freeze any in-progress rev ramp
        }
    }

    /// Begin revving: throttle eases toward full while the rev key is held.
    /// Manual revving overrides and cancels throttle hold.
    func beginRev() {
        throttleHeld = false
        revTarget = 1.0
        revActive = true
    }

    /// Release the rev key: throttle eases back down toward idle.
    func endRev() {
        revTarget = 0.0
    }

    /// Eases the throttle toward the current rev target. Runs every polling
    /// tick while a rev is in progress; stops once idle is reached.
    private func advanceRevRamp() {
        guard revActive else { return }

        throttlePosition += revAveragingFactor * (revTarget - throttlePosition)

        if revTarget == 0.0 && throttlePosition < revIdleThreshold {
            throttlePosition = 0.0
            revActive = false
        }
    }
    /// Dismiss the "engine failed to load" alert without changing the
    /// selected engine. The user can then re-pick a working one from the
    /// sidebar.
    func acknowledgeEngineLoadError() {
        failedEngineName = nil
        emptyPollStreak = 0
    }

    func toggleClutch() {
        // Optimistically flip locally so the UI responds instantly; the next
        // poll authoritatively re-syncs from the native clutchPressure.
        clutchPressed.toggle()
        clutchPressure = clutchPressed ? 0.0 : 1.0
        engine?.toggleClutch()
    }

    /// Drives the native clutch pressure continuously (0 = disengaged,
    /// 1 = engaged). Used by the precision slider in the UI.
    func setClutchPressure(_ pressure: Double) {
        let clamped = min(max(pressure, 0.0), 1.0)
        clutchPressure = clamped
        clutchPressed = clamped < clutchEngagedThreshold
        engine?.setClutchPressure(clamped)
    }

    // New function to support H-Shifter
    func setGear(_ newGear: Int) {
        engine?.setGear(Int32(newGear))
        gear = newGear
        pendingGear = newGear
    }
    
    // Keep these for legacy compatibility if needed
    func shiftUp() { engine?.shiftUp() }
    func shiftDown() { engine?.shiftDown() }
    func resetStats() {
        engine?.resetTravelledDistance()
        engine?.resetFuelConsumption()
    }

    // --- Thermal + damage controls ---
    func toggleCoolantPump() {
        let next = !coolantPumpOn
        engine?.setCoolantPumpEnabled(next)
        coolantPumpOn = next
    }
    func toggleOilPump() {
        let next = !oilPumpOn
        engine?.setOilPumpEnabled(next)
        oilPumpOn = next
    }
    func repairEngine() {
        engine?.repairEngine()
        repairToken &+= 1
        HapticManager.shared.tap(.success)
    }

    /// Cut or restore spark to a single cylinder. Optimistically flips the
    /// local flag so the switch responds instantly; the next poll re-syncs
    /// authoritatively from the C++ ignition module.
    func toggleCylinderIgnition(_ index: Int) {
        guard index >= 0 && index < cylinderIgnitionEnabled.count else { return }
        let next = !cylinderIgnitionEnabled[index]
        engine?.setCylinderIgnitionEnabled(Int32(index), enabled: next)
        cylinderIgnitionEnabled[index] = next
    }
}
