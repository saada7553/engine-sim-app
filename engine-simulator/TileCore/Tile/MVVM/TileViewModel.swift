//
//  TileViewModel.swift
//  TileSurf
//
//  Created by Saad Ata on 11/29/25.
//

import Foundation
import SwiftUI
import Combine

class TileViewModel: Identifiable, ObservableObject, Equatable {
    @ObservedObject var engineVm: EngineViewModel
    @Published var data: TileData
    @Published var children: [TileViewModel]?
//    @Published var view: AnyView?
    
    init(engineVm: EngineViewModel,
         data: TileData,
//         view: AnyView? = nil
    ) {
        self.engineVm = engineVm
        self.data = data
        self.data.id = UUID()
//        self.view = view
        
        if let persistantChildren = data.persistantChildren {
            self.children = persistantChildren.map { childData in
                TileViewModel(engineVm: engineVm, data: childData)
            }
        }
    }
    
    var isLeaf: Bool {
        // TODO: sus, maybe make non optional
        children == nil || (children?.isEmpty ?? true)
    }
    
    static func == (lhs: TileViewModel, rhs: TileViewModel) -> Bool {
        lhs.data.id == rhs.data.id
    }
    
    static func copyData(from: TileViewModel, to: TileViewModel) {
        to.data = from.data
        to.children = from.children
//        to.view = from.view
    }
    
    func debugPrint(
        prefix: String = "",
        isLast: Bool = true,
        configuration: TileDebugConfiguration = .basic
    ) {
        let branch = isLast ? "└─" : "├─"
        let nextPrefix = prefix + (isLast ? "   " : "│  ")

        print("\(prefix)\(branch) Tile(id: \(data.id.uuidString))")
        print("\(nextPrefix)type: \(data.type)")
        
        if(configuration == .detailed) {
            print("\(nextPrefix)splitDirection: \(data.splitDirection.map { "\($0)" } ?? "nil")")
            print("\(nextPrefix)isLeaf: \(isLeaf)")
            print("\(nextPrefix)size: \(data.size ?? CGSize.zero)")
        }
        
        if let children = children, !children.isEmpty {
            print("\(nextPrefix)children:")
            for (index, child) in children.enumerated() {
                let isLastChild = index == children.count - 1
                child.debugPrint(
                    prefix: nextPrefix,
                    isLast: isLastChild,
                    configuration: configuration
                )
            }
        }
    }
}

enum TileDebugConfiguration {
    case basic
    case detailed
}
