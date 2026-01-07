//
//  SelectView.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import SwiftUI

struct SelectView: View {
    @ObservedObject var tile: TileViewModel
    
    var body: some View {
        List {
            Section(header: Text("Views")) {
                ForEach(TileType.allCases.filter { $0 != .select }) { type in
                    Button(action: {
                        tile.data.type = type
                    }) {
                        Text(type.rawValue)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .background(Color.black)
    }
}
