//
//  OscilloscopeView.swift
//  engine-simulator
//

import SwiftUI
import Combine

// MARK: - Layout Constants

private let peakMarkerDiameter: CGFloat = 7

// MARK: - Helper Functions

private func calculateGridLines(minVal: Double, maxVal: Double, size: CGFloat) -> [Double] {
    let range = maxVal - minVal
    guard range > 0 else { return [] }

    let targetSteps = max(2, Int(size / 40))
    let roughStep = range / Double(targetSteps)
    let magnitude = pow(10, floor(log10(roughStep)))
    let normalizedStep = roughStep / magnitude

    let step: Double
    if normalizedStep < 1.5 { step = 1.0 * magnitude }
    else if normalizedStep < 3.0 { step = 2.0 * magnitude }
    else if normalizedStep < 7.0 { step = 5.0 * magnitude }
    else { step = 10.0 * magnitude }

    var lines: [Double] = []
    var current = ceil(minVal / step) * step
    while current <= maxVal + (step * 0.001) {
        if current >= minVal - (step * 0.001) { lines.append(current) }
        current += step
    }
    return lines
}

private func formatValue(_ value: Double) -> String {
    if abs(value) >= 1000 { return String(format: "%.1fk", value / 1000) }
    else if abs(value) < 0.01 && value != 0 { return String(format: "%.3f", value) }
    else { return String(format: "%.1f", value) }
}

private func convertY(_ val: Double, bounds: (min: Double, max: Double), height: CGFloat) -> CGFloat {
    let range = bounds.max - bounds.min
    guard range != 0 else { return height / 2 }
    return height * (1.0 - CGFloat((val - bounds.min) / range))
}

private func convertX(_ val: Double, bounds: (min: Double, max: Double), width: CGFloat) -> CGFloat {
    let range = bounds.max - bounds.min
    guard range != 0 else { return 0 }
    return CGFloat((val - bounds.min) / range) * width
}

// MARK: - Main View

