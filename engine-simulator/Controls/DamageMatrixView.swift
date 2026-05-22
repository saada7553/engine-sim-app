//
//  DamageMatrixView.swift
//  engine-simulator
//
//  Per-cylinder damage read-out for the Engine Health tile. One row per wear
//  component, one column per cylinder; each cylinder gets a segmented dash-LED
//  bar that lights up proportional to that component's health, and the worst
//  cylinder's exact percentage prints at the end of the row. A divider then
//  splits off the engine-wide structural parts, each shown as a labelled bar
//  + percentage.
//
//  Healthy segments light in a neutral instrument white; degraded components
//  shift to amber / red so a problem stands out without the whole panel being
//  colour-coded. Everything sizes off a `scale` factor passed from the tile so
//  typography tracks the tile size, and the bars flex to fill the width.
//

import SwiftUI

// MARK: - Palette / thresholds

private let healthyFill = Color.white.opacity(0.82)
private let warningColor = Color.orange
private let criticalColor = Color.red
private let emptySegmentFill = Color.white.opacity(0.06)
private let segmentBorder = Color.white.opacity(0.14)
private let dividerColor = Color.white.opacity(0.12)
private let labelColor = Color.white.opacity(0.55)
private let headerColor = Color.white.opacity(0.8)
private let percentColor = Color.white.opacity(0.7)

private let warnThreshold: Double = 0.70
private let critThreshold: Double = 0.30

// MARK: - Segment counts

private let perCylinderSegments: Int = 4
private let engineWideSegments: Int = 8

// MARK: - Base metrics (multiplied by `scale`)

private let labelColumnWidthBase: CGFloat = 46
private let percentColumnWidthBase: CGFloat = 30
private let cellGapBase: CGFloat = 4
private let rowGapBase: CGFloat = 3
private let segmentGapBase: CGFloat = 1.5
private let segmentCornerBase: CGFloat = 1
private let headerFontBase: CGFloat = 9
private let rowLabelFontBase: CGFloat = 7
private let percentFontBase: CGFloat = 8
private let wideStripTopPadBase: CGFloat = 6
private let wideRowGapBase: CGFloat = 4
private let wideColumnGapBase: CGFloat = 10

private let labelColumnWidthMin: CGFloat = 34
private let percentColumnWidthMin: CGFloat = 26
private let headerFontMin: CGFloat = 7
private let smallFontMin: CGFloat = 6

private let minimumLabelScale: CGFloat = 0.6
private let segmentBorderWidth: CGFloat = 0.5
private let dividerHeight: CGFloat = 0.5
private let percentScale: Double = 100.0

// MARK: - Helpers

private func fillColor(_ v: Double) -> Color {
    if v < critThreshold { return criticalColor }
    if v < warnThreshold { return warningColor }
    return healthyFill
}

private func percentTextColor(_ v: Double) -> Color {
    if v < critThreshold { return criticalColor }
    if v < warnThreshold { return warningColor }
    return percentColor
}

private func percentText(_ v: Double) -> String {
    "\(Int((max(0.0, min(1.0, v)) * percentScale).rounded()))%"
}

// MARK: - Segmented bar

/// A flat dash-LED bar: `segments` cells that light up to represent `health`.
/// No gradients — lit cells are a solid colour, unlit cells a faint recess.
private struct SegmentedHealthBar: View {
    let health: Double
    let segments: Int
    let color: Color
    let gap: CGFloat
    let corner: CGFloat

    private var litCount: Int {
        if health <= 0 { return 0 }
        let raw = Int((health * Double(segments)).rounded())
        return max(1, min(segments, raw))
    }

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: corner)
                    .fill(i < litCount ? color : emptySegmentFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner)
                            .stroke(segmentBorder, lineWidth: segmentBorderWidth)
                    )
            }
        }
    }
}

// MARK: - Row / item models

private struct ComponentRow: Identifiable {
    let id = UUID()
    let label: String
    let value: (CylinderHealthState) -> Double
}

private let componentRows: [ComponentRow] = [
    ComponentRow(label: "GASKET", value: { $0.headGasket }),
    ComponentRow(label: "IN.VLV", value: { $0.intakeValve }),
    ComponentRow(label: "EX.VLV", value: { $0.exhaustValve }),
    ComponentRow(label: "RINGS",  value: { $0.pistonRings }),
    ComponentRow(label: "PISTON", value: { $0.piston }),
    ComponentRow(label: "ROD",    value: { $0.rod }),
    ComponentRow(label: "R.BRG",  value: { $0.rodBearing }),
]

private struct WideItem: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
}

