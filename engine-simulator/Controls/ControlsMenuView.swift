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
                    .font(.system(size: Theme.FontSize.callout, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Theme.Space.xl)

            Divider().background(Color.strokeFaint)

            VStack(spacing: 0) {
                ForEach(bindings) { binding in
                    KeyBindingRow(binding: binding)
                }
            }
            .padding(.vertical, Theme.Space.sm)
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
                .font(.system(size: Theme.FontSize.callout, weight: .semibold, design: .monospaced))
                .foregroundColor(binding.available ? .white : .sidebarTextSecondary)
                .frame(minWidth: 46)
                .padding(.vertical, Theme.Space.xs)
                .background(Color.sidebarHighlight)
                .cornerRadius(Theme.Radius.small)

            Text(binding.action)
                .font(.system(size: Theme.FontSize.control))
                .foregroundColor(binding.available ? .white.opacity(0.8) : .sidebarTextSecondary)

            Spacer()

            if !binding.available {
                Text("N/A")
                    .font(.system(size: Theme.FontSize.footnote, weight: .semibold))
                    .foregroundColor(.sidebarTextSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}