struct OscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    let configs: [OscilloscopeConfig]

    var showTitle: Bool = true
    var showAxisLabels: Bool = true
    /// When true each channel keeps its own Y scale (channel 0 -> left axis,
    /// channel 1 -> right axis) instead of sharing one unified scale.
    var independentAxes: Bool = false
    /// When true the peak of each channel is marked with the RPM it occurred at.
    var showPeaks: Bool = false
    var detachmentThreshold: CGFloat = 100.0

    private let gridDivisions = 5

    // Convenience init for single channel
    init(manager: OscilloscopeManager, config: OscilloscopeConfig,
         showTitle: Bool = true, showAxisLabels: Bool = true,
         independentAxes: Bool = false, showPeaks: Bool = false) {
        self.manager = manager
        self.configs = [config]
        self.showTitle = showTitle
        self.showAxisLabels = showAxisLabels
        self.independentAxes = independentAxes
        self.showPeaks = showPeaks
    }

    // Main init for multiple channels
    init(manager: OscilloscopeManager, configs: [OscilloscopeConfig],
         showTitle: Bool = true, showAxisLabels: Bool = true,
         independentAxes: Bool = false, showPeaks: Bool = false) {
        self.manager = manager
        self.configs = configs
        self.showTitle = showTitle
        self.showAxisLabels = showAxisLabels
        self.independentAxes = independentAxes
        self.showPeaks = showPeaks
    }

    private var unifiedBounds: (xMin: Double, xMax: Double, yMin: Double, yMax: Double) {
        let allBounds = configs.map { manager.getAxisBounds(for: $0.type, config: $0) }
        return (
            xMin: allBounds.map(\.xMin).min() ?? 0,
            xMax: allBounds.map(\.xMax).max() ?? 1,
            yMin: allBounds.map(\.yMin).min() ?? 0,
            yMax: allBounds.map(\.yMax).max() ?? 1
        )
    }

    /// X range shared by every channel.
    private var sharedXBounds: (min: Double, max: Double) {
        let allBounds = configs.map { manager.getAxisBounds(for: $0.type, config: $0) }
        return (allBounds.map(\.xMin).min() ?? 0, allBounds.map(\.xMax).max() ?? 1)
    }

    private func channelYBounds(_ index: Int) -> (min: Double, max: Double) {
        let b = manager.getAxisBounds(for: configs[index].type, config: configs[index])
        return (b.yMin, b.yMax)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.appBackground
                if independentAxes {
                    independentChart(geometry)
                } else {
                    unifiedChart(geometry)
                }
                if showTitle { drawLegend() }
                if showAxisLabels { drawCornerLabel() }
            }
        }
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Chart Variants

    private func unifiedChart(_ geometry: GeometryProxy) -> some View {
        let bounds = unifiedBounds
        let gridY = calculateGridLines(minVal: bounds.yMin, maxVal: bounds.yMax, size: geometry.size.height)
        let gridX = calculateGridLines(minVal: bounds.xMin, maxVal: bounds.xMax, size: geometry.size.width)

        return ZStack(alignment: .topLeading) {
            drawGrid(geometry: geometry, bounds: bounds, gridX: gridX, gridY: gridY)

            ForEach(configs.indices, id: \.self) { i in
                let config = configs[i]
                let points = manager.getPoints(for: config.type, config: config)
                Canvas { context, size in
                    drawTrace(context: context, points: points, bounds: bounds, size: size, config: config)
                }
                .clipped()
            }

            if showAxisLabels { drawAxisLabels(gridY: gridY, bounds: bounds, geometry: geometry) }
        }
    }

    private func independentChart(_ geometry: GeometryProxy) -> some View {
        let x = sharedXBounds
        let gridX = calculateGridLines(minVal: x.min, maxVal: x.max, size: geometry.size.width)
        let gridY = (0...gridDivisions).map { Double($0) / Double(gridDivisions) }

        return ZStack(alignment: .topLeading) {
            drawGrid(geometry: geometry,
                     bounds: (xMin: x.min, xMax: x.max, yMin: 0, yMax: 1),
                     gridX: gridX, gridY: gridY)

            ForEach(configs.indices, id: \.self) { i in
                let config = configs[i]
                let y = channelYBounds(i)
                let points = manager.getPoints(for: config.type, config: config)
                Canvas { context, size in
                    drawTrace(context: context, points: points,
                              bounds: (xMin: x.min, xMax: x.max, yMin: y.min, yMax: y.max),
                              size: size, config: config)
                }
                .clipped()
            }

            if showAxisLabels { independentAxisLabels(geometry: geometry) }
            if showPeaks { peakAnnotations(geometry: geometry, xBounds: x) }
        }
    }

    private func independentAxisLabels(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(configs.indices, id: \.self) { i in
                let y = channelYBounds(i)
                let labelX: CGFloat = (i == 0) ? 22 : geometry.size.width - 22

                ForEach(0...gridDivisions, id: \.self) { d in
                    let frac = Double(d) / Double(gridDivisions)
                    let value = y.min + (y.max - y.min) * frac
                    Text(formatValue(value))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.textMuted)
                        .position(x: labelX,
                                  y: geometry.size.height * (1.0 - CGFloat(frac)) - 6)
                }

                Text(configs[i].yAxisLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.textMuted)
                    .position(x: labelX, y: 8)
            }
        }
    }

    private func peakAnnotations(geometry: GeometryProxy, xBounds x: (min: Double, max: Double)) -> some View {
        // Markers sit on the peak data points; labels stack vertically in the
        // top-leading corner using SwiftUI's natural layout so they can never
        // overlap regardless of where each curve peaks.
        let peaks: [(config: OscilloscopeConfig, data: CGPoint, screen: CGPoint)] =
            configs.indices.compactMap { i in
                let config = configs[i]
                let y = channelYBounds(i)
                let points = manager.getPoints(for: config.type, config: config)
                guard let peak = points.max(by: { $0.y < $1.y }), peak.y > 0 else { return nil }
                let screen = CGPoint(
                    x: convertX(Double(peak.x), bounds: (x.min, x.max), width: geometry.size.width),
                    y: convertY(Double(peak.y), bounds: (y.min, y.max), height: geometry.size.height)
                )
                return (config, peak, screen)
            }

        return ZStack {
            ForEach(peaks.indices, id: \.self) { idx in
                Circle()
                    .fill(peaks[idx].config.color)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    .frame(width: peakMarkerDiameter, height: peakMarkerDiameter)
                    .position(peaks[idx].screen)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(peaks.indices, id: \.self) { idx in
                    let p = peaks[idx]
                    Text("PEAK \(p.config.type.displayName.uppercased()) \(Int(p.data.y.rounded())) \(p.config.yAxisLabel) @ \(Int(p.data.x.rounded())) RPM")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(p.config.color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(6)
        }
    }

    // MARK: - Subviews & Drawing

    private func drawGrid(geometry: GeometryProxy, bounds: (xMin: Double, xMax: Double, yMin: Double, yMax: Double), gridX: [Double], gridY: [Double]) -> some View {
        ZStack {
            Path { path in
                for val in gridY {
                    let y = convertY(val, bounds: (bounds.yMin, bounds.yMax), height: geometry.size.height)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
                for val in gridX {
                    let x = convertX(val, bounds: (bounds.xMin, bounds.xMax), width: geometry.size.width)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
            }
            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)

            if bounds.yMin < 0 && bounds.yMax > 0 {
                Path { path in
                    let y = convertY(0, bounds: (bounds.yMin, bounds.yMax), height: geometry.size.height)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
                .stroke(Color.gray.opacity(0.5), lineWidth: 0.5)
            }
        }
    }

    private func drawTrace(context: GraphicsContext, points: [CGPoint], bounds: (xMin: Double, xMax: Double, yMin: Double, yMax: Double), size: CGSize, config: OscilloscopeConfig) {
        guard points.count > 1 else { return }
        
        let screenPoints = points.map { point in
            CGPoint(
                x: convertX(point.x, bounds: (bounds.xMin, bounds.xMax), width: size.width),
                y: convertY(point.y, bounds: (bounds.yMin, bounds.yMax), height: size.height)
            )
        }

        var prev = screenPoints[0]
        var lastDetached = false
        let total = CGFloat(points.count)

        for i in 1..<screenPoints.count {
            let current = screenPoints[i]
            // Time-series scopes use position-in-buffer as an age cue so the
            // freshest samples pop. Static curves (e.g. the spark advance
            // map) opt out via `fadeWithAge = false` — every point is the
            // current state and should render at full strength.
            let s: CGFloat = config.fadeWithAge ? CGFloat(i) / total : 1.0

            let xWentBack = prev.x > current.x
            let largeGap = abs(current.x - prev.x) > detachmentThreshold
            let detached = xWentBack || largeGap

            if config.drawReverse || (!detached && !lastDetached) {
                var width = config.lineWidth * max(s, 0.3)
                if s > 0.95 { width += ((s - 0.95) / 0.05) * 2.0 }

                var path = Path()
                path.move(to: prev)
                path.addLine(to: current)

                context.stroke(path, with: .color(config.color.opacity(max(s, 0.75))), lineWidth: width)
            }

            lastDetached = detached
            prev = current
        }
    }

    private func drawAxisLabels(gridY: [Double], bounds: (xMin: Double, xMax: Double, yMin: Double, yMax: Double), geometry: GeometryProxy) -> some View {
        ForEach(gridY, id: \.self) { val in
            Text(formatValue(val))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.textMuted)
                .position(x: 20, y: convertY(val, bounds: (bounds.yMin, bounds.yMax), height: geometry.size.height) - 6)
        }
    }

    private func drawLegend() -> some View {
        // Legend sizes are smaller on iOS so they don't dominate a
        // shrunk-down oscilloscope tile.
        #if os(macOS)
        let legendFontSize: CGFloat = 10
        let chipSize: CGFloat = 8
        let itemSpacing: CGFloat = 12
        let pad: CGFloat = 4
        let outerPad: CGFloat = 6
        #else
        let legendFontSize: CGFloat = 7
        let chipSize: CGFloat = 5
        let itemSpacing: CGFloat = 7
        let pad: CGFloat = 3
        let outerPad: CGFloat = 4
        #endif

        return VStack {
            HStack {
                Spacer()
                HStack(spacing: itemSpacing) {
                    ForEach(configs.indices, id: \.self) { i in
                        HStack(spacing: 3) {
                            Circle().fill(configs[i].color)
                                .frame(width: chipSize, height: chipSize)
                            Text(configs[i].type.displayName)
                        }
                    }
                }
                .font(.system(size: legendFontSize, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .padding(pad)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
            }
            Spacer()
        }
        .padding(outerPad)
    }

    private func drawCornerLabel() -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                let xLabel = configs.first?.xAxisLabel ?? ""
                let yLabels = Set(configs.map { $0.yAxisLabel }).sorted().joined(separator: ", ")
                Text("\(xLabel) / \(yLabels)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(4)
            }
        }
        .padding(4)
    }
}

// MARK: - Specialized Views

struct TorqueOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View { OscilloscopeView(manager: manager, config: .standard(for: .torque)) }
}

struct PowerOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View { OscilloscopeView(manager: manager, config: .standard(for: .power)) }
}

/// Dyno chart: torque and power over RPM. Reuses the shared OscilloscopeView
/// in its independent-axes mode; once a run ends it shows peak callouts, and
/// an idle hint is overlaid on the empty graph until the first run has data.
struct DynoOscilloscopeView: View {
    @ObservedObject var engineVm: EngineViewModel
    @ObservedObject var manager: OscilloscopeManager

    init(engineVm: EngineViewModel) {
        self.engineVm = engineVm
        self.manager = engineVm.oscilloscopeManager
    }

    private var hasNoData: Bool {
        manager.torque.isEmpty && manager.power.isEmpty
    }

    var body: some View {
        ZStack {
            OscilloscopeView(
                manager: manager,
                configs: [.standard(for: .torque), .standard(for: .power)],
                independentAxes: true,
                showPeaks: !engineVm.dynoEnabled
            )
            if !engineVm.dynoEnabled && hasNoData {
                #if os(macOS)
                Text("ENABLE DYNO (D) TO RUN")
                    .modifier(RetroFont(size: Theme.FontSize.callout))
                    .foregroundColor(.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(6)
                #else
                Text("TAP DYNO IN TOP BAR TO RUN")
                    .modifier(RetroFont(size: Theme.FontSize.callout))
                    .foregroundColor(.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(6)
                #endif
            }
        }
    }
}

struct SparkAdvanceOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View { OscilloscopeView(manager: manager, config: .standard(for: .sparkAdvance)) }
}

struct TotalExhaustFlowOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View { OscilloscopeView(manager: manager, config: .standard(for: .totalExhaustFlow)) }
}

struct ExhaustFlowOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View { OscilloscopeView(manager: manager, config: .standard(for: .exhaustFlow)) }
}

