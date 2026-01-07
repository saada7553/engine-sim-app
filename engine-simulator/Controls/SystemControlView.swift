//
//  SystemControlView.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import SwiftUI

struct SystemControlView: View {
    @ObservedObject var vm: EngineViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            ControlButton(label: "IGNITION", active: vm.isIgnitionOn, color: .red) { vm.toggleIgnition() }
            ControlButton(label: "STARTER", active: vm.isStarterOn, color: .orange) { vm.toggleStarter() }
            ControlButton(label: "CLUTCH", active: vm.clutchPressed, color: .blue) { vm.toggleClutch() }
        }
    }
}
