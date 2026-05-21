////
////  SideBarView.swift
////  TileSurf
////
////  Created by Saad Ata on 12/1/25.
////
////  Sidebar styled with the same palette as the rest of the app: dark
////  appBackground, hairline white-opacity borders, orange as the live accent
////  (matching ignition / gauges / shift buttons elsewhere). The previous
////  iteration leaned on a peachy salmon "sidebarAccent" that ended up feeling
////  unrelated to the dashboard surfaces.
////

import Foundation
import SwiftUI

// MARK: - Constants

private let rowPaddingH: CGFloat = 12
private let rowPaddingV: CGFloat = 7
private let rowCornerRadius: CGFloat = 6
private let hoverFill = Color.white.opacity(0.05)
private let selectedFill = Color.orange.opacity(0.12)
private let selectedBorder = Color.orange.opacity(0.45)
private let subtleBorder = Color.white.opacity(0.10)
private let primaryText = Color.white
private let dimText = Color.white.opacity(0.65)
private let mutedText = Color.white.opacity(0.45)
private let activeDot = Color.orange
private let inactiveDot = Color.white.opacity(0.20)

// MARK: - Sidebar

struct SideBarView: View {
    @ObservedObject private var tileStore: TileStore = .shared
    @ObservedObject private var engineLibrary: EngineLibrary = .shared
    @ObservedObject var rootViewModel: RootViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader()

            ScrollView {
                VStack(spacing: 18) {
                    layoutsSection
                    enginesSection
                }
                .padding(.vertical, 14)
            }

            Spacer(minLength: 0)

            SidebarFooter()
        }
        .background(Color.appBackground)
    }

    private var enginesSection: some View {
        SidebarSection(title: "ENGINES") {
            BuildEngineButton(action: { rootViewModel.startEngineBuild() })
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            ForEach(engineLibrary.entries) { entry in
                EngineRow(
                    entry: entry,
                    isSelected: engineLibrary.selectedEngineId == entry.id,
                    isLocked: engineLibrary.isPaywalled(entry.id) && !purchaseManager.isPro,
                    onSelect: { selectEngine(entry) },
                    onDelete: { engineLibrary.deleteUserEngine(id: entry.id) }
                )
            }
        }
    }

    private var layoutsSection: some View {
        SidebarSection(title: "LAYOUTS") {
            // Saved layouts. The one matching activeLayoutId is highlighted
            // — but only while the user hasn't edited it. The moment they
            // split or delete a tile, isLayoutDirty flips, the highlight
            // moves to the "Unsaved" row below, and this one goes idle.
            ForEach(tileStore.layouts, id: \.id) { layout in
                LayoutRow(
                    layout: layout,
                    isSelected: !rootViewModel.isLayoutDirty && rootViewModel.activeLayoutId == layout.id,
                    action: {
                        rootViewModel.loadState(newRootData: layout.rootData, layoutId: layout.id)
                    },
                    onDelete: { deleteLayout(layout) }
                )
            }

            // The pending unsaved working layout. Appears only while there
            // are real unsaved edits, becomes a normal LayoutRow with the
            // user-supplied name as soon as they save.
            if rootViewModel.isLayoutDirty {
                UnsavedLayoutRow(onSave: { rootViewModel.presentSaveLayout() })
            }
        }
    }

    /// Switch to `entry` if it's free or the user owns Pro; otherwise raise
    /// the paywall and leave the current selection alone.
    private func selectEngine(_ entry: EngineEntry) {
        if engineLibrary.isPaywalled(entry.id) {
            purchaseManager.gatePro {
                engineLibrary.selectedEngineId = entry.id
            }
        } else {
            engineLibrary.selectedEngineId = entry.id
        }
    }

    private func deleteLayout(_ layout: TileLayout) {
        if rootViewModel.activeLayoutId == layout.id {
            rootViewModel.activeLayoutId = nil
        }
        tileStore.deleteLayout(layout)
    }
}

// MARK: - Header

struct SidebarHeader: View {
    var body: some View {
        VStack(spacing: 0) {
            // Centered branding — no trailing Spacer so the engine glyph
            // and "engine-sim" text sit together in the middle of the
            // sidebar header instead of hugging the leading edge.
            HStack(spacing: 10) {
                Image(systemName: "engine.combustion.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                Text("engine-sim")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle().fill(subtleBorder).frame(height: 1)
        }
    }
}

// MARK: - Section

struct SidebarSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .modifier(RetroFont(size: 10, weight: .bold))
                .foregroundColor(mutedText)
                .tracking(1.2)
                .padding(.horizontal, 16)

            VStack(spacing: 2) {
                content
            }
        }
    }
}

// MARK: - Build Engine CTA
//
// Reads like an "empty slot you can fill" — a dashed hairline outline with
// the same row height/padding as a regular EngineRow, but with a "+" glyph
// and a neutral label. Distinct from the solid-bordered selection rows
// without resorting to gradients or shadow gimmicks.