struct IntakeFlowOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View { OscilloscopeView(manager: manager, config: .standard(for: .intakeFlow)) }
}

struct FlowOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View {
        OscilloscopeView(manager: manager, configs: [.standard(for: .exhaustFlow), .standard(for: .intakeFlow)])
    }
}

struct ExhaustValveLiftOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View { OscilloscopeView(manager: manager, config: .standard(for: .exhaustValveLift)) }
}

struct IntakeValveLiftOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View { OscilloscopeView(manager: manager, config: .standard(for: .intakeValveLift)) }
}

struct ValveLiftOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View {
        OscilloscopeView(manager: manager, configs: [.standard(for: .exhaustValveLift), .standard(for: .intakeValveLift)])
    }
}

struct CylinderPressureOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View { OscilloscopeView(manager: manager, config: .standard(for: .cylinderPressure)) }
}

struct CylinderMoleculesOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View { OscilloscopeView(manager: manager, config: .standard(for: .cylinderMolecules)) }
}

struct PVOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View { OscilloscopeView(manager: manager, config: .standard(for: .PV)) }
}

struct SelectableOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    let type: EngineScopeType
    var body: some View { OscilloscopeView(manager: manager, config: .standard(for: type)) }
}

#if DEBUG
struct OscilloscopeView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = OscilloscopeManager()
        VStack(spacing: 10) {
            TorqueOscilloscopeView(manager: manager).frame(height: 150)
            PowerOscilloscopeView(manager: manager).frame(height: 150)
        }
        .padding().background(Color.black)
    }
}
#endif