//
//  HoverDetectionView.swift
//  TileSurf
//
//  Created by Saad Ata on 11/25/25.
//
//  Per-tile overlays shown while the workspace is in SPLIT or DELETE mode.
//  Styling tracks the rest of the dashboard: dark fills, hairline borders,
//  monospaced "RetroFont" labels, and the app's orange/red status colors.
//

import Foundation
import SwiftUI

enum HoverMode {
    case delete
    case split
}

// Palette constants — kept here so all overlay styling is in one place and
// stays aligned with RetroPanel / ControlButton elsewhere in the app.
private let overlayBackgroundDim = Color.black.opacity(0.55)
private let overlayHighlightFill = Color.accentLive.opacity(0.22)
private let overlayHighlightBorder = Color.accentLive.opacity(0.85)
private let overlayDeleteFill = Color.accentDanger.opacity(0.22)
private let overlayDeleteBorder = Color.accentDanger.opacity(0.85)
private let overlayDeleteIconColor = Color.accentDanger
private let overlayLabelBackground = Color.black.opacity(0.85)
private let overlayLabelBorder = Color.white.opacity(0.25)
private let overlayCornerRadius: CGFloat = 10

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
                DeleteOverlay()
                    .transition(.opacity)
            case .split:
                if let direction = hoverPosition {
                    SplitOverlay(
                        direction: direction,
                        isLeftOrTop: determineIsLeftOrTop(
                            location: lastHoverLocation,
                            direction: direction
                        )
                    )
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
        if mode == .split, let direction = hoverPosition {
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

// MARK: - Delete overlay
//
// Dimmed tile with a red-bordered halo and a centered "REMOVE TILE" label.
// Reads as a destructive action without resorting to the previous magenta
// gradient blast.

private struct DeleteOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: overlayCornerRadius)
                .fill(overlayBackgroundDim)

            RoundedRectangle(cornerRadius: overlayCornerRadius)
                .fill(overlayDeleteFill)

            RoundedRectangle(cornerRadius: overlayCornerRadius)
                .strokeBorder(overlayDeleteBorder, lineWidth: 1.5)

            VStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(overlayDeleteIconColor)
                OverlayLabel(text: "REMOVE TILE", accent: overlayDeleteBorder)
            }
        }
    }
}

// MARK: - Split overlay
//
// Splits the tile into the two halves the user is about to create, fills the
// hovered half with an orange wash, and draws a divider line where the new
// split will land. The label tells the user which way the split will fall.

private struct SplitOverlay: View {
    let direction: SplitDirection
    let isLeftOrTop: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: overlayCornerRadius)
                    .fill(overlayBackgroundDim)

                highlightedHalf(in: geo)

                divider(in: geo)

                RoundedRectangle(cornerRadius: overlayCornerRadius)
                    .strokeBorder(overlayHighlightBorder, lineWidth: 1.5)

                OverlayLabel(text: labelText, accent: overlayHighlightBorder)
                    .position(labelPosition(in: geo))
            }
        }
    }

    private func highlightedHalf(in geo: GeometryProxy) -> some View {
        let rect = halfRect(in: geo)
        return Rectangle()
            .fill(overlayHighlightFill)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .clipShape(RoundedRectangle(cornerRadius: overlayCornerRadius))
    }

    private func divider(in geo: GeometryProxy) -> some View {
        let w = geo.size.width
        let h = geo.size.height
        let dashed = StrokeStyle(lineWidth: 1.5, dash: [4, 4])

        return Path { path in
            if direction == .horizontal {
                let x = w / 2
                path.move(to: CGPoint(x: x, y: 8))
                path.addLine(to: CGPoint(x: x, y: h - 8))
            } else {
                let y = h / 2
                path.move(to: CGPoint(x: 8, y: y))
                path.addLine(to: CGPoint(x: w - 8, y: y))
            }
        }
        .stroke(overlayHighlightBorder, style: dashed)
    }

    private func halfRect(in geo: GeometryProxy) -> CGRect {
        let w = geo.size.width
        let h = geo.size.height
        if direction == .horizontal {
            let halfW = w / 2
            let x = isLeftOrTop ? 0 : halfW
            return CGRect(x: x, y: 0, width: halfW, height: h)
        } else {
            let halfH = h / 2
            let y = isLeftOrTop ? 0 : halfH
            return CGRect(x: 0, y: y, width: w, height: halfH)
        }
    }

    private func labelPosition(in geo: GeometryProxy) -> CGPoint {
        let rect = halfRect(in: geo)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private var labelText: String {
        switch (direction, isLeftOrTop) {
        case (.horizontal, true):  return "SPLIT LEFT"
        case (.horizontal, false): return "SPLIT RIGHT"
        case (.vertical, true):    return "SPLIT TOP"
        case (.vertical, false):   return "SPLIT BOTTOM"
        }
    }
}

// MARK: - Shared label

/// Pill label rendered in the monospaced retro font with a thin border in
/// the supplied accent color. Reused by both overlay styles.
private struct OverlayLabel: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .modifier(RetroFont(size: Theme.FontSize.body, weight: .bold))
            .foregroundColor(.white)
            .tracking(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(overlayLabelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(accent.opacity(0.7), lineWidth: 1)
            )
    }
}
