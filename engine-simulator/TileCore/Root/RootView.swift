//
//  RootView.swift
//  TileSurf
//
//  Created by Saad Ata on 11/25/25.
//

import Foundation
import SwiftUI

struct RootView: View {
    @ObservedObject public var vm: RootViewModel

    var body: some View {
        VStack(spacing: 0) {
            if !vm.isBuildingEngine {
                CustomTopBar(
                    vm: vm.engineVm,
                    browserMode: $vm.browserMode,
                    isLayoutDirty: vm.isLayoutDirty,
                    onToggleSplit: vm.toggleSplitMode,
                    onToggleDelete: vm.toggleDeleteMode,
                    onSaveLayout: vm.presentSaveLayout
                )
            }

            Group {
                if vm.isBuildingEngine {
                    EngineBuilderView(onClose: { vm.finishEngineBuild() })
                } else {
                    TileContainerView(
                        tile: vm.rootTile,
                        focusedTile: $vm.focusedTile,
                        browserMode: $vm.browserMode,
                        hoveredTile: $vm.hoveredTile,
                        hoverPosition: $vm.hoverPosition,
                        deleteTile: { tile in
                            vm.deleteTile(tile)
                            vm.browserMode = .operational
                        },
                        onLayoutChanged: vm.markLayoutDirty
                    )
                }
            }
            .toolbarVisibility(.hidden)
        }
        .alert("Save Workspace", isPresented: $vm.isPresentingSaveLayout) {
            TextField("Layout Name", text: $vm.pendingLayoutName)
            Button("Cancel", role: .cancel) { vm.cancelSaveLayout() }
            Button("Save") { vm.confirmSaveLayout() }
                .disabled(vm.pendingLayoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Name this tile arrangement to keep it in your layouts list.")
        }
    }
}
