//
//  EngineBuilderView.swift
//  engine-simulator
//
//  Top-level builder coordinator. Replaces the tile layout when the user
//  hits the + button in the ENGINES sidebar section.
//
//  Layout is a fixed sidebar of sections on the left, a scrollable detail
//  panel on the right, and a header with the engine name + save/cancel.
//  All sections are reachable in any order; save is enabled as soon as the
//  name is valid.
//

import SwiftUI
import Combine

// MARK: - Layout constants

private enum BuilderLayout {
    static let sectionRailWidth: CGFloat = 200
    static let detailHorizontalPadding: CGFloat = 40
    static let detailVerticalPadding: CGFloat = 28
    static let headerVerticalPadding: CGFloat = 14
    static let headerHorizontalPadding: CGFloat = 24
    static let sectionRowHeight: CGFloat = 32
    static let sectionGroupSpacing: CGFloat = 18
}

// MARK: - Section grouping

/// Visual grouping of the sections in the left rail. Each step belongs to
/// exactly one group; groups exist only for the rail's section dividers.
private enum BuilderSectionGroup: String, CaseIterable {
    case identity
    case engine
    case timing
    case airflow
    case drivetrain
    case finalize

    var label: String {
        switch self {
        case .identity:   return "Identity"
        case .engine:     return "Engine"
        case .timing:     return "Timing"
        case .airflow:    return "Air & fuel"
        case .drivetrain: return "Drivetrain"
        case .finalize:   return "Finalize"
        }
    }

    var steps: [BuilderStep] {
        switch self {
        case .identity:   return [.identity]
        case .engine:     return [.layout, .bottomEnd]
        case .timing:     return [.cam, .firingOrder, .ignitionFuel]
        case .airflow:    return [.induction, .exhaust]
        case .drivetrain: return [.transmission, .vehicle]
        case .finalize:   return [.advanced, .review]
        }
    }
}

// MARK: - Steps

enum BuilderStep: Int, CaseIterable, Identifiable {
    case identity
    case layout
    case bottomEnd
    case cam
    case firingOrder
    case induction
    case exhaust
    case ignitionFuel
    case transmission
    case vehicle
    case advanced
    case review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .identity:     return "Identity"
        case .layout:       return "Layout"
        case .bottomEnd:    return "Sizing"
        case .cam:          return "Camshaft"
        case .firingOrder:  return "Firing Order"
        case .induction:    return "Induction"
        case .exhaust:      return "Exhaust"
        case .ignitionFuel: return "Ignition · Fuel"
        case .transmission: return "Transmission"
        case .vehicle:      return "Vehicle"
        case .advanced:     return "Advanced"
        case .review:       return "Review"
        }
    }
}

// MARK: - Builder phase

/// The builder opens on a mode chooser, then either drops straight into the
/// manual wizard or runs the AI prompt first. AI generation lands the user in
/// the same wizard (at Review) so they can tweak before saving.
enum BuilderPhase {
    case chooseMode
    case aiPrompt
    case editing
}

// MARK: - Builder state

final class EngineBuilderState: ObservableObject {
    @Published var spec: EngineSpec
    @Published var step: BuilderStep = .identity
    @Published var phase: BuilderPhase

    /// Set when a save is rejected because the name or description failed the
    /// content check. Drives the inline error on the Identity step and pins
    /// `nameContentError` / `descriptionContentError` to the right field.
    @Published var contentRejection: EngineContentValidator.Rejection?
    /// True while the async content check runs, so the Save button can show a
    /// pending state and not be tapped twice.
    @Published var isValidatingContent = false

    /// True when the builder was opened on an existing saved engine. Editing
    /// reuses the spec's id, so saving overwrites the original entry rather
    /// than creating a duplicate. Also drives the "Save Changes" header label.
    let isEditingExisting: Bool

    /// Open the builder. With no `editing` spec this is a fresh build that may
    /// start on the mode chooser; passing an existing spec drops straight into
    /// the wizard so the user can revise the engine they already saved.
    init(editing spec: EngineSpec? = nil) {
        if let spec = spec {
            self.spec = spec
            self.isEditingExisting = true
            // No mode chooser when revising an existing engine — the spec is
            // already authored, so go straight into the wizard.
            self.phase = .editing
        } else {
            self.spec = .defaultSpec()
            self.isEditingExisting = false
            // The mode chooser only earns its place when on-device AI is actually
            // available. Otherwise there's nothing to choose — go straight into
            // the manual wizard.
            self.phase = AIEngineGeneration.availability.isAvailable ? .chooseMode : .editing
        }
    }

    func jump(to step: BuilderStep) { self.step = step }

    /// Enter the manual wizard from scratch.
    func startManual() {
        step = .identity
        phase = .editing
    }

