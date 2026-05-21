//
//  RootView.swift
//  TileSurf
//
//  Created by Saad Ata on 11/25/25.
//

import Foundation
import SwiftUI

struct RootView: View {
    @ObservedObject public var vm: RootViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !vm.isBuildingEngine {
                    CustomTopBar(
                        vm: vm.engineVm,
                        browserMode: $vm.browserMode,
                        isLayoutDirty: vm.isLayoutDirty,
                        onToggleSplit: vm.toggleSplitMode,
                        onToggleDelete: vm.toggleDeleteMode,
                        onSaveLayout: vm.presentSaveLayout
                    )
                }

                Group {
                    if vm.isBuildingEngine {
                        EngineBuilderView(onClose: { vm.finishEngineBuild() })
                    } else {
                        TileContainerView(
                            tile: vm.rootTile,
                            focusedTile: $vm.focusedTile,
                            browserMode: $vm.browserMode,
                            hoveredTile: $vm.hoveredTile,
                            hoverPosition: $vm.hoverPosition,
                            deleteTile: { tile in
                                vm.deleteTile(tile)
                                vm.browserMode = .operational
                            },
                            onLayoutChanged: vm.markLayoutDirty
                        )
                    }
                }
                .toolbarVisibility(.hidden)
            }

            // Subview observes vm.engineVm directly so SwiftUI re-renders
            // whenever failedEngineName changes. Putting @ObservedObject on a
            // nested EngineViewModel reference inside RootView itself wasn't
            // firing updates reliably.
            EngineLoadAlertHost(vm: vm.engineVm)
        }
        .alert("Save Workspace", isPresented: $vm.isPresentingSaveLayout) {
            TextField("Layout Name", text: $vm.pendingLayoutName)
            Button("Cancel", role: .cancel) { vm.cancelSaveLayout() }
            Button("Save") { vm.confirmSaveLayout() }
                .disabled(vm.pendingLayoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Name this tile arrangement to keep it in your layouts list.")
        }
        .sheet(isPresented: $purchaseManager.isPresentingPaywall) {
            PaywallSheet(manager: purchaseManager)
        }
    }
}

private struct EngineLoadAlertHost: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        if let failedName = vm.failedEngineName {
            EngineLoadErrorOverlay(
                engineName: failedName,
                onDismiss: { vm.acknowledgeEngineLoadError() }
            )
        }
    }
}

// MARK: - Engine load error overlay

private let overlayScrimColor = Color.black.opacity(0.65)
private let overlayCardFill = Color.appBackground
private let overlayCardBorder = Color.white.opacity(0.18)
private let overlayWarningColor = Color.red.opacity(0.9)
private let overlayCornerRadius: CGFloat = 10
private let overlayCardMaxWidth: CGFloat = 420

struct EngineLoadErrorOverlay: View {
    let engineName: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            overlayScrimColor
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(overlayWarningColor)
                    Text("ENGINE FAILED TO LOAD")
                        .modifier(RetroFont(size: 11, weight: .bold))
                        .foregroundColor(overlayWarningColor)
                        .tracking(2)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("\u{201C}\(engineName)\u{201D} couldn\u{2019}t be initialized.")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("The simulator couldn\u{2019}t bring this engine online — ignition and starter won\u{2019}t respond while it\u{2019}s the selected engine. Pick another engine from the sidebar to keep using the app, or edit this one in the engine builder.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("DISMISS")
                            .modifier(RetroFont(size: 11, weight: .bold))
                            .tracking(1.6)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.orange.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.orange.opacity(0.6), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
            .frame(maxWidth: overlayCardMaxWidth)
            .background(
                RoundedRectangle(cornerRadius: overlayCornerRadius)
                    .fill(overlayCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: overlayCornerRadius)
                    .stroke(overlayCardBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.5), radius: 18, y: 8)
        }
        .transition(.opacity)
    }
}
