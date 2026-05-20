//
//  CustomSplitView.swift
//  TileSurf
//
//  Created by Saad Ata on 11/25/25.
//

import Foundation
import SwiftUI

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
