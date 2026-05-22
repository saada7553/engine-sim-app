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

    /// While true, the detail area shows the engine builder instead of the tile layout.
    @Published var isBuildingEngine: Bool = false

    /// The saved engine being edited, if the builder was opened from an
    /// existing user engine. Nil for a fresh build. Cleared when the builder
    /// closes so the next "Build New Engine" starts blank.
    @Published var editingEngineSpec: EngineSpec?

    /// Save-layout dialog state. Lives on the root VM so both the top-bar
    /// save button and the sidebar's save action open the same dialog.
    @Published var isPresentingSaveLayout: Bool = false
    @Published var pendingLayoutName: String = ""

    /// The id of the saved layout currently loaded into the workspace, and
    /// whether the user has modified the tiles since then. Both feed the
    /// sidebar's "Current Workspace" row and the active highlight.
    ///
    /// Persisted to UserDefaults under ``lastActiveLayoutKey`` so the next
    /// launch can re-open whatever the user was using. Resolved against
    /// `TileStore.shared.layouts` (built-ins ∪ user layouts); a missing or
    /// stale id falls back to ``BuiltInLayouts.defaultLayout``.
    @Published var activeLayoutId: UUID? {
        didSet { persistActiveLayoutId() }
    }
    @Published var isLayoutDirty: Bool = false

    static let lastActiveLayoutKey = "lastActiveLayoutId"

    private func persistActiveLayoutId() {
        let defaults = UserDefaults.standard
        if let id = activeLayoutId {
            defaults.set(id.uuidString, forKey: Self.lastActiveLayoutKey)
        } else {
            defaults.removeObject(forKey: Self.lastActiveLayoutKey)
        }
    }

    /// Used for window management only.
    let id = UUID()

    /// Open the builder. Pass `editing:` to revise an existing saved engine;
    /// omit it for a fresh build.
    func startEngineBuild(editing spec: EngineSpec? = nil) {
        browserMode = .operational
        editingEngineSpec = spec
        isBuildingEngine = true
    }

    func finishEngineBuild() {
        isBuildingEngine = false
        editingEngineSpec = nil
    }

    /// Open the save-layout dialog from anywhere in the UI.
    func presentSaveLayout() {
        pendingLayoutName = ""
        isPresentingSaveLayout = true
    }

    /// Commit the current tile tree as a new named layout. No-ops on empty
    /// names so the alert's disabled-when-empty rule is enforced everywhere.
    func confirmSaveLayout() {
        let trimmed = pendingLayoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        TileStore.shared.saveLayout(rootTile: rootTile, layoutName: trimmed)
        // The new layout becomes the active one. We don't know its id ahead
        // of time so fall back to matching by name on the next refresh.
        if let saved = TileStore.shared.layouts.first(where: { $0.name == trimmed }) {
            activeLayoutId = saved.id
        }
        isLayoutDirty = false
        pendingLayoutName = ""
        isPresentingSaveLayout = false
    }

    func cancelSaveLayout() {
        pendingLayoutName = ""
        isPresentingSaveLayout = false
    }

    /// Called by tile operations (split / delete) so the sidebar can show an
    /// "unsaved changes" indicator without diffing tile trees.
    func markLayoutDirty() {
        isLayoutDirty = true
    }

    /// Toggle split-edit mode. While active, hover overlays let the user
    /// drop a new tile by clicking on an existing tile's edge.
    func toggleSplitMode() {
        browserMode = browserMode == .split ? .operational : .split
    }

    /// Toggle delete-edit mode. While active, clicking a tile removes it.
    func toggleDeleteMode() {
        browserMode = browserMode == .delete ? .operational : .delete
    }
    
//    init(engineVm: EngineViewModel) {
//        let tile = TileViewModel(engineVm: engineVm)
//        self.engineVm = engineVm
//        self.rootTile = tile
//        self.focusedTile = tile
//    }
    
    init(engineVm: EngineViewModel, data: TileData, activeLayoutId: UUID? = nil) {
        hoveredTile = nil
        hoverPosition = nil
        browserMode = .operational
        let newTile = TileViewModel(engineVm: engineVm, data: data)
        rootTile = newTile
        focusedTile = newTile
        self.engineVm = engineVm
        self.activeLayoutId = activeLayoutId
    }
    
    func loadState(newRootData: TileData, layoutId: UUID? = nil) {
        hoveredTile = nil
        hoverPosition = nil
        browserMode = .operational
        rootTile = TileViewModel(engineVm: engineVm, data: newRootData)
        focusedTile = findFirstLeaf(in: rootTile)
        activeLayoutId = layoutId
        isLayoutDirty = false
    }

    func deleteTile(_ tileToDelete: TileViewModel) {
        if deleteTileRecursive(in: rootTile, tileToDelete: tileToDelete) {
            focusedTile = findFirstLeaf(in: rootTile)
            markLayoutDirty()
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
