//
//  EngineBuilderView.swift
//  engine-simulator
//
//  Top-level builder coordinator. Replaces the tile layout when the user
//  hits the + button in the ENGINES sidebar section.
//

import SwiftUI
import Combine

// MARK: - Steps

enum BuilderStep: Int, CaseIterable, Identifiable {
    case identity
    case layout
    case bottomEnd
    case cam
    case induction
    case exhaust
    case ignitionFuel
    case advanced
    case review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .identity:     return "Identity"
        case .layout:       return "Layout"
        case .bottomEnd:    return "Bottom End"
        case .cam:          return "Camshaft"
        case .induction:    return "Induction"
        case .exhaust:      return "Exhaust"
        case .ignitionFuel: return "Ignition · Fuel"
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

    var stepIndex: Int { step.rawValue }
    var stepCount: Int { BuilderStep.allCases.count }

    func goNext() {
        guard let idx = BuilderStep.allCases.firstIndex(of: step),
              idx < BuilderStep.allCases.count - 1 else { return }
        step = BuilderStep.allCases[idx + 1]
    }

    func goBack() {
        guard let idx = BuilderStep.allCases.firstIndex(of: step), idx > 0 else { return }
        step = BuilderStep.allCases[idx - 1]
    }

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
                BuilderHeader(state: state, onClose: onClose)
                Divider().background(BuilderTheme.line)

                ZStack { stepContent }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 28)

                Divider().background(BuilderTheme.line)
                BuilderFooter(state: state, onClose: onClose, onSave: save)
            }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch state.step {
        case .identity:     IdentityStep(state: state)
        case .layout:       LayoutStep(state: state)
        case .bottomEnd:    BottomEndStep(state: state)
        case .cam:          CamStep(state: state)
        case .induction:    InductionStep(state: state)
        case .exhaust:      ExhaustStep(state: state)
        case .ignitionFuel: IgnitionFuelStep(state: state)
        case .advanced:     AdvancedStep(state: state)
        case .review:       ReviewStep(state: state)
        }
    }

    private func save() {
        EngineLibrary.shared.saveUserEngine(state.spec)
        onClose()
    }
}

// MARK: - Header / footer

private struct BuilderHeader: View {
    @ObservedObject var state: EngineBuilderState
    let onClose: () -> Void

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
            }

            Spacer()

            StepProgress(state: state)

            Spacer()

            Button(action: onClose) {
                Text("CANCEL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(BuilderTheme.label)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

private struct StepProgress: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        HStack(spacing: 16) {
            Text("\(state.stepIndex + 1) / \(state.stepCount)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(BuilderTheme.label)

            Text(state.step.title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white)

            HStack(spacing: 4) {
                ForEach(BuilderStep.allCases) { s in
                    let done = s.rawValue <= state.stepIndex
                    Rectangle()
                        .fill(done ? BuilderTheme.accent : BuilderTheme.line)
                        .frame(width: 18, height: 2)
                }
            }
        }
    }
}

private struct BuilderFooter: View {
    @ObservedObject var state: EngineBuilderState
    let onClose: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            BuilderNavButton(label: "Back", style: .secondary,
                             enabled: state.stepIndex > 0,
                             action: { state.goBack() })

            Spacer()

            if state.step == .review {
                BuilderNavButton(label: "Save Engine", style: .primary,
                                 enabled: state.nameIsValid, action: onSave)
            } else {
                BuilderNavButton(label: "Next", style: .primary,
                                 enabled: state.nameIsValid,
                                 action: { state.goNext() })
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
