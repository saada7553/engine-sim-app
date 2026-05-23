//
//  SelectView.swift
//  engine-simulator
//
//  Shown when a fresh tile hasn't been assigned a view yet. The previous
//  implementation was a plain SwiftUI List, which read as a bright system
//  scroll surface and didn't match the dashboard aesthetic anywhere else in
//  the app. This version renders the available view types as compact dark
//  cards grouped by category, each with a stylized preview glyph and a one
//  line description, so the user can recognise the option before clicking.
//

import SwiftUI

// MARK: - Layout constants

private let selectViewHorizontalPadding: CGFloat = 24
private let selectViewVerticalPadding: CGFloat = 20
private let cardHeight: CGFloat = 64
private let cardSpacing: CGFloat = 10
private let cardCornerRadius: CGFloat = Theme.Radius.panel
private let cardHoverBorder = Color.accentLive.opacity(0.75)
private let cardIdleBorder = Color.white.opacity(0.15)
private let cardBackground = Color.white.opacity(0.04)
private let cardHoverBackground = Color.accentLive.opacity(0.08)
private let cardIconColor = Color.accentLive.opacity(0.85)
private let cardTitleColor = Color.white.opacity(0.92)
private let cardSubtitleColor = Color.textMuted
private let sectionTitleColor = Color.white.opacity(0.55)

// MARK: - Tile type metadata
//
// Lives here, in the picker, because every other view that renders these
// types already knows how to draw itself; only the picker needs an icon and
// a one-line elevator pitch.

private struct TilePreviewMeta {
    let icon: String
    let summary: String
}

private let tilePreviews: [TileType: TilePreviewMeta] = [
    .engine3DProcedural: .init(icon: "cube.transparent",
                               summary: "Live 3D model of the simulated engine"),
    .engine3DWireframe: .init(icon: "grid",
                              summary: "Rotating colour-cycling wireframe diagnostic view"),

    .speedometerGauge:           .init(icon: "speedometer",        summary: "Vehicle speed dial"),
    .rpmGauge:                   .init(icon: "gauge.high",         summary: "Engine RPM with redline"),
    .manifoldPressureGauge:      .init(icon: "barometer",          summary: "Intake manifold vacuum / boost"),
    .volumetricEfficiencyGauge:  .init(icon: "percent",            summary: "VE % at the current operating point"),
    .airScfmGauge:               .init(icon: "wind",               summary: "Air flow into the engine (SCFM)"),
    .intakeAfrGauge:             .init(icon: "flame",              summary: "Intake air-fuel ratio"),
    .exhaustO2Gauge:             .init(icon: "smoke",              summary: "Exhaust O₂ % readout"),
    .cylinderPressureGauge:      .init(icon: "thermometer.high",   summary: "Peak cylinder pressure"),

    .engineControls:  .init(icon: "slider.horizontal.3", summary: "Throttle, clutch, gear shifter"),
    .ecuTuning:       .init(icon: "memorychip",          summary: "Ignition + fuel map tuning grid"),
    .cylinderControl: .init(icon: "switch.2",            summary: "Cut spark to individual cylinders"),
    .engineHealth:    .init(icon: "heart.text.square",   summary: "Coolant, oil, per-component damage"),
    .obd2:            .init(icon: "exclamationmark.triangle", summary: "OBD-II diagnostic code readout"),

    .shiftLight:        .init(icon: "rectangle.grid.1x2", summary: "Race-style LED shift indicator"),
    .zeroToSixtyTimer:  .init(icon: "stopwatch",          summary: "Arm-and-launch 0-60 mph stopwatch"),

    .leaderboard:       .init(icon: "trophy",             summary: "Global rankings — post your dyno & launch runs"),
    .community:         .init(icon: "person.2",           summary: "Browse & download engines shared by other players"),

    .torqueOscilloscope:            .init(icon: "waveform.path",        summary: "Crankshaft torque vs crank angle"),
    .powerOscilloscope:             .init(icon: "bolt.fill",            summary: "Instantaneous engine power"),
    .dynoOscilloscope:              .init(icon: "speedometer",          summary: "Dyno torque + power vs RPM sweep"),
    .sparkAdvanceOscilloscope:      .init(icon: "bolt",                 summary: "Spark advance over the curve"),
    .totalExhaustFlowOscilloscope:  .init(icon: "wind",                 summary: "Combined exhaust mass flow"),
    .exhaustFlowOscilloscope:       .init(icon: "wind",                 summary: "Per-runner exhaust flow"),
    .intakeFlowOscilloscope:        .init(icon: "wind",                 summary: "Per-runner intake flow"),
    .flowOscilloscope:              .init(icon: "waveform",             summary: "Intake + exhaust flow overlay"),
    .exhaustValveLiftOscilloscope:  .init(icon: "waveform.path.ecg",    summary: "Exhaust valve lift curve"),
    .intakeValveLiftOscilloscope:   .init(icon: "waveform.path.ecg",    summary: "Intake valve lift curve"),
    .valveLiftOscilloscope:         .init(icon: "waveform.path.ecg",    summary: "Both valve lift curves overlaid"),
    .cylinderPressureOscilloscope:  .init(icon: "waveform.path.badge.plus",
                                          summary: "Cylinder pressure vs crank angle"),
    .cylinderMoleculesOscilloscope: .init(icon: "atom",                 summary: "Mole counts inside the cylinder"),
    .pvOscilloscope:                .init(icon: "chart.xyaxis.line",    summary: "Pressure-volume thermodynamic loop"),
]

