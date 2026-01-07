//
//  View+CornerRadius.swift
//  TileSurf
//
//  Created by Saad Ata on 12/2/25.
//

import SwiftUI

extension View {
    func customCornerRadius() -> some View {
        self.clipShape(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}
