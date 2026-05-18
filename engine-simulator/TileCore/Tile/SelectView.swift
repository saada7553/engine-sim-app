//
//  SelectView.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import SwiftUI

struct SelectView: View {
    @ObservedObject var tile: TileViewModel

    // Grouped tile types for organized selection
    private let visualizationTypes: [TileType] = [.engine3DView]

    private let gaugeTypes: [TileType] = [
        .speedometerGauge, .rpmGauge, .manifoldPressureGauge,
        .volumetricEfficiencyGauge, .airScfmGauge, .intakeAfrGauge,
        .exhaustO2Gauge, .cylinderPressureGauge
    ]

    private let controlTypes: [TileType] = [.engineControls]

    private let oscilloscopeTypes: [TileType] = [
        .torqueOscilloscope, .powerOscilloscope, .dynoOscilloscope,
        .sparkAdvanceOscilloscope, .totalExhaustFlowOscilloscope,
        .exhaustFlowOscilloscope, .intakeFlowOscilloscope, .flowOscilloscope,
        .exhaustValveLiftOscilloscope, .intakeValveLiftOscilloscope,
        .valveLiftOscilloscope, .cylinderPressureOscilloscope,
        .cylinderMoleculesOscilloscope, .pvOscilloscope
    ]

    var body: some View {
        List {
            Section(header: Text("Visualizations")) {
                ForEach(visualizationTypes) { type in
                    tileButton(for: type)
                }
            }

            Section(header: Text("Gauges")) {
                ForEach(gaugeTypes) { type in
                    tileButton(for: type)
                }
            }

            Section(header: Text("Controls")) {
                ForEach(controlTypes) { type in
                    tileButton(for: type)
                }
            }

            Section(header: Text("Oscilloscopes")) {
                ForEach(oscilloscopeTypes) { type in
                    tileButton(for: type)
                }
            }
        }
        .listStyle(PlainListStyle())
        .background(Color.appBackground)
    }

    private func tileButton(for type: TileType) -> some View {
        Button(action: {
            tile.data.type = type
        }) {
            Text(type.rawValue)
                .foregroundColor(.white)
        }
    }
}
