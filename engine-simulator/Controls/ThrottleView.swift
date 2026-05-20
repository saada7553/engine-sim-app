//
//  ThrottleView.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import SwiftUI

// Proportions used by the visualizers below so internal elements scale with
// whatever rectangle they're rendered into (rather than relying on fixed pt
// sizes that break when the Controls tile shrinks).
private let bodyShaftHeightFraction: CGFloat = 0.85
private let bodyShaftWidthFraction: CGFloat = 0.05
private let bodyBladeWidthFraction: CGFloat = 0.7
private let bodyBladeHeightFraction: CGFloat = 0.05
private let bodyPivotFraction: CGFloat = 0.075
private let throttleArrowGapFraction: CGFloat = 0.25
private let throttleArrowHeightFraction: CGFloat = 0.12

private let clutchShaftHeightFraction: CGFloat = 0.1
private let clutchDriveDiscHeightFraction: CGFloat = 0.75
private let clutchDriveDiscWidthFraction: CGFloat = 0.05
private let clutchDrivenDiscHeightFraction: CGFloat = 0.625
private let clutchDrivenDiscWidthFraction: CGFloat = 0.035
private let clutchDisengageGapFraction: CGFloat = 0.05
private let clutchShaftGapFraction: CGFloat = 0.1

struct ThrottleView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        HStack(spacing: 0) {
            column(title: "CLUTCH ASSEMBLY") {
                ClutchPlateVisualizer(isEngaged: !vm.clutchPressed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
                    .cornerRadius(4)

                ClutchPedal(isPressed: Binding(get: { vm.clutchPressed }, set: { _ in vm.toggleClutch() }))
            }

            Divider().background(Color.white.opacity(0.1))

            column(title: "INTAKE MANIFOLD") {
                ThrottleBodyVisualizer(openPercentage: vm.throttlePosition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
                    .cornerRadius(4)

                PrecisionThrottleSlider(value: $vm.throttlePosition)
            }
        }
        .background(Color.black.opacity(0.2))
        .border(Color.white.opacity(0.1), width: 1)
    }

    @ViewBuilder
    private func column<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).modifier(RetroFont(size: 10)).foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal, 8)

            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ThrottleBodyVisualizer: View {
    var openPercentage: Double

    // Throttle blade angle: closed sits a few degrees off the bore so it stays
    // visible, then opens to nearly perpendicular at full throttle.
    private let bladeClosedDegrees: Double = 5
    private let bladeOpenSweepDegrees: Double = 85
    private let arrowVisibilityThreshold: Double = 0.1
    private let arrowOpacityScale: Double = 0.7

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let shaftHeight = h * bodyShaftHeightFraction
            let shaftWidth = w * bodyShaftWidthFraction
            let bladeWidth = w * bodyBladeWidthFraction
            let bladeHeight = h * bodyBladeHeightFraction
            let pivotDiameter = min(w, h) * bodyPivotFraction
            let arrowSpacing = h * throttleArrowGapFraction
            let arrowHeight = h * throttleArrowHeightFraction
            let angle = bladeClosedDegrees + bladeOpenSweepDegrees * openPercentage

            ZStack {
                HStack {
                    Rectangle().fill(Color(white: 0.3)).frame(width: shaftWidth, height: shaftHeight)
                    Spacer()
                    Rectangle().fill(Color(white: 0.3)).frame(width: shaftWidth, height: shaftHeight)
                }
                .frame(width: bladeWidth + 2 * shaftWidth)

                Circle().fill(Color(white: 0.6)).frame(width: pivotDiameter, height: pivotDiameter)

                Rectangle()
                    .fill(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                    .frame(width: bladeWidth, height: bladeHeight)
                    .rotationEffect(.degrees(angle))
                    .animation(.linear(duration: 0.05), value: openPercentage)

                if openPercentage > arrowVisibilityThreshold {
                    VStack(spacing: arrowSpacing) {
                        ForEach(0..<2, id: \.self) { _ in
                            Image(systemName: "arrow.down")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: arrowHeight)
                                .foregroundColor(.blue.opacity(openPercentage * arrowOpacityScale))
                        }
                    }
                }
            }
            .frame(width: w, height: h)
        }
    }
}

