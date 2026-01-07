//
//  HoverDetectionView.swift
//  TileSurf
//
//  Created by Saad Ata on 11/25/25.
//

import Foundation
import SwiftUI

enum HoverMode {
    case delete
    case split
}

struct HoverDetectionView: View {
    let mode: HoverMode
    let geometry: GeometryProxy
    let isHovered: Bool
    let hoverPosition: SplitDirection?
    let onHover: (SplitDirection?) -> Void
    let onHoverEnd: () -> Void
    let onSplit: (SplitDirection, Bool) -> Void
    let onDelete: () -> Void
    @State private var lastHoverLocation: CGPoint = .zero
    
    var body: some View {
        ZStack {
            overlayContent
            hitbox
        }
    }
    
    @ViewBuilder
   private var overlayContent: some View {
       if isHovered {
           switch mode {
           case .delete:
               deleteOverlay
                   .transition(.opacity.combined(with: .scale))
           case .split:
               if let direction = hoverPosition {
                   splitOverlay(direction)
                       .transition(.opacity)
               }
           }
       }
   }
    
    var hitbox: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { tapGesture() }
            .onContinuousHover { phase in
                onContHover(phase)
            }
    }
    
    func tapGesture() -> Void {
        if  mode == .split,
            let direction = hoverPosition {
            let isLeftOrTop = determineIsLeftOrTop(
                location: lastHoverLocation,
                direction: direction
            )
            onSplit(direction, isLeftOrTop)
        }
        
        if mode == .delete {
            onDelete()
        }
    }
    
    func onContHover(_ phase: HoverPhase) -> Void {
        switch phase {
        case .active(let location):
            lastHoverLocation = location
            let direction = determineDirection(location: location)
            onHover(direction)
        case .ended:
            onHoverEnd()
        }
    }
    
    func determineDirection(location: CGPoint) -> SplitDirection {
        let W = geometry.size.width
        let H = geometry.size.height
        
        let mainDiagonalY = (H / W) * location.x
        let antiDiagonalY = H - (H / W) * location.x
        let y = location.y
        
        let aboveMain = y < mainDiagonalY
        let aboveAnti = y < antiDiagonalY

        let isHorizontal = aboveMain != aboveAnti
        return isHorizontal ? .horizontal : .vertical
    }
    
    func determineIsLeftOrTop(location: CGPoint, direction: SplitDirection) -> Bool {
        if direction == .horizontal { return location.x < geometry.size.width / 2 }
        return location.y < geometry.size.height / 2
    }
}


// MARK: - Overlay Styles Extension
extension HoverDetectionView {
    var deleteOverlay: some View {
        DeleteOverlayContent()
    }
    
    func splitOverlay(_ direction: SplitDirection) -> some View {
        SplitOverlayContent(
            direction: direction,
            isLeftOrTop: determineIsLeftOrTop(
                location: lastHoverLocation,
                direction: direction
            )
        )
    }
}

// MARK: - Delete Overlay Component
private struct DeleteOverlayContent: View {
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            backgroundGradient
            deleteIcon
        }
        .onAppear { startPulseAnimation() }
    }
    
    private var backgroundGradient: some View {
        LinearGradient.deleteOverlayGradient
            .opacity(0.85)
            .customCornerRadius()
    }
    
    private var deleteIcon: some View {
        Image(systemName: "trash.fill")
            .font(.system(size: 64, weight: .medium))
            .foregroundStyle(.white)
            .scaleEffect(pulseScale)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
    
    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.1
        }
    }
}

private struct SplitOverlayContent: View {
    let direction: SplitDirection
    let isLeftOrTop: Bool
    @State private var animationProgress: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                splitGradientBackground
                splitLabel(in: geo)
            }
        }
        .onAppear { startAnimation() }
    }
    
    private var splitGradientBackground: some View {
        Group {
            if direction == .horizontal {
                HStack(spacing: 0) {
                    gradientSection(isHovered: isLeftOrTop)
                    gradientSection(isHovered: !isLeftOrTop)
                }
            } else {
                VStack(spacing: 0) {
                    gradientSection(isHovered: isLeftOrTop)
                    gradientSection(isHovered: !isLeftOrTop)
                }
            }
        }
        .customCornerRadius()
    }
    
    private func gradientSection(isHovered: Bool) -> some View {
        Group {
            if isHovered {
                LinearGradient.splitPrimaryGradient
                    .opacity(0.7)
            } else {
                Color.clear
            }
        }
    }
    
    private func splitLabel(in geo: GeometryProxy) -> some View {
        Text(splitDirectionText)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                LinearGradient.tileViewBorderGradient,
                                lineWidth: 2
                            )
                    }
            )
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .offset(labelOffset(in: geo))
            .opacity(animationProgress)
    }
    
    private var splitDirectionText: String {
        switch (direction, isLeftOrTop) {
        case (.horizontal, true): return "Split Left"
        case (.horizontal, false): return "Split Right"
        case (.vertical, true): return "Split Top"
        case (.vertical, false): return "Split Bottom"
        }
    }
    
    private func labelOffset(in geo: GeometryProxy) -> CGSize {
        let midX = geo.size.width / 2
        let midY = geo.size.height / 2
        
        switch (direction, isLeftOrTop) {
        case (.horizontal, true):
            return CGSize(width: -midX / 2, height: 0)
        case (.horizontal, false):
            return CGSize(width: midX / 2, height: 0)
        case (.vertical, true):
            return CGSize(width: 0, height: -midY / 2)
        case (.vertical, false):
            return CGSize(width: 0, height: midY / 2)
        }
    }
    
    private func startAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            animationProgress = 1.0
        }
    }
}
