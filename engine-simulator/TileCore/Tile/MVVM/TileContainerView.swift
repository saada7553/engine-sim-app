//
//  TileContainerView.swift
//  TileSurf
//
//  Created by Saad Ata on 11/25/25.
//

import Foundation
import SwiftUI
import WebKit

struct TileContainerView: View {
    @ObservedObject var tile: TileViewModel
    @Binding var focusedTile: TileViewModel
    @Binding var browserMode: BrowserMode
    @Binding var hoveredTile: TileViewModel?
    @Binding var hoverPosition: SplitDirection?
    let deleteTile: (TileViewModel) -> Void
    /// Called whenever the tile tree changes — split / delete / etc. — so
    /// the workspace can flag the layout as having unsaved changes.
    let onLayoutChanged: () -> Void
    
    var body: some View {
        if tile.isLeaf {
            tileView
        } else if let children = tile.children,
                  let direction = tile.data.splitDirection
        {
            splitView(direction, children)
        }
    }
    
    var tileView: some View {
        TileView(
            tile: tile,
            isFocused: focusedTile.id == tile.id,
            browserMode: browserMode,
            isHovered: hoveredTile?.id == tile.id,
            hoverPosition: hoverPosition,
            onTap: {
                focusedTile = tile
            },
            onDelete: {
                deleteTile(tile)
            },
            onSplit: { direction, isLeftOrTop in
                splitTile(tile, direction: direction, isLeftOrTop: isLeftOrTop)
                onLayoutChanged()
            },
            onHover: { position in
                if hoveredTile != tile || hoverPosition != position {
                    hoveredTile = tile
                    hoverPosition = position
                }
            },
            onHoverEnd: {
                if hoveredTile?.id == tile.id {
                    hoveredTile = nil
                    hoverPosition = nil
                }
            }
        )
    }
    
    func splitView(
        _ direction: SplitDirection,
        _ children: [TileViewModel]
    ) -> some View {
        CustomSplitView(
            direction: $tile.data.splitDirection,
            children: $tile.children,
            focusedTile: $focusedTile,
            browserMode: $browserMode,
            hoveredTile: $hoveredTile,
            hoverPosition: $hoverPosition,
            deleteTile: deleteTile,
            onLayoutChanged: onLayoutChanged
        )
        .toolbar(removing: .title) // sadd
        .id(tile.id)
    }
    
    func splitTile(
        _ tile: TileViewModel,
        direction: SplitDirection,
        isLeftOrTop: Bool
    ) {
        let newTile = TileViewModel(
            engineVm: tile.engineVm,
            data: TileData(id: UUID(), type: .select)
        )
        let existingTile = TileViewModel(
            engineVm: tile.engineVm,
            data: tile.data,
        )
        
        tile.children = isLeftOrTop ? [newTile, existingTile] : [existingTile, newTile]
        tile.data.splitDirection = direction
        
        browserMode = .operational
        hoveredTile = nil
        hoverPosition = nil
        focusedTile = newTile
    }
}
