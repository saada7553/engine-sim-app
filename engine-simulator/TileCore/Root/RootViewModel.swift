//
//  RootViewModel.swift
//  TileSurf
//
//  Created by Saad Ata on 11/26/25.
//

import Foundation
import SwiftUI
import Combine
import WebKit

class RootViewModel: ObservableObject, Observable {
    @ObservedObject var engineVm: EngineViewModel
    @Published var rootTile: TileViewModel
    @Published var focusedTile: TileViewModel
    @Published var browserMode: BrowserMode = .operational
    @Published var hoveredTile: TileViewModel?
    @Published var hoverPosition: SplitDirection?
    
    /// Used for window management only.
    let id = UUID()
    
//    init(engineVm: EngineViewModel) {
//        let tile = TileViewModel(engineVm: engineVm)
//        self.engineVm = engineVm
//        self.rootTile = tile
//        self.focusedTile = tile
//    }
    
    init(engineVm: EngineViewModel, data: TileData) {
        hoveredTile = nil
        hoverPosition = nil
        browserMode = .operational
        let newTile = TileViewModel(engineVm: engineVm, data: data)
        rootTile = newTile
        focusedTile = newTile
        self.engineVm = engineVm
    }
    
    func loadState(newRootData: TileData) {
        hoveredTile = nil
        hoverPosition = nil
        browserMode = .operational
        rootTile = TileViewModel(engineVm: engineVm, data: newRootData)
        focusedTile = findFirstLeaf(in: rootTile)
    }
    
    func deleteTile(_ tileToDelete: TileViewModel) {
        if deleteTileRecursive(in: rootTile, tileToDelete: tileToDelete) {
            focusedTile = findFirstLeaf(in: rootTile)
        }
    }
    
    func deleteTileRecursive(in parent: TileViewModel, tileToDelete: TileViewModel) -> Bool {
        guard let children = parent.children else { return false }
        
        if let index = children.firstIndex(where: { $0.data.id == tileToDelete.data.id }) {
            let remainingChild = children[index == 0 ? 1 : 0]
            
            parent.objectWillChange.send()
            TileViewModel.copyData(from: remainingChild, to: parent)
            
            if let grandchildren = remainingChild.children {
                DispatchQueue.main.async {
                    parent.children = grandchildren
                }
            }
                
            // TODO: delete the view 
//            if let webView = tileToDelete.view {
//                webView.stopLoading()
//                webView.navigationDelegate = nil
//                webView.uiDelegate = nil
//                webView.removeFromSuperview()
//                // TODO: fix this nonsense 
//                webView.setAllMediaPlaybackSuspended(true)
//            }
            
            return true
        }
        
        for child in children {
            if deleteTileRecursive(in: child, tileToDelete: tileToDelete) {
                return true
            }
        }
        
        return false
    }
    
    func findFirstLeaf(in tile: TileViewModel) -> TileViewModel {
        if tile.isLeaf { return tile }
        if let children = tile.children,
           let first = children.first {
            return findFirstLeaf(in: first)
        }
        return tile
    }
}

enum BrowserMode {
    case operational
    case split
    case delete
}
