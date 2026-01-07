////
////  SideBarView.swift
////  TileSurf
////
////  Created by Saad Ata on 12/1/25.
////
//
//import Foundation
//import SwiftUI
//
//struct SideBarView: View {
//    @Binding var selection: String
//    @State var bookmarksExpanded: Bool = true
//    @State var layoutsExpanded: Bool = true
//    @ObservedObject var workspaceManager: WorkspaceManager
//    @ObservedObject private var tileStore: TileStore = .shared
//    
//    var body: some View {
//        List(selection: $selection) {
//            UrlHeaderView(
//                rootTile: workspaceManager.selectedVm.rootTile,
//                focusedTile: $workspaceManager.selectedVm.focusedTile,
//                browserMode: $workspaceManager.selectedVm.browserMode,
//                currUrl: $workspaceManager.selectedVm.currUrl
//            )
//            
//            ForEach(workspaceManager.workspaces, id: \.self.id) { vm in
//                Label(vm.id.uuidString, systemImage: "house")
//                    .onTapGesture {
//                        selection = vm.id.uuidString
//                        workspaceManager.selectedVm = vm
//                        workspaceManager.selectedVm.rootTile.debugPrint(configuration: .detailed)
//                    }
//            }
//            
//            Button {
//                workspaceManager.newWorkspace()
//            } label: {
//                Image(systemName: "macwindow.badge.plus")
//            }
//            
//            Label("History", systemImage: "square.grid.2x2")
//                .tag("history")
//            
//            Label("Cookies", systemImage: "shield.lefthalf.filled")
//                .tag("cookies")
//            
//            Label("Settings", systemImage: "gear")
//                .tag("settings")
//            
//            Section {
//                DisclosureGroup("Bookmarks", isExpanded: $bookmarksExpanded) {
//                    ForEach(BookmarkStore.shared.items) { bookmark in
//                        HStack {
//                            Image(systemName: "bookmark")
//                            Text(bookmark.title)
//                        }
//                        .onTapGesture {
//                            workspaceManager.selectedVm.navigateTo(bookmark.url)
//                        }
//                    }
//                }
//                
//            }
//            
//            Section {
//                DisclosureGroup("Layouts", isExpanded: $layoutsExpanded) {
//                    ForEach(tileStore.layouts) { layout in
//                        HStack {
//                            Image(systemName: "layout")
//                            Text(layout.name)
//                        }
//                        .onTapGesture {
//                            workspaceManager.selectedVm.loadState(newRootData: layout.rootData)
//                        }
//                    }
//                }
//                
//            }
//        }
//    }
//}

import Foundation
import SwiftUI

struct SideBarView: View {
    @Binding var selection: String
    @State var bookmarksExpanded: Bool = true
    @State var layoutsExpanded: Bool = true
    @ObservedObject private var tileStore: TileStore = .shared
    @ObservedObject var rootViewModel: RootViewModel
    
    var body: some View {
        VStack() {
            SaveLayoutButton(rootTile: rootViewModel.rootTile)
            
            Section {
                DisclosureGroup(
                    isExpanded: $layoutsExpanded,
                    content: {
                        ForEach(tileStore.layouts) { layout in
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.split.3x3")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentSecondary)
                                Text(layout.name)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                            }
                            .padding(.leading, 8)
                            .onTapGesture {
                                rootViewModel.loadState(newRootData: layout.rootData)
                            }
                        }
                    },
                    label: {
                        Label {
                            Text("Layouts")
                                .font(.system(size: 13, weight: .medium))
                        } icon: {
                            Image(systemName: "rectangle.split.3x3")
                                .foregroundColor(.accentSecondary)
                        }
                    }
                )
            }
        }
    }
}
