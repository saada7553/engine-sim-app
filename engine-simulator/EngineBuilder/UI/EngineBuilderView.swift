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

// MARK: - Builder state

final class EngineBuilderState: ObservableObject {
    @Published var spec: EngineSpec
    @Published var step: BuilderStep = .identity

    init(initial: EngineSpec = .defaultSpec()) { self.spec = initial }

    func jump(to step: BuilderStep) { self.step = step }

    var nameIsValid: Bool {
        !spec.name.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty
    }
}

// MARK: - View

struct EngineBuilderView: View {
    let onClose: () -> Void
    @StateObject private var state = EngineBuilderState()

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
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
        // Gated: lets the user design freely, but committing the engine to
        // the library is a Pro feature. PurchaseManager raises the paywall
        // when the user isn't entitled; the save + close run on a Pro user.
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

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 10) {
                Text("ENGINE BUILDER")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.white)
                Rectangle()
                    .fill(BuilderTheme.accent)
                    .frame(width: 6, height: 6)
                Text(state.spec.name.isEmpty ? "Untitled" : state.spec.name)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                if state.spec.layout.cylinderCount > 0 {
                    Text("·")
                        .foregroundColor(BuilderTheme.label)
                    Text("\(state.spec.layout.displayName) · \(String(format: "%.2fL", state.spec.displacementLitres))")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(BuilderTheme.label)
                }
            }

            Spacer()

            BuilderNavButton(label: "Cancel", style: .secondary,
                             action: onClose)
            BuilderNavButton(label: "Save Engine", style: .primary,
                             enabled: state.nameIsValid, action: onSave)
        }
        .padding(.horizontal, BuilderLayout.headerHorizontalPadding)
        .padding(.vertical, BuilderLayout.headerVerticalPadding)
    }
}

// MARK: - Section rail

private struct BuilderSectionRail: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BuilderLayout.sectionGroupSpacing) {
                ForEach(BuilderSectionGroup.allCases, id: \.self) { group in
                    sectionGroup(group)
                }
            }
            .padding(.vertical, 20)
        }
        .background(Color.white.opacity(0.02))
    }

    private func sectionGroup(_ group: BuilderSectionGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
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
                Rectangle()
                    .fill(selected ? BuilderTheme.accent : Color.clear)
                    .frame(width: 2, height: 14)

                Text(step.title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(selected ? .white : BuilderTheme.label)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: BuilderLayout.sectionRowHeight)
            .background(selected ? Color.white.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
