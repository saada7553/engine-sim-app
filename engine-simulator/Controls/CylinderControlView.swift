//
//  CylinderControlView.swift
//  engine-simulator
//
//  Per-cylinder spark control tile. One rocker switch per cylinder cuts or
//  restores ignition to that cylinder, reusing the same DashRockerSwitch
//  chrome as the coolant / oil pump controls in the Engine Health tile so the
//  two tiles read as one family. Cutting a cylinder stops its plug from
//  firing — the charge is drawn in and pumped out unburnt — and surfaces a
//  warning in the OBD-II scanner for as long as it stays cut.
//
//  The switch bank centers itself and re-flows between a row, a column, or a
//  grid depending on which arrangement best fills the tile's bounding box.
//

import SwiftUI

// MARK: - Layout metrics (base values scaled to fit)

private let referenceWidth: CGFloat = 380
private let minScale: CGFloat = 0.7
private let maxScale: CGFloat = 1.25

private let tilePaddingBase: CGFloat = 12
private let sectionSpacingBase: CGFloat = 8
private let panelSpacingBase: CGFloat = 6
private let cellSpacingBase: CGFloat = 12
private let controlCaptionGapBase: CGFloat = 3

private let titleFontBase: CGFloat = 11
private let captionFontBase: CGFloat = 8

private let titleFontMin: CGFloat = 9
private let captionFontMin: CGFloat = 7

private let switchWidthBase: CGFloat = 46
private let switchHeightBase: CGFloat = 44

// Per-cell footprint at scale 1.0: switch + caption gap + caption line.
private let cellWidthBase: CGFloat = switchWidthBase
private let cellHeightBase: CGFloat = switchHeightBase + controlCaptionGapBase + captionFontBase

// How far the switches may scale relative to their base size when filling the
// available space.
private let switchMinScale: CGFloat = 0.65
private let switchMaxScale: CGFloat = 1.4

private let cardCorner: CGFloat = 3
private let borderColor = Color.white.opacity(0.12)
private let mutedText = Color.white.opacity(0.45)
private let ignitionAccent = Color.green

struct CylinderControlView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        GeometryReader { geo in
            let scale = min(max(geo.size.width / referenceWidth, minScale), maxScale)

            VStack(alignment: .leading, spacing: sectionSpacingBase * scale) {
                header(scale: scale)
                switchPanel(scale: scale)
            }
            .padding(tilePaddingBase * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.appBackground)
        }
    }

    // MARK: Header

    private func header(scale: CGFloat) -> some View {
        Text("CYLINDER IGNITION CONTROL")
            .modifier(RetroFont(size: max(titleFontMin, titleFontBase * scale)))
            .tracking(1.0)
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    // MARK: Switch panel

    private func switchPanel(scale: CGFloat) -> some View {
        let spacing = cellSpacingBase * scale

        return GeometryReader { box in
            let count = vm.cylinderIgnitionEnabled.count
            if count == 0 {
                emptyState(scale: scale)
            } else {
                let layout = bestLayout(count: count, in: box.size, spacing: spacing)
                switchGrid(layout: layout, spacing: spacing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(panelSpacingBase * scale)
        .overlay(panelBorder)
        .clipShape(RoundedRectangle(cornerRadius: cardCorner))
    }

    private func emptyState(scale: CGFloat) -> some View {
        Text("NO ENGINE LOADED")
            .modifier(RetroFont(size: max(captionFontMin, captionFontBase * scale)))
            .foregroundColor(mutedText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func switchGrid(layout: GridLayout, spacing: CGFloat) -> some View {
        let switchScale = layout.switchScale

        return VStack(spacing: spacing) {
            ForEach(0..<layout.rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<layout.columns, id: \.self) { col in
                        let index = row * layout.columns + col
                        if index < vm.cylinderIgnitionEnabled.count {
                            cylinderSwitch(index: index, switchScale: switchScale)
                        }
                    }
                }
            }
        }
    }

    private func cylinderSwitch(index: Int, switchScale: CGFloat) -> some View {
        VStack(spacing: controlCaptionGapBase * switchScale) {
            DashRockerSwitch(topLabel: "ON",
                             bottomLabel: "OFF",
                             isOn: vm.cylinderIgnitionEnabled[index],
                             accent: ignitionAccent,
                             width: switchWidthBase * switchScale,
                             height: switchHeightBase * switchScale,
                             toggle: { vm.toggleCylinderIgnition(index) })
            Text("CYL \(index + 1)")
                .modifier(RetroFont(size: max(captionFontMin, captionFontBase * switchScale)))
                .tracking(0.6)
                .foregroundColor(mutedText)
                .lineLimit(1)
        }
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: cardCorner)
            .stroke(borderColor, lineWidth: 0.75)
    }

    // MARK: Responsive layout

    private struct GridLayout {
        let columns: Int
        let rows: Int
        let switchScale: CGFloat
    }

    /// Picks the column/row split that lets the switches grow as large as
    /// possible inside `size` — which naturally yields a single row in a wide
    /// box, a single column in a tall one, and a grid in between. Ties break
    /// toward the arrangement with the fewest empty trailing cells.
    private func bestLayout(count: Int, in size: CGSize, spacing: CGFloat) -> GridLayout {
        var best = GridLayout(columns: count, rows: 1, switchScale: switchMinScale)
        var bestScore = -CGFloat.greatestFiniteMagnitude

        for columns in 1...count {
            let rows = Int((Double(count) / Double(columns)).rounded(.up))

            let gridWidth = CGFloat(columns) * cellWidthBase + CGFloat(columns - 1) * spacing
            let gridHeight = CGFloat(rows) * cellHeightBase + CGFloat(rows - 1) * spacing
            guard gridWidth > 0, gridHeight > 0 else { continue }

            let fit = min(size.width / gridWidth, size.height / gridHeight)
            let emptyCells = columns * rows - count
            let score = fit - CGFloat(emptyCells) * 0.01

            if score > bestScore {
                bestScore = score
                let scale = min(max(fit, switchMinScale), switchMaxScale)
                best = GridLayout(columns: columns, rows: rows, switchScale: scale)
            }
        }

        return best
    }
}
