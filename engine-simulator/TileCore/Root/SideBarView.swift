////
////  SideBarView.swift
////  TileSurf
////
////  Created by Saad Ata on 12/1/25.
////
////  Clean, flat sidebar: a dark appBackground panel, quiet monospaced labels,
////  hairline separators, and rows that highlight with a soft orange tint when
////  selected. No metal bezels or recessed faces — that heavy dash chrome lives
////  on the instrument controls (the top bar), not on navigation. The one
////  accent is the "Build New Engine" button, which carries the blueprint blue
////  of the app icon, kept flat and understated.
////

import Foundation
import SwiftUI

// MARK: - Constants

private let rowPaddingH: CGFloat = 12
private let rowPaddingV: CGFloat = 8
private let rowCorner: CGFloat = Theme.Radius.control
private let rowGutter: CGFloat = 10
private let dotSize: CGFloat = 7

private let selectedFill = Color.accentLive.opacity(0.14)
private let hoverFill = Color.white.opacity(0.05)
private let dividerColor = Color.white.opacity(0.07)

private let primaryText = Color.textPrimary
private let dimText = Color.textSecondary
private let mutedText = Color.textMuted

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
                VStack(alignment: .leading, spacing: 22) {
                    layoutsSection
                    enginesSection
                }
                .padding(.vertical, 16)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            SidebarFooter()
        }
        .background(Color.appBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(dividerColor).frame(width: 1)
        }
    }

    private var enginesSection: some View {
        SidebarSection(title: "ENGINES") {
            BuildEngineButton(action: { rootViewModel.startEngineBuild() })
                .padding(.horizontal, rowGutter)
                .padding(.bottom, 6)

            ForEach(engineLibrary.entries) { entry in
                EngineRow(
                    entry: entry,
                    isSelected: engineLibrary.selectedEngineId == entry.id,
                    isLocked: engineLibrary.isPaywalled(entry.id) && !purchaseManager.isPro,
                    onSelect: { selectEngine(entry) },
                    onEdit: { editEngine(entry) },
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

    /// Open the builder seeded with this user-built engine so the user can
    /// revise and re-save it (overwrites the original by id).
    private func editEngine(_ entry: EngineEntry) {
        guard let spec = entry.spec else { return }
        rootViewModel.startEngineBuild(editing: spec)
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
            HStack(spacing: 9) {
                // Brand glyph stays warm/orange — deliberately not the blue
                // accent, so the nameplate keeps its identity.
                Image(systemName: "engine.combustion.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.accentHeat)
                Text("ENGINE SIM")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.92))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Rectangle().fill(dividerColor).frame(height: 1)
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
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(mutedText)
                .tracking(1.4)
                .padding(.horizontal, 16)

            VStack(spacing: 1) {
                content
            }
        }
    }
}

// MARK: - Indicator dot
//
// The clean stand-in for the dash tell-tale lamps used elsewhere: a small
// filled dot that glows orange on the selected row, and a quiet hollow ring
// when idle. No skeuomorphic lens — this is navigation, so it stays simple.

private struct StatusDot: View {
    let lit: Bool

    var body: some View {
        Circle()
            .fill(lit ? Color.accentLive : Color.clear)
            .overlay(
                Circle().stroke(lit ? Color.clear : Color.white.opacity(0.22),
                                lineWidth: 1)
            )
            .frame(width: dotSize, height: dotSize)
            .shadow(color: lit ? Color.accentLive.opacity(0.7) : .clear, radius: 3)
    }
}

// MARK: - Build Engine CTA
//
// The single creative action — a solid, flat accent-filled button. Row
// selection is only a faint accent wash, so a fully-filled button reads as
// clearly clickable and stands apart, with no gradient.

private struct BuildEngineButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus.square.dashed")
                    .font(.system(size: 14, weight: .bold))
                Text("Build New Engine")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                Spacer()
            }
            .foregroundColor(.white)
            .padding(.horizontal, rowPaddingH)
            .padding(.vertical, rowPaddingV + 2)
            .frame(maxWidth: .infinity)
            // Solid accent fill — a clean, flat primary button. The selected
            // rows are only a faint accent wash, so a fully-filled button reads
            // as distinctly clickable without any gradient.
            .background(
                RoundedRectangle(cornerRadius: rowCorner)
                    .fill(Color.accentLive.opacity(hovered ? 1.0 : 0.92))
            )
            .shadow(color: Color.accentLive.opacity(hovered ? 0.4 : 0.22),
                    radius: hovered ? 6 : 3, y: 1)
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

    private var background: Color {
        if isSelected { return selectedFill }
        return isHovered ? hoverFill : .clear
    }

    var body: some View {
        let core = HStack(spacing: rowGutter) {
            content()
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, rowPaddingH)
        .padding(.vertical, rowPaddingV)
        .background(
            RoundedRectangle(cornerRadius: rowCorner).fill(background)
        )
        .padding(.horizontal, rowGutter)
        .contentShape(Rectangle())

        if let onTap = onTap {
            core.onTapGesture(perform: onTap)
        } else {
            core
        }
    }
}

