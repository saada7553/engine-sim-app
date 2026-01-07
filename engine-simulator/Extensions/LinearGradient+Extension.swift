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
    
    public static let deleteOverlayGradient = LinearGradient(
        stops: [
            .init(color: Color(hue: 0, saturation: 0.8, brightness: 0.9), location: 0.0),
            .init(color: Color(hue: 0.05, saturation: 0.85, brightness: 0.75), location: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let splitPrimaryGradient = LinearGradient(
        stops: [
            .init(color: .accentPrimary.opacity(0.6), location: 0.0),
            .init(color: .accentSecondary.opacity(0.4), location: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
