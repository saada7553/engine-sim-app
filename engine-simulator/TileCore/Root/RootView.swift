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
        Group {
            if vm.isBuildingEngine {
                EngineBuilderView(onClose: { vm.finishEngineBuild() })
            } else {
                TileContainerView(
                    tile: vm.rootTile,
                    focusedTile: $vm.focusedTile,
                    browserMode: $vm.browserMode,
                    hoveredTile: $vm.hoveredTile,
                    hoverPosition: $vm.hoverPosition
                ) { tile in
                    vm.deleteTile(tile)
                    vm.browserMode = .operational
                }
            }
        }
        .toolbar(removing: .title)
    }
}
