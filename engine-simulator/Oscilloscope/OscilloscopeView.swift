//
//  OscilloscopeView.swift
//  engine-simulator
//

import SwiftUI
import Combine

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
    var detachmentThreshold: CGFloat = 100.0

    // Convenience init for single channel
    init(manager: OscilloscopeManager, config: OscilloscopeConfig, showTitle: Bool = true, showAxisLabels: Bool = true) {
        self.manager = manager
        self.configs = [config]
        self.showTitle = showTitle
        self.showAxisLabels = showAxisLabels
    }

    // Main init for multiple channels
    init(manager: OscilloscopeManager, configs: [OscilloscopeConfig], showTitle: Bool = true, showAxisLabels: Bool = true) {
        self.manager = manager
        self.configs = configs
        self.showTitle = showTitle
        self.showAxisLabels = showAxisLabels
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

    var body: some View {
        GeometryReader { geometry in
            let bounds = unifiedBounds
            let gridY = calculateGridLines(minVal: bounds.yMin, maxVal: bounds.yMax, size: geometry.size.height)
            let gridX = calculateGridLines(minVal: bounds.xMin, maxVal: bounds.xMax, size: geometry.size.width)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.8) // Background

                drawGrid(geometry: geometry, bounds: bounds, gridX: gridX, gridY: gridY)
                
                // Traces
                ForEach(configs.indices, id: \.self) { i in
                    let config = configs[i]
                    let points = manager.getPoints(for: config.type, config: config)
                    
                    Canvas { context, size in
                        drawTrace(context: context, points: points, bounds: bounds, size: size, config: config)
                    }
                    .clipped()
                }

                if showAxisLabels { drawAxisLabels(gridY: gridY, bounds: bounds, geometry: geometry) }
                if showTitle { drawLegend() }
                if showAxisLabels { drawCornerLabel() }
            }
        }
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
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
            let s = CGFloat(i) / total
            
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
                .foregroundColor(.gray)
                .position(x: 20, y: convertY(val, bounds: (bounds.yMin, bounds.yMax), height: geometry.size.height) - 6)
        }
    }

    private func drawLegend() -> some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    ForEach(configs.indices, id: \.self) { i in
                        HStack(spacing: 4) {
                            Circle().fill(configs[i].color).frame(width: 8, height: 8)
                            Text(configs[i].type.displayName)
                        }
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .padding(4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
            }
            Spacer()
        }
        .padding(6)
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

struct DynoOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    var body: some View {
        OscilloscopeView(manager: manager, configs: [.standard(for: .torque), .standard(for: .power)])
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
            DynoOscilloscopeView(manager: manager).frame(height: 150)
        }
        .padding().background(Color.black)
    }
}
#endif