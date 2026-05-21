//
//  CustomSplitView.swift
//  TileSurf
//
//  Created by Saad Ata on 11/25/25.
//
//  macOS exposes a draggable NSSplitView so users can resize tile panes
//  arbitrarily. iOS deliberately ships read-only built-in layouts (per the
//  design call to skip the custom tiling system there), so on iOS we fall
//  back to a static HStack/VStack that hands every child an equal slice.
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit

class StyledSplitView: NSSplitView {
    override var dividerColor: NSColor {
        return NSColor(white: 0.2, alpha: 1.0)
    }
}

struct CustomSplitView: NSViewRepresentable {
    @Binding var direction: SplitDirection?
    @Binding var children: [TileViewModel]?
    @Binding var focusedTile: TileViewModel
    @Binding var browserMode: BrowserMode
    @Binding var hoveredTile: TileViewModel?
    @Binding var hoverPosition: SplitDirection?
    let deleteTile: (TileViewModel) -> Void
    let onLayoutChanged: () -> Void

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = StyledSplitView()
        splitView.dividerStyle = .thick
        splitView.delegate = context.coordinator
        buildView(splitView)
        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        let currentChildIds = splitView.arrangedSubviews.compactMap {
            ($0 as? NSHostingView<TileContainerView>)?.rootView.tile.id
        }
        let newChildIds = children?.map { $0.id }

        if currentChildIds != newChildIds ||
            splitView.arrangedSubviews.count != children?.count
        {
            splitView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            buildView(splitView)
        }
    }

    private func buildView(_ splitView: NSSplitView) {
        splitView.isVertical = (direction == .horizontal)
        var prevSize: CGSize? = nil

        for child in children ?? [] {
            if let size = child.data.size {
                prevSize = size
            }
        }

        for (index, child) in children?.enumerated() ?? [].enumerated() {
            let hostingView = NSHostingView(rootView:
                TileContainerView(
                    tile: child,
                    focusedTile: $focusedTile,
                    browserMode: $browserMode,
                    hoveredTile: $hoveredTile,
                    hoverPosition: $hoverPosition,
                    deleteTile: deleteTile,
                    onLayoutChanged: onLayoutChanged
                )
            )

            // TODO: holy sus fix this asap
            let initialSize: CGSize = child.data.size != nil ? child.data.size! :
                prevSize != nil ? prevSize! :
            NSSize(
                width: splitView.bounds.width > 0 ? splitView.bounds.width : 5000,
                height: splitView.bounds.height > 0 ? splitView.bounds.height : 5000
            )

            hostingView.frame = NSRect(origin: .zero, size: initialSize)
            splitView.addArrangedSubview(hostingView)
            splitView.setHoldingPriority(.defaultLow, forSubviewAt: index)
        }
    }

    func makeCoordinator() -> SplitViewCoordinator {
        SplitViewCoordinator(parent: self)
    }
}

class SplitViewCoordinator: NSObject, NSSplitViewDelegate {
    var parent: CustomSplitView

    init(parent: CustomSplitView) {
        self.parent = parent
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView else { return }
        let sizes = splitView.arrangedSubviews.map { $0.frame.size }
        guard sizes.count == 2,
              parent.children?.count == 2
        else { return }

        parent.children?[0].data.size = sizes[0]
        parent.children?[1].data.size = sizes[1]
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return false
    }

    func splitView(_ splitView: NSSplitView,
                   constrainSplitPosition proposed: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        let minVal: CGFloat = 60

        let total = splitView.isVertical
            ? splitView.bounds.width
            : splitView.bounds.height

        let maxVal = total - minVal

        return min(max(proposed, minVal), maxVal)
    }

    func splitView(_ splitView: NSSplitView,
                   shouldAdjustSizeOfSubview view: NSView) -> Bool {
        return false
    }
}

#else

// iOS: a non-resizable H/VStack with weighted children. The per-child
// `data.size` set in BuiltInLayouts (e.g. 1600×140 for the shift light row,
// 1600×860 for the inner row underneath) is used as a layout *weight* so the
// shift light stays a thin strip instead of getting 50% of the screen. Drag
// resize isn't supported here — the built-in layouts ship as-is on iOS.
struct CustomSplitView: View {
    @Binding var direction: SplitDirection?
    @Binding var children: [TileViewModel]?
    @Binding var focusedTile: TileViewModel
    @Binding var browserMode: BrowserMode
    @Binding var hoveredTile: TileViewModel?
    @Binding var hoverPosition: SplitDirection?
    let deleteTile: (TileViewModel) -> Void
    let onLayoutChanged: () -> Void

    var body: some View {
        let kids = children ?? []
        GeometryReader { geo in
            let weights = kids.map { weight(for: $0) }
            let totalWeight = max(weights.reduce(0, +), 1)
            let isHorizontal = direction == .horizontal

            if isHorizontal {
                HStack(spacing: 0) {
                    ForEach(kids.indices, id: \.self) { i in
                        tileContainer(kids[i])
                            .frame(width: geo.size.width * weights[i] / totalWeight,
                                   height: geo.size.height)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(kids.indices, id: \.self) { i in
                        tileContainer(kids[i])
                            .frame(width: geo.size.width,
                                   height: geo.size.height * weights[i] / totalWeight)
                    }
                }
            }
        }
    }

    private func weight(for child: TileViewModel) -> CGFloat {
        guard let size = child.data.size else { return 1 }
        let raw = direction == .horizontal ? size.width : size.height
        return max(raw, 1)
    }

    private func tileContainer(_ child: TileViewModel) -> some View {
        TileContainerView(
            tile: child,
            focusedTile: $focusedTile,
            browserMode: $browserMode,
            hoveredTile: $hoveredTile,
            hoverPosition: $hoverPosition,
            deleteTile: deleteTile,
            onLayoutChanged: onLayoutChanged
        )
    }
}

#endif