// MARK: - DamageMatrixView

struct DamageMatrixView: View {
    let cylinders: [CylinderHealthState]
    let wide: EngineWideHealthState
    var scale: CGFloat = 1.0

    private var labelColumnWidth: CGFloat { max(labelColumnWidthMin, labelColumnWidthBase * scale) }
    private var percentColumnWidth: CGFloat { max(percentColumnWidthMin, percentColumnWidthBase * scale) }
    private var cellGap: CGFloat { cellGapBase * scale }
    private var rowGap: CGFloat { rowGapBase * scale }
    private var segmentGap: CGFloat { segmentGapBase * scale }
    private var segmentCorner: CGFloat { segmentCornerBase * scale }
    private var headerFont: CGFloat { max(headerFontMin, headerFontBase * scale) }
    private var rowLabelFont: CGFloat { max(smallFontMin, rowLabelFontBase * scale) }
    private var percentFont: CGFloat { max(smallFontMin, percentFontBase * scale) }

    // Engine-wide structural parts, two per row. Pumps deliberately excluded —
    // their state already lives on the thermals control switches.
    private var wideItems: [WideItem] {
        [
            WideItem(label: "HEAD",  value: wide.cylinderHead),
            WideItem(label: "CAM",   value: wide.camshaft),
            WideItem(label: "CRANK", value: wide.crankshaft),
            WideItem(label: "MAINS", value: wide.mainBearing),
        ]
    }

    var body: some View {
        if cylinders.isEmpty {
            emptyState
        } else {
            VStack(spacing: rowGap) {
                headerRow
                ForEach(componentRows) { row in
                    componentRow(row)
                }
                wideStrip
            }
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("NO ENGINE LOADED")
                .font(.system(size: headerFont, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(labelColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Component grid

    private var headerRow: some View {
        HStack(spacing: cellGap) {
            Color.clear.frame(width: labelColumnWidth)
            ForEach(0..<cylinders.count, id: \.self) { i in
                Text("C\(i + 1)")
                    .font(.system(size: headerFont, weight: .bold, design: .monospaced))
                    .foregroundColor(headerColor)
                    .lineLimit(1)
                    .minimumScaleFactor(minimumLabelScale)
                    .frame(maxWidth: .infinity)
            }
            Color.clear.frame(width: percentColumnWidth)
        }
    }

    private func componentRow(_ row: ComponentRow) -> some View {
        let worst = cylinders.map(row.value).min() ?? 1.0
        return HStack(spacing: cellGap) {
            rowLabel(row.label)
            ForEach(0..<cylinders.count, id: \.self) { i in
                let health = row.value(cylinders[i])
                SegmentedHealthBar(health: cylinders[i].seized ? 0 : health,
                                   segments: perCylinderSegments,
                                   color: cylinders[i].seized ? criticalColor : fillColor(health),
                                   gap: segmentGap,
                                   corner: segmentCorner)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            percentLabel(worst)
        }
        .frame(maxHeight: .infinity)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: rowLabelFont, weight: .bold, design: .monospaced))
            .tracking(0.4)
            .foregroundColor(labelColor)
            .lineLimit(1)
            .minimumScaleFactor(minimumLabelScale)
            .frame(width: labelColumnWidth, alignment: .trailing)
    }

    private func percentLabel(_ v: Double) -> some View {
        Text(percentText(v))
            .font(.system(size: percentFont, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(percentTextColor(v))
            .lineLimit(1)
            .minimumScaleFactor(minimumLabelScale)
            .frame(width: percentColumnWidth, alignment: .trailing)
    }

    // MARK: Engine-wide strip

    private var wideStrip: some View {
        VStack(spacing: wideRowGapBase * scale) {
            ForEach(0..<(wideItems.count / 2), id: \.self) { rowIndex in
                HStack(spacing: wideColumnGapBase * scale) {
                    wideItemView(wideItems[rowIndex * 2])
                    wideItemView(wideItems[rowIndex * 2 + 1])
                }
            }
        }
        .padding(.top, wideStripTopPadBase * scale)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(dividerColor)
                .frame(height: dividerHeight)
        }
    }

    private func wideItemView(_ item: WideItem) -> some View {
        HStack(spacing: cellGap) {
            rowLabel(item.label)
            SegmentedHealthBar(health: item.value,
                               segments: engineWideSegments,
                               color: fillColor(item.value),
                               gap: segmentGap,
                               corner: segmentCorner)
                .frame(maxWidth: .infinity)
                .frame(height: headerFont)
            percentLabel(item.value)
        }
        .frame(maxWidth: .infinity)
    }
}
