//
//  SidebarManager.swift
//  TileSurf
//
//  Created by Saad Ata on 11/27/25.
//

import Foundation
import SwiftUI

public class SidebarManager {
    static let shared = SidebarManager()
    private init() {}
    
    public func toggleSidebar() {
        NSApp
            .keyWindow?
            .firstResponder?
            .tryToPerform(
                #selector(NSSplitViewController.toggleSidebar(_:)),
                with: nil
            )
    }
}
