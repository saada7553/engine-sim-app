//
//  ControlsMenuView.swift
//  engine-simulator
//
//  Popover that lists the keyboard bindings handled by KeyboardController.
//  Styled to match the dash theme — RetroFont labels, the brand accent header,
//  and the same key chips used by the onboarding keyboard legend.
//

import SwiftUI

private let controlsPopoverWidth: CGFloat = 250
private let controlsKeyChipMinWidth: CGFloat = 46

private struct KeyBinding: Identifiable {
    let id = UUID()
    let key: String
    let action: String
}

struct ControlsMenuView: View {
    private let bindings: [KeyBinding] = [
        .init(key: "A", action: "Ignition"),
        .init(key: "S", action: "Starter"),
        .init(key: "⇧", action: "Clutch"),
        .init(key: "Space", action: "Rev engine"),
        .init(key: "↑", action: "Upshift"),
        .init(key: "↓", action: "Downshift"),
        .init(key: "D", action: "Dyno"),
        .init(key: "H", action: "Throttle hold")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(Color.strokeFaint)
                .frame(height: Theme.Stroke.thin)

            VStack(spacing: Theme.Space.sm) {
                ForEach(bindings) { KeyBindingRow(binding: $0) }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.lg)
        }
        .frame(width: controlsPopoverWidth)
        .background(Color.appBackground)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "keyboard")
                .font(.system(size: Theme.FontSize.headline))
                .foregroundColor(.accentLive)
            Text("KEYBOARD CONTROLS")
                .modifier(RetroFont(size: Theme.FontSize.callout))
                .tracking(Theme.Tracking.wide)
                .foregroundColor(.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.lg)
    }
}

private struct KeyBindingRow: View {
    let binding: KeyBinding

    var body: some View {
        HStack(spacing: Theme.Space.lg) {
            Text(binding.key)
                .font(.system(size: Theme.FontSize.footnote, weight: .semibold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .frame(minWidth: controlsKeyChipMinWidth)
                .padding(.vertical, Theme.Space.xs)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .fill(Color.sidebarHighlight))

            Text(binding.action)
                .font(.system(size: Theme.FontSize.control))
                .foregroundColor(.textSecondary)

            Spacer(minLength: 0)
        }
    }
}
