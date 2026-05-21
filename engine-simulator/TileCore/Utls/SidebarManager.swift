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
import Combine

#if os(macOS)
import AppKit
#endif

public class SidebarManager: ObservableObject {
    static let shared = SidebarManager()
    private init() {}

    /// Observable sidebar visibility for iOS. macOS uses the responder
    /// chain (NSSplitViewController.toggleSidebar) and ignores this value.
    @Published public var isSidebarHidden: Bool = false

    public func toggleSidebar() {
        #if os(macOS)
        NSApp
            .keyWindow?
            .firstResponder?
            .tryToPerform(
                #selector(NSSplitViewController.toggleSidebar(_:)),
                with: nil
            )
        #else
        isSidebarHidden.toggle()
        #endif
    }
}