    /// Adopt an AI-generated spec and drop into the wizard's Review step so the
    /// user can verify and fine-tune everything before saving.
    func adoptGenerated(_ spec: EngineSpec) {
        self.spec = spec
        step = .review
        phase = .editing
    }

    var nameIsValid: Bool {
        !spec.name.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty
    }

    /// The rejection reason to show under the name field, if the name is what
    /// failed the content check.
    var nameContentError: String? {
        contentRejection?.field == .name ? contentRejection?.reason : nil
    }

    /// The rejection reason to show under the description field, if that's what
    /// failed the content check.
    var descriptionContentError: String? {
        contentRejection?.field == .description ? contentRejection?.reason : nil
    }

    /// Clear a stale content rejection once the user edits the offending field,
    /// so the error doesn't linger while they fix it.
    func clearContentRejection() {
        if contentRejection != nil { contentRejection = nil }
    }
}

// MARK: - View

struct EngineBuilderView: View {
    let onClose: () -> Void
    @StateObject private var state: EngineBuilderState

    /// `editingSpec` seeds the wizard with an existing saved engine; nil opens
    /// a fresh build.
    init(editingSpec: EngineSpec? = nil, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _state = StateObject(wrappedValue: EngineBuilderState(editing: editingSpec))
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            switch state.phase {
            case .chooseMode:
                BuilderModeChooser(
                    onManual: { state.startManual() },
                    onAI: { state.phase = .aiPrompt },
                    onCancel: onClose
                )
            case .aiPrompt:
                AIEnginePromptView(
                    onGenerated: { state.adoptGenerated($0) },
                    onBack: { state.phase = .chooseMode },
                    onCancel: onClose
                )
            case .editing:
                editor
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            BuilderHeader(state: state, onClose: onClose, onSave: save)
            Divider().background(BuilderTheme.line)

            HStack(spacing: 0) {
                BuilderSectionRail(state: state)
                    .frame(width: BuilderLayout.sectionRailWidth)
                Divider().background(BuilderTheme.line)

                ScrollView {
                    stepContent
                        .padding(.horizontal, BuilderLayout.detailHorizontalPadding)
                        .padding(.vertical, BuilderLayout.detailVerticalPadding)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch state.step {
        case .identity:     IdentityStep(state: state)
        case .layout:       LayoutStep(state: state)
        case .bottomEnd:    BottomEndStep(state: state)
        case .cam:          CamStep(state: state)
        case .firingOrder:  FiringOrderStep(state: state)
        case .induction:    InductionStep(state: state)
        case .exhaust:      ExhaustStep(state: state)
        case .ignitionFuel: IgnitionFuelStep(state: state)
        case .transmission: TransmissionStep(state: state)
        case .vehicle:      VehicleStep(state: state)
        case .advanced:     AdvancedStep(state: state)
        case .review:       ReviewStep(state: state)
        }
    }

    private func save() {
        guard !state.isValidatingContent else { return }
        // Screen the name + description before anything else. A shared engine's
        // text is public (community board / leaderboard), so an objectionable
        // name or description must never be committed to the library — the only
        // place a publishable engine can come from. This runs ahead of the Pro
        // gate so bad text can't even reach the paywall.
        state.isValidatingContent = true
        Task {
            let rejection = await EngineContentValidator.validate(
                name: state.spec.name,
                description: state.spec.engineDescription)
            await MainActor.run {
                state.isValidatingContent = false
                if let rejection {
                    state.contentRejection = rejection
                    state.step = .identity   // surface the offending field
                    return
                }
                commitSave()
            }
        }
    }

    /// Commit the validated engine. Gated: designing is free, but committing to
    /// the library is a Pro feature — PurchaseManager raises the paywall when the
    /// user isn't entitled; the save + close run on a Pro user.
    private func commitSave() {
        PurchaseManager.shared.gatePro {
            EngineLibrary.shared.saveUserEngine(state.spec)
            onClose()
        }
    }
}

// MARK: - Header

private struct BuilderHeader: View {
    @ObservedObject var state: EngineBuilderState
    let onClose: () -> Void
    let onSave: () -> Void

    private var saveButtonLabel: String {
        if state.isValidatingContent { return "Checking…" }
        return state.isEditingExisting ? "Save Changes" : "Save Engine"
    }

    /// Live build warnings, recomputed on every edit so the Save button can flag
    /// them even when the user never opens the Review step. Cheap, pure
    /// arithmetic, same recompute-per-edit pattern as the cost chip.
    private var warnings: [BuildWarning] { EngineSpecValidator.warnings(for: state.spec) }
    private var hasCriticalWarning: Bool { warnings.contains { $0.severity == .critical } }

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 10) {
                Text("ENGINE BUILDER")
                    .font(.system(size: Theme.FontSize.control, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.white)
                Rectangle()
                    .fill(BuilderTheme.accent)
                    .frame(width: 6, height: 6)
                Text(state.spec.name.isEmpty ? "Untitled" : state.spec.name)
                    .font(.system(size: Theme.FontSize.control, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                if state.spec.layout.cylinderCount > 0 {
                    Text("·")
                        .foregroundColor(BuilderTheme.label)
                    Text("\(state.spec.layout.displayName) · \(String(format: "%.2fL", state.spec.displacementLitres))")
                        .font(.system(size: Theme.FontSize.callout, weight: .regular, design: .monospaced))
                        .foregroundColor(BuilderTheme.label)
                }
            }

            Spacer()

            BuildCostChip(spec: state.spec)

            BuilderNavButton(label: "Cancel", style: .secondary,
                             action: onClose)
            BuilderNavButton(label: saveButtonLabel,
                             style: .primary,
                             enabled: state.nameIsValid && !state.isValidatingContent,
                             action: onSave)
                .overlay(alignment: .topTrailing) {
                    if !warnings.isEmpty {
                        SaveWarningBadge(count: warnings.count, hasCritical: hasCriticalWarning)
                            .offset(x: 7, y: -7)
                            .help("\(warnings.count) build warning\(warnings.count == 1 ? "" : "s"). Open Review to see details.")
                    }
                }
        }
        .padding(.horizontal, BuilderLayout.headerHorizontalPadding)
        .padding(.vertical, BuilderLayout.headerVerticalPadding)
    }
}

// MARK: - Save warning badge

/// Small count badge that rides the corner of the Save button when the build
/// has open warnings, so a user who skips the Review step still sees there is
/// something to look at. Red when any warning is critical, amber otherwise.
private struct SaveWarningBadge: View {
    let count: Int
    let hasCritical: Bool

    private var tint: Color { hasCritical ? .accentDanger : .accentWarn }

    var body: some View {
        Text("\(count)")
            .font(.system(size: Theme.FontSize.footnote, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 4)
            .background(Capsule().fill(tint))
            .overlay(Capsule().stroke(Color.appBackground, lineWidth: 2))
    }
}

// MARK: - Build cost chip

/// Live whole-build price, recomputed from the spec on every edit. Sits in the
/// header so the cost of a change is always visible while tuning — the same
/// number the leaderboard's value/budget metrics use.
private struct BuildCostChip: View {
    let spec: EngineSpec

    var body: some View {
        HStack(spacing: 8) {
            Text("COST")
                .font(.system(size: Theme.FontSize.footnote, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(BuilderTheme.label)
            Text(EnginePricing.formatted(EnginePricing.buildCost(for: spec)))
                .font(.system(size: Theme.FontSize.control, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        // Never let a long price get truncated by the header's flexible layout.
        .fixedSize()
        // Match BuilderNavButton's padding so the chip is the same height as
        // the Cancel / Save buttons sitting beside it in the header.
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .fill(Color.surfaceLow)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .stroke(BuilderTheme.accent.opacity(0.4), lineWidth: Theme.Stroke.thin)
                )
        )
    }
}

// MARK: - Section rail

private struct BuilderSectionRail: View {
    @ObservedObject var state: EngineBuilderState

    /// Mirrors the header's Save-button badge so a user scanning the rail sees
    /// the Review row flagged, pointing them at where the warnings live.
    private var warnings: [BuildWarning] { EngineSpecValidator.warnings(for: state.spec) }
    private var hasCriticalWarning: Bool { warnings.contains { $0.severity == .critical } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BuilderLayout.sectionGroupSpacing) {
                ForEach(BuilderSectionGroup.allCases, id: \.self) { group in
                    sectionGroup(group)
                }
            }
            .padding(.vertical, 20)
        }
        .background(Color.surfaceFaint)
    }

    private func sectionGroup(_ group: BuilderSectionGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.label.uppercased())
                .font(.system(size: Theme.FontSize.footnote, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundColor(BuilderTheme.label)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            ForEach(group.steps) { step in
                sectionRow(step)
            }
        }
    }

    private func sectionRow(_ step: BuilderStep) -> some View {
        let selected = state.step == step
        return Button(action: { state.jump(to: step) }) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(selected ? BuilderTheme.accent : Color.clear)
                    .frame(width: 2, height: 14)

                Text(step.title.uppercased())
                    .font(.system(size: Theme.FontSize.callout, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(selected ? .white : BuilderTheme.label)
                Spacer()
                if step == .review && !warnings.isEmpty {
                    SaveWarningBadge(count: warnings.count, hasCritical: hasCriticalWarning)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: BuilderLayout.sectionRowHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(selected ? Color.accentLive.opacity(0.14) : Color.clear)
            )
            // Make the entire row a hit target, not just the label glyphs.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}
