//
//  TileStore.swift
//  TileSurf
//
//  Created by Saad Ata on 11/29/25.
//

import Foundation
import SwiftUI
import Combine

class TileStore: ObservableObject {
    @Published var layouts: [TileLayout] = []
    static let shared: TileStore = .init()
    private let filePersistance: FilePersistence
    
    private init(
        filePersistance: FilePersistence = FilePersistence(directory: "TileLayouts")
    ) {
        self.filePersistance = filePersistance
        loadLayouts()
    }
    
    /// During normal runtime, only the TileViewModel stores information about a tile's children.
    /// When capturing a new layout, we take a "snapshot" of this information and save it to the
    /// TileData's corrolated children list for persistance.
    private func syncModelData(_ viewModel: TileViewModel, _ data: TileData) {
        var currData = viewModel.data
        currData.persistantChildren = []
                
        for child in viewModel.children ?? [] {
            // Must update bottom up, do not switch the ordering of these lines.
            syncModelData(child, child.data)
            currData.persistantChildren?.append(child.data)
        }
        
        viewModel.data = currData
    }
        
    func saveLayout(
        rootTile: TileViewModel,
        layoutName: String
    ) {
        syncModelData(rootTile, rootTile.data)
        let rootData = rootTile.data
        
        let newLayout = TileLayout(
            id: UUID(),
            name: layoutName,
            rootData: rootData
        )
        layouts.append(newLayout)
        filePersistance.save(newLayout, to: UUID().uuidString)
        loadLayouts() // Update the UI
    }
    
    func loadLayouts() {
        let saved = filePersistance.load(TileLayout.self)
        layouts = saved
    }
}

struct TileLayout: Identifiable, Codable {
    let id: UUID
    let name: String
    let rootData: TileData
}