private struct BuildEngineButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Build New Engine")
                    .font(.system(size: 13, weight: .regular))
                Spacer(minLength: 0)
            }
            .foregroundColor(hovered ? .white : dimText)
            .padding(.horizontal, rowPaddingH)
            .padding(.vertical, rowPaddingV)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: rowCornerRadius)
                    .fill(hovered ? hoverFill : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: rowCornerRadius)
                    .stroke(
                        hovered ? Color.white.opacity(0.35) : Color.white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Open the engine builder")
    }
}

// MARK: - Row primitive

private struct SidebarRow<Content: View, Trailing: View>: View {
    let isSelected: Bool
    let isHovered: Bool
    let onTap: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        let core = HStack(spacing: 10) {
            content()
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, rowPaddingH)
        .padding(.vertical, rowPaddingV)
        .background(
            RoundedRectangle(cornerRadius: rowCornerRadius)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: rowCornerRadius)
                .stroke(isSelected ? selectedBorder : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())

        if let onTap = onTap {
            core.onTapGesture(perform: onTap)
        } else {
            core
        }
    }

    private var background: Color {
        if isSelected { return selectedFill }
        return isHovered ? hoverFill : .clear
    }
}

// MARK: - Engine Row

struct EngineRow: View {
    let entry: EngineEntry
    let isSelected: Bool
    let isLocked: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var hovered = false

    private var subtitle: String {
        var parts = [entry.displacementLabel, "\(entry.cylinderCount) cyl"]
        if entry.isUserBuilt { parts.append("custom") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        SidebarRow(isSelected: isSelected, isHovered: hovered, onTap: onSelect) {
            HStack(spacing: 10) {
                leadingGlyph
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? primaryText : dimText)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(mutedText)
                }
            }
        } trailing: {
            // Hover-only on macOS; iOS has no hover state so we show the
            // trash whenever the row belongs to a user-built engine.
            #if os(macOS)
            if hovered && entry.isUserBuilt {
                deleteButton(label: "Delete this engine")
            }
            #else
            if entry.isUserBuilt {
                deleteButton(label: "Delete this engine")
            }
            #endif
        }
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if isLocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(mutedText)
                .frame(width: 6, height: 6)
        } else {
            Circle()
                .fill(isSelected ? activeDot : inactiveDot)
                .frame(width: 6, height: 6)
        }
    }

    private func deleteButton(label: String) -> some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundColor(mutedText)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - Layout Row

struct LayoutRow: View {
    let layout: TileLayout
    let isSelected: Bool
    let action: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundColor(mutedText)
        }
        .buttonStyle(.plain)
        .help("Delete this layout")
    }

    var body: some View {
        SidebarRow(isSelected: isSelected, isHovered: hovered, onTap: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isSelected ? activeDot : inactiveDot)
                    .frame(width: 6, height: 6)
                Text(layout.name)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? primaryText : dimText)
            }
        } trailing: {
            // Built-in layouts ship with the app and aren't user-deletable
            // — no trash affordance for those rows. macOS uses hover; iOS
            // shows the trash for every user-saved layout (no hover state).
            #if os(macOS)
            if hovered && !layout.isBuiltIn {
                deleteButton
            }
            #else
            if !layout.isBuiltIn {
                deleteButton
            }
            #endif
        }
        .onHover { hovered = $0 }
    }
}

// MARK: - Unsaved Layout Row

/// Ephemeral entry that appears in the layout list once the user starts
/// editing the workspace. Treated visually like any other LayoutRow but
/// italicized, with a save icon on the right. Becomes a normal LayoutRow
/// the moment the user saves and inputs a name.
struct UnsavedLayoutRow: View {
    let onSave: () -> Void
    @State private var hovered = false

    var body: some View {
        SidebarRow(isSelected: true, isHovered: hovered, onTap: onSave) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text("Unsaved")
                    .font(.system(size: 13, weight: .regular).italic())
                    .foregroundColor(primaryText)
            }
        } trailing: {
            Button(action: onSave) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .help("Name and save this workspace")
        }
        .onHover { hovered = $0 }
    }
}

// MARK: - Footer

struct SidebarFooter: View {
    @State private var showingControls = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(subtleBorder).frame(height: 1)
            HStack(spacing: 14) {
                Button(action: {}) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)

                // The keyboard-shortcuts popover only makes sense on macOS
                // where the keyboard drives the dashboard; on iOS the
                // throttle / shift / dyno / clutch live on the top bar.
                #if os(macOS)
                Button(action: { showingControls.toggle() }) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Keyboard shortcuts")
                .popover(isPresented: $showingControls, arrowEdge: .bottom) {
                    ControlsMenuView()
                }
                #endif

                Spacer()

                Button(action: {}) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                        .foregroundColor(mutedText)
                }
                .buttonStyle(.plain)
                .help("Help")
            }
            .padding(14)
        }
    }
}
