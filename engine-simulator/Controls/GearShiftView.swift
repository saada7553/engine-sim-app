//
//  GearShiftView.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import SwiftUI

struct GearShiftView: View {
    @ObservedObject var vm: EngineViewModel
    
    var body: some View {
        VStack {
            HPatternShifter(currentGear: $vm.gear) { newGear in
                vm.setGear(newGear)
            }
            Text(vm.gear == 0 ? "NEUTRAL" : (vm.gear == -1 ? "REVERSE" : "GEAR \(vm.gear)"))
                .modifier(RetroFont(size: 10))
                .foregroundColor(vm.gear == 0 ? .green : .orange)
        }
    }
}

// 2.2 H-Pattern Shifter
struct HPatternShifter: View {
    @Binding var currentGear: Int // -1 = R, 0 = N, 1-6
    var action: (Int) -> Void
    
    let gridItems = [
        GridItem(.flexible()), // Col 1: R / 2
        GridItem(.flexible()), // Col 2: 1 / 3
        GridItem(.flexible()), // Col 3: 3 / 4
        GridItem(.flexible())  // Col 4: 5 / 6
    ]
    
    var body: some View {
        ZStack {
            // The "Gate" Lines
            HStack(spacing: 0) {
                Divider().background(Color.white.opacity(0.2))
                Spacer()
                Divider().background(Color.white.opacity(0.2))
                Spacer()
                Divider().background(Color.white.opacity(0.2))
                Spacer()
                Divider().background(Color.white.opacity(0.2))
            }
            .frame(height: 50)
            .padding(.horizontal, 25)
            
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1)
            
            // The Knobs
            VStack(spacing: 20) {
                // Top Row: R, 1, 3, 5
                HStack(spacing: 15) {
                    GearButton(label: "R", gearIdx: -1, current: currentGear, action: action)
                    GearButton(label: "1", gearIdx: 1, current: currentGear, action: action)
                    GearButton(label: "3", gearIdx: 3, current: currentGear, action: action)
                    GearButton(label: "5", gearIdx: 5, current: currentGear, action: action)
                }
                
                // Bottom Row: -, 2, 4, 6
                HStack(spacing: 15) {
                    // Spacer for Reverse lockout area
                    Circle().fill(Color.clear).frame(width: 35, height: 35)
                    GearButton(label: "2", gearIdx: 2, current: currentGear, action: action)
                    GearButton(label: "4", gearIdx: 4, current: currentGear, action: action)
                    GearButton(label: "6", gearIdx: 6, current: currentGear, action: action)
                }
            }
        }
        .padding(10)
    }
}

struct GearButton: View {
    var label: String
    var gearIdx: Int
    var current: Int
    var action: (Int) -> Void
    
    var isActive: Bool { current == gearIdx }
    
    var body: some View {
        Button(action: {
            // Toggle Neutral if clicking active gear, else set gear
            if isActive { action(0) } else { action(gearIdx) }
        }) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.orange : Color.black)
                    .overlay(Circle().stroke(isActive ? Color.white : Color.gray, lineWidth: 1))
                
                Text(label)
                    .modifier(RetroFont(size: 14))
                    .foregroundColor(isActive ? .black : .white)
            }
            .frame(width: 35, height: 35)
        }
        .buttonStyle(.plain)
    }
}