private struct TilePreviewSection {
    let title: String
    let types: [TileType]
}

private let pickerSections: [TilePreviewSection] = [
    .init(title: "VISUALIZATION", types: [.engine3DProcedural, .engine3DWireframe]),
    .init(title: "GAUGES", types: [
        .rpmGauge, .speedometerGauge, .manifoldPressureGauge,
        .volumetricEfficiencyGauge, .airScfmGauge, .intakeAfrGauge,
        .exhaustO2Gauge, .cylinderPressureGauge,
    ]),
    .init(title: "CONTROLS", types: [.engineControls, .ecuTuning, .cylinderControl]),
    .init(title: "DIAGNOSTICS", types: [.engineHealth, .obd2]),
    .init(title: "DRIVER TOOLS", types: [.shiftLight, .zeroToSixtyTimer]),
    .init(title: "COMPETE", types: [.leaderboard, .community]),
    .init(title: "OSCILLOSCOPES", types: [
        .torqueOscilloscope, .powerOscilloscope, .dynoOscilloscope,
        .sparkAdvanceOscilloscope, .pvOscilloscope,
        .cylinderPressureOscilloscope, .cylinderMoleculesOscilloscope,
        .flowOscilloscope, .intakeFlowOscilloscope, .exhaustFlowOscilloscope,
        .totalExhaustFlowOscilloscope, .valveLiftOscilloscope,
        .intakeValveLiftOscilloscope, .exhaustValveLiftOscilloscope,
    ]),
]

// MARK: - SelectView

struct SelectView: View {
    @ObservedObject var tile: TileViewModel

    var body: some View {
        ZStack {
            Color.appBackground

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    ForEach(pickerSections, id: \.title) { section in
                        SectionGrid(section: section) { type in
                            tile.data.type = type
                        }
                    }
                }
                .padding(.horizontal, selectViewHorizontalPadding)
                .padding(.vertical, selectViewVerticalPadding)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SELECT A VIEW")
                .modifier(RetroFont(size: Theme.FontSize.callout, weight: .bold))
                .foregroundColor(.accentLive)
                .tracking(2)
            Text("Pick what this tile should display.")
                .font(.system(size: Theme.FontSize.headline))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

// MARK: - Section grid

private struct SectionGrid: View {
    let section: TilePreviewSection
    let onSelect: (TileType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .modifier(RetroFont(size: Theme.FontSize.footnote, weight: .bold))
                .foregroundColor(sectionTitleColor)
                .tracking(1.4)

            // Flow layout instead of a fixed-column grid: every card is the
            // same height and sizes its WIDTH to its text, so a long
            // description widens its card rather than wrapping and making the
            // row taller than its neighbours.
            FlowLayout(spacing: cardSpacing) {
                ForEach(section.types, id: \.rawValue) { type in
                    PreviewCard(type: type, action: { onSelect(type) })
                }
            }
        }
    }
}

// MARK: - Flow layout
//
// Left-aligned wrapping layout: places each card at its intrinsic size and
// breaks to a new row when the next one won't fit the available width.

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0, totalHeight: CGFloat = 0

        for size in subviews.map({ $0.sizeThatFits(.unspecified) }) {
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? totalWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Card

private struct PreviewCard: View {
    let type: TileType
    let action: () -> Void

    @State private var hovering = false

    private var meta: TilePreviewMeta {
        tilePreviews[type] ?? TilePreviewMeta(icon: "square.dashed", summary: type.displayName)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PreviewIcon(symbol: meta.icon, hovering: hovering)

                VStack(alignment: .leading, spacing: 3) {
                    Text(type.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(cardTitleColor)
                    Text(meta.summary)
                        .font(.system(size: 11))
                        .foregroundColor(cardSubtitleColor)
                }
                // Both lines stay single-line; the card widens to fit them
                // (handled by FlowLayout) rather than wrapping and growing tall.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .frame(height: cardHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .fill(hovering ? cardHoverBackground : cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .stroke(hovering ? cardHoverBorder : cardIdleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(meta.summary)
    }
}

private struct PreviewIcon: View {
    let symbol: String
    let hovering: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.black.opacity(0.35))
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )

            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(hovering ? .accentLive : cardIconColor)
        }
        .frame(width: 36, height: 36)
    }
}
