////
////  ContentView.swift
////  engine-simulator
////
////  Created by Saad Ata on 12/30/25.
////
//
//import SwiftUI
//import Combine
//
//// MARK: - 3. Main Layout
//struct ContentView: View {
//    @StateObject var osManager: OscilloscopeManager
//    @StateObject var vm: EngineViewModel
//    
//    init(osManager: OscilloscopeManager = OscilloscopeManager()) {
//        self._osManager = StateObject(wrappedValue: osManager)
//        self._vm = StateObject(wrappedValue: EngineViewModel(oscillioscopeManager: osManager))
//    }
//    
//    var body: some View {
//        ZStack {
//            Color.black.edgesIgnoringSafeArea(.all)
//            
//            VStack(spacing: 0) {
//                // MARK: Top Bar
//                HStack {
//                    Text("ENGINE CONTROLLER")
//                        .modifier(RetroFont(size: 16))
//                        .foregroundColor(.white)
//                    Spacer()
//                    Text("BUILD V0.3 // A.G.")
//                        .modifier(RetroFont(size: 10))
//                        .foregroundColor(.gray)
//                }
//                .padding()
//                .background(Color.white.opacity(0.05))
//                .border(Color.white.opacity(0.1), width: 1, edges: [.bottom])
//                
//                HStack(alignment: .top, spacing: 10) {
//                    
//                    // MARK: LEFT COL - Controls
//                    VStack(spacing: 10) {
//                        RetroPanel("SYSTEM") {
//                            SystemControlView(vm: vm)
//                        }
//                        
//                        RetroPanel("TRANSMISSION") {
//                            GearShiftView(vm: vm)
//                        }
//                        
//                        Spacer()
//                    }
//                    .frame(width: 220)
//                    
//                    // MARK: CENTER COL - Viewport
//                    VStack(spacing: 10) {
//                        RetroPanel("VISUALIZATION") {
////                            Engine3DView(vm: en)
////                                .frame(maxWidth: .infinity, maxHeight: .infinity)
////                                .background(Color.black)
//                        }
//                        
//                        RetroPanel("RPM ANALYSIS") {
////                            OscilloscopeView(model: vm.rpmOscilloscope, color: .red)
////                                .frame(maxWidth: .infinity, maxHeight: .infinity)
//                            CylinderPressureOscilloscopeView(manager: osManager)
//                        }
//                        
//                        RetroPanel("INPUT") {
//                            ThrottleView(vm: vm)
//                                .padding(.horizontal, 4)
//                        }
//                        .frame(height: 40)
//                    }
//                    
//                    // MARK: RIGHT COL - Instruments
//                    VStack(spacing: 10) {
////                        RetroPanel("TACHOMETER") {
////                            UniversalGauge(
////                                value: $vm.rpm,
////                                maxValue: vm.redline,
////                                label: "X1000 RPM",
////                                units: "",
////                                color: .red,
////                                isRPM: true
////                            )
////                            .frame(height: 150)
////                        }
////                        
////                        RetroPanel("SPEEDOMETER") {
////                            // Convert m/s to km/h (approx * 3.6)
////                            UniversalGauge(
////                                value: $vm.vehicleSpeed,
////                                maxValue: 260.0,
////                                label: "VELOCITY",
////                                units: "KM/H",
////                                color: .orange
////                            )
////                            .frame(height: 150)
////                        }
//                        
//                        RetroPanel("TELEMETRY") {
//                            VStack(spacing: 6) {
//                                DataRow(label: "FUEL", value: String(format: "%.2f L", vm.fuelConsumed))
//                                DataRow(label: "DIST", value: String(format: "%.1f KM", vm.distanceTravelled))
//                            }
//                        }
//                        
//                        Spacer()
//                    }
//                    .frame(width: 200)
//                }
//                .padding(10)
//            }
//            .frame(maxWidth: .infinity, maxHeight: .infinity)
//        }
//    }
//}
//
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//            .frame(width: 900, height: 600)
//    }
//}
