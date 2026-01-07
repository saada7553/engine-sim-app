//
//  SaveLayoutView.swift
//  TileSurf
//
//  Created by Saad Ata on 11/30/25.
//

import Foundation
import SwiftUI

struct SaveLayoutButton: View {
    @ObservedObject var rootTile: TileViewModel
    @State private var showingSaveDialog = false
    @State private var layoutName = ""
    
    var body: some View {
        Button {
            showingSaveDialog = true
        } label: {
            Image(systemName: "house.fill")
        }
        .alert("Save Layout", isPresented: $showingSaveDialog) {
            TextField("Layout Name", text: $layoutName)
            Button("Cancel", role: .cancel) {
                layoutName = ""
            }
            Button("Save") {
                if !layoutName.isEmpty {
                    TileStore.shared.saveLayout(rootTile: rootTile, layoutName: layoutName)
                    layoutName = ""
                }
            }
            .disabled(layoutName.isEmpty)
        } message: {
            Text("Enter a name for this layout")
        }
    }
}
