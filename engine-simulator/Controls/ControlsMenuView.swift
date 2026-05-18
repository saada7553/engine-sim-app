//
//  ControlsMenuView.swift
//  engine-simulator
//
//  Popover that lists the keyboard bindings handled by KeyboardController.
//

import SwiftUI

struct KeyBinding: Identifiable {
    let id = UUID()
    let key: String
    let action: String
    let available: Bool
}

struct ControlsMenuView: View {
    private let bindings: [KeyBinding] = [
        KeyBinding(key: "A", action: "Toggle ignition", available: true),
        KeyBinding(key: "S", action: "Starter", available: true),
        KeyBinding(key: "⇧", action: "Clutch", available: true),
        KeyBinding(key: "↑", action: "Upshift", available: true),
        KeyBinding(key: "↓", action: "Downshift", available: true),
        KeyBinding(key: "D", action: "Enable dyno", available: true),
        KeyBinding(key: "H", action: "Throttle hold", available: true),
        KeyBinding(key: "Space", action: "Rev engine", available: true),
        KeyBinding(key: ".", action: "Vehicle brake", available: false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .foregroundColor(.sidebarAccent)
                Text("KEYBOARD CONTROLS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.08))

            VStack(spacing: 0) {
                ForEach(bindings) { binding in
                    KeyBindingRow(binding: binding)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 240)
        .background(Color.appBackground)
    }
}

private struct KeyBindingRow: View {
    let binding: KeyBinding

    var body: some View {
        HStack(spacing: 12) {
            Text(binding.key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(binding.available ? .white : .sidebarTextSecondary)
                .frame(minWidth: 46)
                .padding(.vertical, 4)
                .background(Color.sidebarHighlight)
                .cornerRadius(4)

            Text(binding.action)
                .font(.system(size: 12))
                .foregroundColor(binding.available ? .white.opacity(0.8) : .sidebarTextSecondary)

            Spacer()

            if !binding.available {
                Text("N/A")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.sidebarTextSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}
