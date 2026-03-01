//
//  EngineViewModel.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import Foundation
import SwiftUI
import Combine

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

    // Gauge Data
    @Published var manifoldPressure: Double = 0.0      // inHg (gauge pressure)
    @Published var intakeFlowRate: Double = 0.0        // SCFM
    @Published var volumetricEfficiency: Double = 0.0  // Percentage (calculated)
    @Published var cylinderPressure: Double = 0.0      // PSI
    @Published var intakeAFR: Double = 0.0             // Air-Fuel Ratio
    @Published var exhaustO2: Double = 0.0             // O2 percentage
    
    // Inputs
    @Published var throttlePosition: Double = 0.0 {
        didSet { engine?.setThrottle(throttlePosition) }
    }
    
    @Published var clutchPressed: Bool = true
    
    let oscilloscopeManager: OscilloscopeManager
    private var timer: Timer?
    
    init(oscillioscopeManager: OscilloscopeManager) {
        self.oscilloscopeManager = oscillioscopeManager
        let newEngine = EngineWrapper()
        self.engine = newEngine
        self.redline = newEngine?.getEngineRedline() ?? 6500.0
        
        // Setup Polling Timer (30 Hz)
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self, let engine = self.engine else { return }
            
            if let state = engine.pollState() {
                self.rpm = state.rpm
                self.gear = Int(state.gear)
                self.isIgnitionOn = state.isIgnitionOn
                self.isStarterOn = state.isStarterOn
                self.vehicleSpeed = state.vehicleSpeed
                self.distanceTravelled = state.distanceTravelled
                self.fuelConsumed = state.fuelConsumed

                // Gauge data (calculated in C++ with proper engine values)
                self.manifoldPressure = state.manifoldPressure
                self.intakeFlowRate = state.intakeFlowRate
                self.volumetricEfficiency = state.volumetricEfficiency
                self.cylinderPressure = state.cylinderPressure
                self.intakeAFR = state.intakeAFR
                self.exhaustO2 = state.exhaustO2

                // Pass engine wrapper to oscilloscope manager for sampling
                self.oscilloscopeManager.sample(from: engine)
            }
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    func toggleIgnition() { engine?.toggleIgnition() }
    func toggleStarter() { engine?.toggleStarter() }
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
