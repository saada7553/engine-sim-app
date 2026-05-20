//
//  BuilderControls.swift
//  engine-simulator
//
//  Shared visual controls for the engine builder. All styled with the dark
//  monospaced look used elsewhere in the app — no generic macOS chrome.
//

import SwiftUI

// MARK: - Visual constants

enum BuilderTheme {
    static let cardCorner: CGFloat = 4
    static let trackHeight: CGFloat = 2
    static let knobSize: CGFloat = 14
    static let accent: Color = .sidebarAccent
    static let dim: Color = .white.opacity(0.4)
    static let line: Color = .white.opacity(0.15)
    static let label: Color = .white.opacity(0.55)
}

// MARK: - Big readout

struct BigReadout: View {
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(BuilderTheme.label)
                .tracking(2)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 56, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
                Text(unit.uppercased())
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.dim)
                    .tracking(2)
            }
        }
    }
}

// MARK: - Themed slider

struct BuilderSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.1
    var unit: String = ""
    var format: String = "%.1f"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(BuilderTheme.label)
                Spacer()
                Text("\(String(format: format, value))\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
            }

            ThemedTrackSlider(value: $value, range: range, step: step)
                .frame(height: 22)
        }
    }
}

private struct ThemedTrackSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let normalized = clamp((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0, 1)
            let knobX = normalized * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(BuilderTheme.line)
                    .frame(height: BuilderTheme.trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)

                Rectangle()
                    .fill(BuilderTheme.accent)
                    .frame(width: knobX, height: BuilderTheme.trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)

                Rectangle()
                    .fill(BuilderTheme.accent)
                    .frame(width: BuilderTheme.knobSize, height: BuilderTheme.knobSize)
                    .offset(x: knobX - BuilderTheme.knobSize / 2)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let frac = clamp(drag.location.x / width, 0, 1)
                        let raw = range.lowerBound + frac * (range.upperBound - range.lowerBound)
                        value = snap(raw)
                    }
            )
        }
    }

    private func snap(_ raw: Double) -> Double {
        guard step > 0 else { return clamp(raw, range.lowerBound, range.upperBound) }
        let snapped = (raw / step).rounded() * step
        return clamp(snapped, range.lowerBound, range.upperBound)
    }
}

private func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
    min(max(v, lo), hi)
}

// MARK: - Selectable card grid

struct CardGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    let isSelected: (Item) -> Bool
    let onSelect: (Item) -> Void
    let content: (Item, Bool) -> Content

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 16), count: columns)
        LazyVGrid(columns: cols, spacing: 16) {
            ForEach(items) { item in
                let selected = isSelected(item)
                Button(action: { onSelect(item) }) {
                    content(item, selected)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(selected ? Color.white.opacity(0.08) : Color.white.opacity(0.02))
                        .overlay(
                            Rectangle()
                                .stroke(selected ? BuilderTheme.accent : BuilderTheme.line,
                                        lineWidth: selected ? 1.5 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Themed nav buttons

struct BuilderNavButton: View {
    enum Style { case primary, secondary, ghost }

    let label: String
    let style: Style
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .frame(minWidth: 130)
                .foregroundColor(textColor)
                .background(backgroundColor)
                .overlay(Rectangle().stroke(borderColor, lineWidth: 1))
                // Without this the secondary/ghost styles have a clear
                // background — the click only registers on the text glyphs
                // or border, making the rest of the button dead space.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private var textColor: Color {
        switch style {
        case .primary:   return .black
        case .secondary: return .white
        case .ghost:     return BuilderTheme.label
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:   return BuilderTheme.accent
        case .secondary: return .clear
        case .ghost:     return .clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:   return BuilderTheme.accent
        case .secondary: return .white.opacity(0.5)
        case .ghost:     return .clear
        }
    }
}

// MARK: - Section heading (used inside steps)

struct BuilderSectionHeading: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(3)
            .foregroundColor(BuilderTheme.label)
    }
}
