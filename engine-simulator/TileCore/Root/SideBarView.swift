////
////  SideBarView.swift
////  TileSurf
////
////  Created by Saad Ata on 12/1/25.
////

import Foundation
import SwiftUI

struct SideBarView: View {
    @ObservedObject private var tileStore: TileStore = .shared
    @ObservedObject var rootViewModel: RootViewModel
    
    @State private var showingSaveLayoutAlert = false
    @State private var newLayoutName = ""
    @State private var activeLayoutId: UUID?
    
    // Mock data for engines as shown in concept
    private let mockEngines = [
        EngineInfo(name: "Chevy 350 V8", displacement: "5.7L", cylinders: 8, isLoaded: true),
        EngineInfo(name: "Honda B16A", displacement: "1.6L", cylinders: 4, isLoaded: false),
        EngineInfo(name: "Inline 4 demo", displacement: "2.0L", cylinders: 4, isLoaded: false)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader()
            
            ScrollView {
                VStack(spacing: 24) {
                    SidebarSection(title: "ENGINES", action: {}) {
                        ForEach(mockEngines) { engine in
                            EngineRow(engine: engine)
                        }
                    }
                    
                    SidebarSection(title: "LAYOUTS", action: { showingSaveLayoutAlert = true }) {
                        ForEach(Array(tileStore.layouts.enumerated()), id: \.element.id) { index, layout in
                            LayoutRow(
                                layout: layout,
                                hotkey: index < 9 ? "\(index + 1)" : nil,
                                isSelected: activeLayoutId == layout.id,
                                action: {
                                    activeLayoutId = layout.id
                                    rootViewModel.loadState(newRootData: layout.rootData)
                                },
                                onDelete: { deleteLayout(layout) }
                            )
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            
            Spacer()
            
            SidebarFooter()
        }
        .background(Color.appBackground)
        .alert("Save Current Layout", isPresented: $showingSaveLayoutAlert) {
            TextField("Layout Name", text: $newLayoutName)
            Button("Cancel", role: .cancel) { newLayoutName = "" }
            Button("Save") {
                if !newLayoutName.isEmpty {
                    TileStore.shared.saveLayout(rootTile: rootViewModel.rootTile, layoutName: newLayoutName)
                    newLayoutName = ""
                }
            }
            .disabled(newLayoutName.isEmpty)
        } message: {
            Text("Enter a name for this workspace configuration.")
        }
    }

    private func deleteLayout(_ layout: TileLayout) {
        if activeLayoutId == layout.id {
            activeLayoutId = nil
        }
        tileStore.deleteLayout(layout)
    }
}

// MARK: - Components

struct SidebarHeader: View {
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "engine.combustion.fill")
                    .foregroundColor(.sidebarAccent)
                Text("engine-sim")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(16)
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    let action: () -> Void
    let content: Content
    
    init(title: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.action = action
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.sidebarTextSecondary)
                Spacer()
                Button(action: action) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundColor(.sidebarTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            
            VStack(spacing: 4) {
                content
            }
        }
    }
}

struct EngineRow: View {
    let engine: EngineInfo
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(engine.isLoaded ? Color.sidebarAccent : Color.sidebarTextSecondary.opacity(0.3))
                .frame(width: 6, height: 6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.name)
                    .font(.system(size: 14))
                    .foregroundColor(engine.isLoaded ? .white : .white.opacity(0.7))
                Text("\(engine.displacement) · \(engine.cylinders) cyl" + (engine.isLoaded ? " · loaded" : ""))
                    .font(.system(size: 11))
                    .foregroundColor(.sidebarTextSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(engine.isLoaded ? Color.sidebarHighlight : Color.clear)
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }
}

struct LayoutRow: View {
    let layout: TileLayout
    let hotkey: String?
    let isSelected: Bool
    let action: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isSelected ? Color.sidebarAccent : Color.sidebarTextSecondary.opacity(0.3))
                .frame(width: 6, height: 6)

            Text(layout.name)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))

            Spacer()

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.sidebarTextSecondary)
                }
                .buttonStyle(.plain)
            } else if let hotkey = hotkey {
                HStack(spacing: 2) {
                    Image(systemName: "command")
                    Text(hotkey)
                }
                .font(.system(size: 10))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.appBackground)
                .cornerRadius(4)
                .foregroundColor(.sidebarTextSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isSelected ? Color.sidebarHighlight : Color.clear)
        .cornerRadius(6)
        .padding(.horizontal, 8)
        .onTapGesture(perform: action)
        .onHover { isHovered = $0 }
    }
}

struct SidebarFooter: View {
    @State private var showingControls = false

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.05))
            HStack {
                Button(action: {}) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button(action: { showingControls.toggle() }) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .popover(isPresented: $showingControls, arrowEdge: .bottom) {
                    ControlsMenuView()
                }

                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.sidebarTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }
}

// MARK: - Models

struct EngineInfo: Identifiable {
    let id = UUID()
    let name: String
    let displacement: String
    let cylinders: Int
    let isLoaded: Bool
}