struct ClutchPlateVisualizer: View {
    var isEngaged: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cy = h / 2
            let cx = w / 2

            let shaftHeight = h * clutchShaftHeightFraction
            let shaftGap = w * clutchShaftGapFraction
            let driveDiscHeight = h * clutchDriveDiscHeightFraction
            let driveDiscWidth = w * clutchDriveDiscWidthFraction
            let drivenDiscHeight = h * clutchDrivenDiscHeightFraction
            let drivenDiscWidth = w * clutchDrivenDiscWidthFraction
            let gap: CGFloat = isEngaged ? 0 : w * clutchDisengageGapFraction

            ZStack {
                Path { p in
                    p.addRect(CGRect(x: 0, y: cy - shaftHeight/2, width: cx - shaftGap, height: shaftHeight))
                    p.addRect(CGRect(x: cx + shaftGap, y: cy - shaftHeight/2, width: w - (cx + shaftGap), height: shaftHeight))
                }.fill(Color.sidebarTextSecondary)

                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [Color(white: 0.4), Color(white: 0.7), Color(white: 0.4)], startPoint: .top, endPoint: .bottom))
                    .frame(width: driveDiscWidth, height: driveDiscHeight)
                    .position(x: cx - driveDiscWidth/2, y: cy)

                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [.orange, .orange.opacity(0.6), .orange], startPoint: .top, endPoint: .bottom))
                    .frame(width: drivenDiscWidth, height: drivenDiscHeight)
                    .position(x: cx + drivenDiscWidth/2 + gap, y: cy)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isEngaged)
            }
        }
    }
}

struct ClutchPedal: View {
    @Binding var isPressed: Bool
    
    var body: some View {
        Button(action: { isPressed.toggle() }) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 40, height: 50)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .rotation3DEffect(.degrees(isPressed ? 25 : 0), axis: (x: 1, y: 0, z: 0))
                    
                    VStack(spacing: 5) {
                        ForEach(0..<5) { _ in Rectangle().fill(Color.black.opacity(0.5)).frame(width: 32, height: 2) }
                    }
                    .rotation3DEffect(.degrees(isPressed ? 25 : 0), axis: (x: 1, y: 0, z: 0))
                }
                Text(isPressed ? "DISENGAGED" : "ENGAGED")
                    .modifier(RetroFont(size: 8))
                    .foregroundColor(isPressed ? .orange : .orange.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }
}

struct PrecisionThrottleSlider: View {
    @Binding var value: Double
    private let height: CGFloat = 32
    private let handleWidth: CGFloat = 20
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("THROTTLE INPUT").modifier(RetroFont(size: 9)).foregroundColor(.gray)
                Spacer()
                Text(String(format: "%.0f%%", value * 100)).modifier(RetroFont(size: 9)).foregroundColor(.orange)
            }
            
            GeometryReader { geo in
                let width = geo.size.width - handleWidth
                let x = width * CGFloat(value)
                
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.05))
                    HStack(spacing: 0) {
                        ForEach(0..<11) { i in
                            Rectangle().fill(Color.sidebarTextSecondary.opacity(0.3)).frame(width: 1)
                            if i != 10 { Spacer() }
                        }
                    }
                    .padding(.vertical, 8)
                    
                    Rectangle()
                        .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
                        .frame(width: handleWidth)
                        .overlay(Rectangle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .overlay(HStack(spacing: 2) { ForEach(0..<3) { _ in Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1, height: 12) } })
                        .offset(x: x)
                }
                .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    value = min(max(0, Double((v.location.x - handleWidth/2) / width)), 1)
                })
            }
            .frame(height: height)
        }
    }
}
