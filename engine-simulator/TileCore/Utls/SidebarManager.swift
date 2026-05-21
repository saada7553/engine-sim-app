//
//  SidebarManager.swift
//  TileSurf
//
//  Created by Saad Ata on 11/27/25.
//
//  macOS routes cmd+B through to the responder chain so the system handles
//  the NavigationSplitView toggle. iOS doesn't have NSApp / responder
//  chain in the same shape — the sidebar there folds automatically via
//  NavigationSplitView's built-in toolbar control, so the keyboard shortcut
//  collapses to a no-op.
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

public class SidebarManager {
    static let shared = SidebarManager()
    private init() {}

    public func toggleSidebar() {
        #if os(macOS)
        NSApp
            .keyWindow?
            .firstResponder?
            .tryToPerform(
                #selector(NSSplitViewController.toggleSidebar(_:)),
                with: nil
            )
        #endif
    }
}