// MARK: - Engine Row

struct EngineRow: View {
    let entry: EngineEntry
    let isSelected: Bool
    let isLocked: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovered = false

    private var subtitle: String {
        var parts = [entry.displacementLabel, "\(entry.cylinderCount) cyl"]
        if entry.isUserBuilt { parts.append("custom") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        SidebarRow(isSelected: isSelected, isHovered: hovered, onTap: onSelect) {
            HStack(spacing: rowGutter) {
                leadingGlyph
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(isSelected ? primaryText : dimText)
                    Text(subtitle)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(mutedText)
                }
            }
        } trailing: {
            // Edit + delete actions for user-built engines. Hover-gated on
            // macOS; always shown on iOS, which has no hover state.
            #if os(macOS)
            if hovered && entry.isUserBuilt {
                rowActions
            }
            #else
            if entry.isUserBuilt {
                rowActions
            }
            #endif
        }
        .onHover { hovered = $0 }
    }

    private var rowActions: some View {
        HStack(spacing: rowGutter) {
            iconButton(systemName: "slider.horizontal.3", label: "Edit this engine", action: onEdit)
            iconButton(systemName: "trash", label: "Delete this engine", action: onDelete)
        }
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if isLocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(mutedText)
                .frame(width: dotSize, height: dotSize)
        } else {
            StatusDot(lit: isSelected)
        }
    }

    private func iconButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
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
            HStack(spacing: rowGutter) {
                StatusDot(lit: isSelected)
                Text(layout.name)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
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
            HStack(spacing: rowGutter) {
                StatusDot(lit: true)
                Text("Unsaved")
                    .font(.system(size: 13, weight: .regular, design: .monospaced).italic())
                    .foregroundColor(primaryText)
            }
        } trailing: {
            Button(action: onSave) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentLive)
            }
            .buttonStyle(.plain)
            .help("Name and save this workspace")
        }
        .onHover { hovered = $0 }
    }
}

// MARK: - Footer

struct SidebarFooter: View {
    @ObservedObject private var identity = PlayerIdentity.shared
    @State private var showingControls = false
    @State private var showingProfile = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(dividerColor).frame(height: 1)
            HStack(spacing: 16) {
                Button(action: { showingProfile = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle")
                        Text(identity.username.isEmpty ? "SETTINGS" : identity.username.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.0)
                            .lineLimit(1)
                    }
                    .foregroundColor(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Edit your leaderboard name")
                .popover(isPresented: $showingProfile, arrowEdge: .bottom) {
                    UsernameEditorSheet(identity: identity)
                }

                // The keyboard-shortcuts popover only makes sense on macOS
                // where the keyboard drives the dashboard; on iOS the
                // throttle / shift / dyno / clutch live on the top bar.
                #if os(macOS)
                Button(action: { showingControls.toggle() }) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.75))
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
