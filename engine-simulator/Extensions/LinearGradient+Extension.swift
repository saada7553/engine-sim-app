//
//  LinearGradient+Extension.swift
//  TileSurf
//
//  Created by Saad Ata on 12/2/25.
//

import Foundation
import SwiftUI

extension LinearGradient {
    public static let tileViewBorderGradient: LinearGradient = LinearGradient(
        stops: [
            .init(color: .accentPrimary.opacity(1), location: 0.0),
            .init(color: .accentSecondary.opacity(0.8), location: 0.5),
            .init(color: .accentTertiary.opacity(0.9), location: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
