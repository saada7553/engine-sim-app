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
    /// Built-ins (ordered, immutable) are always shown first, then the user's
    /// saved layouts. Built-ins live entirely in code so they ship with the
    /// .app bundle and cannot be deleted or persisted.
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
            rootData: rootData,
            isBuiltIn: false
        )
        filePersistance.save(newLayout, to: UUID().uuidString)
        loadLayouts() // Update the UI
    }

    /// Layouts are persisted under randomly named files, so locate the file
    /// whose decoded contents match the layout id before removing it. Built-in
    /// layouts have no file on disk — this is a guarded no-op for them.
    func deleteLayout(_ layout: TileLayout) {
        guard !layout.isBuiltIn else { return }
        for file in filePersistance.listFiles() {
            if let stored = filePersistance.load(TileLayout.self, from: file),
               stored.id == layout.id {
                filePersistance.delete(file: file)
            }
        }
        loadLayouts()
    }

    func loadLayouts() {
        let saved = filePersistance.load(TileLayout.self)
        layouts = BuiltInLayouts.all + saved
    }
}

struct TileLayout: Identifiable, Codable {
    let id: UUID
    let name: String
    let rootData: TileData
    /// Whether this layout ships with the app (immutable, no disk file).
    var isBuiltIn: Bool

    init(id: UUID, name: String, rootData: TileData, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.rootData = rootData
        self.isBuiltIn = isBuiltIn
    }

    /// Custom decoder so user layouts saved before `isBuiltIn` existed still
    /// load — Swift's synthesized init(from:) ignores stored-property
    /// defaults and would throw on a missing key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.rootData = try c.decode(TileData.self, forKey: .rootData)
        self.isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rootData, isBuiltIn
    }
}
