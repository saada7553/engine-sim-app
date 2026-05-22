//
//  BuilderControls.swift
//  engine-simulator
//
//  Shared visual controls for the engine builder. All styled with the dark
//  monospaced look used elsewhere in the app — no generic macOS chrome.
//

import SwiftUI

// MARK: - Visual constants

// Builder visuals now alias the app-wide tokens (orange accent, the shared
// text/stroke ladder, Theme corner radii) so the builder reads as the same
// instrument app as everything else — the old salmon `sidebarAccent` and the
// sharp 4pt boxes are gone.
enum BuilderTheme {
    static let cardCorner: CGFloat = Theme.Radius.control
    static let trackHeight: CGFloat = 3
    static let knobSize: CGFloat = 14
    static let accent: Color = .accentLive
    static let dim: Color = .textFaint
    static let line: Color = .strokeSubtle
    static let label: Color = .textMuted
}

// MARK: - Big readout

struct BigReadout: View {
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: Theme.FontSize.body, weight: .bold, design: .monospaced))
                .foregroundColor(BuilderTheme.label)
                .tracking(2)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 56, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
                Text(unit.uppercased())
                    .font(.system(size: Theme.FontSize.headline, weight: .regular, design: .monospaced))
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
                    .font(.system(size: Theme.FontSize.body, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(BuilderTheme.label)
                Spacer()
                Text("\(String(format: format, value))\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.system(size: Theme.FontSize.headline, weight: .regular, design: .monospaced))
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
                Capsule()
                    .fill(BuilderTheme.line)
                    .frame(height: BuilderTheme.trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)

                Capsule()
                    .fill(BuilderTheme.accent)
                    .frame(width: knobX, height: BuilderTheme.trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)

                Circle()
                    .fill(BuilderTheme.accent)
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .frame(width: BuilderTheme.knobSize, height: BuilderTheme.knobSize)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
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
                        .background(
                            RoundedRectangle(cornerRadius: BuilderTheme.cardCorner)
                                .fill(selected ? Color.surfaceRaised : Color.surfaceFaint)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BuilderTheme.cardCorner)
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
                .font(.system(size: Theme.FontSize.callout, weight: .bold, design: .monospaced))
                .tracking(2)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .frame(minWidth: 130)
                .foregroundColor(textColor)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control).fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .stroke(borderColor, lineWidth: Theme.Stroke.thin)
                )
                // Without this the secondary/ghost styles have a clear
                // background — the click only registers on the text glyphs
                // or border, making the rest of the button dead space.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    // Tinted-accent CTA to match the rest of the app (the overlay / paywall
    // buttons, SmallActionButton) rather than a solid fill.
    private var textColor: Color {
        switch style {
        case .primary:   return .accentLive
        case .secondary: return .textPrimary
        case .ghost:     return BuilderTheme.label
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:   return Color.accentLive.opacity(0.14)
        case .secondary: return .surfaceLow
        case .ghost:     return .clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:   return Color.accentLive.opacity(0.6)
        case .secondary: return .strokeStrong
        case .ghost:     return .clear
        }
    }
}

// MARK: - Section heading (used inside steps)

struct BuilderSectionHeading: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: Theme.FontSize.body, weight: .bold, design: .monospaced))
            .tracking(3)
            .foregroundColor(BuilderTheme.label)
    }
}
