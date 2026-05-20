//
//  EngineViewModel.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import Foundation
import SwiftUI
import Combine

// Rev ramp smoothing: each polling tick the throttle moves this fraction of
// the remaining distance toward its target, so revs ease in and out smoothly.
private let revAveragingFactor: Double = 0.35
// Throttle below this is treated as fully idle and snapped to zero.
private let revIdleThreshold: Double = 0.001

class EngineViewModel: ObservableObject {
    private var engine: EngineWrapper?

    // Live Data
    @Published var rpm: Double = 0.0
    @Published var gear: Int = 0 // 0=Neutral, -1=Reverse, 1-6=Gears
    @Published var isIgnitionOn: Bool = false
    @Published var isStarterOn: Bool = false
    @Published var vehicleSpeed: Double = 0.0
    @Published var distanceTravelled: Double = 0.0
    @Published var fuelConsumed: Double = 0.0
    @Published var redline: Double

    // Dynamometer sweep
    @Published var dynoEnabled: Bool = false

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
    @Published var ignitionMap: [ScopePoint] = []
    
    // Inputs
    @Published var throttlePosition: Double = 0.0 {
        didSet { engine?.setThrottle(throttlePosition) }
    }
    
    @Published var clutchPressed: Bool = true
    
    let oscilloscopeManager: OscilloscopeManager
    private var timer: Timer?
    private var selectionCancellable: AnyCancellable?

    init(oscillioscopeManager: OscilloscopeManager) {
        self.oscilloscopeManager = oscillioscopeManager
        let initialPath = EngineLibrary.shared.selectedEntry?.mrPath
        let newEngine = initialPath.map { EngineWrapper(mrPath: $0) } ?? EngineWrapper()
        self.engine = newEngine
        self.redline = newEngine?.getEngineRedline() ?? 6500.0

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
                self.rpm = state.rpm
                self.gear = Int(state.gear)
                self.isIgnitionOn = state.isIgnitionOn
                self.isStarterOn = state.isStarterOn
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

                // Pass engine wrapper to oscilloscope manager for sampling
                self.oscilloscopeManager.sample(from: engine)
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

        // Reset transient state so old values don't bleed through during the swap.
        rpm = 0
        gear = 0
        isIgnitionOn = false
        isStarterOn = false
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
    func toggleClutch() {
        clutchPressed.toggle()
        engine?.toggleClutch()
    }
    
    // New function to support H-Shifter
    func setGear(_ newGear: Int) {
        engine?.setGear(Int32(newGear))
        // Manually update local state for instant UI feedback
        self.gear = newGear
    }
    
    // Keep these for legacy compatibility if needed
    func shiftUp() { engine?.shiftUp() }
    func shiftDown() { engine?.shiftDown() }
    func resetStats() {
        engine?.resetTravelledDistance()
        engine?.resetFuelConsumption()
    }
}
