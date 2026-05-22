//
//  AIEnginePromptView.swift
//  engine-simulator
//
//  The "describe your engine" screen. Takes free text, runs it through the
//  on-device Foundation Models generator, and hands the resulting EngineSpec
//  back so the builder can drop into its Review step for fine-tuning.
//
//  Only reached when Foundation Models is available (the mode chooser is
//  skipped otherwise), so this view assumes a working model and only has to
//  handle per-request errors.
//

import SwiftUI

private enum PromptLayout {
    static let maxContentWidth: CGFloat = 620
    static let editorMinHeight: CGFloat = 150
    static let headerHorizontalPadding: CGFloat = 24
    static let headerVerticalPadding: CGFloat = 14
    static let contentSpacing: CGFloat = 22
}

private let promptExamples: [String] = [
    "Angry American muscle V8 with a deep rumble",
    "Turbocharged inline-6 like a 2JZ, built for drift",
    "High-revving naturally aspirated F1 V12",
    "Economical little inline-3 city car engine",
    "Boxer-4 rally engine with anti-lag burble",
]

struct AIEnginePromptView: View {
    let onGenerated: (EngineSpec) -> Void
    let onBack: () -> Void
    let onCancel: () -> Void

    @State private var prompt: String = ""
    @State private var isGenerating = false
    @State private var errorText: String?
    @FocusState private var editorFocused: Bool

    private var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(BuilderTheme.line)

            ScrollView {
                content
                    .frame(maxWidth: PromptLayout.maxContentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 32)
            }
        }
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: PromptLayout.contentSpacing) {
            BuilderSectionHeading(title: "Describe your engine")
            Text("Say what you want in plain language. Layout, character, the\ncar it lives in. The on-device model drafts a full spec you can\nthen fine-tune before saving.")
                .font(.system(size: Theme.FontSize.headline, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.label)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            promptEditor

            // While generating, the indicator takes the place of the examples
            // and button so the page stays put and the prompt stays visible.
            if isGenerating {
                GeneratingIndicator()
                    .padding(.top, 6)
            } else {
                examples

                if let errorText {
                    Text(errorText)
                        .font(.system(size: Theme.FontSize.callout, weight: .regular, design: .monospaced))
                        .foregroundColor(.accentDanger)
                }

                generateButton
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isGenerating)
    }

    private var promptEditor: some View {
        ZStack(alignment: .topLeading) {
            if prompt.isEmpty {
                Text("e.g. Twin-turbo flat-six, track-focused, screaming to 9000rpm")
                    .font(.system(size: Theme.FontSize.title, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.dim.opacity(0.3))
                    .padding(.top, 8)
                    .padding(.leading, 5)
            }
            TextEditor(text: $prompt)
                .focused($editorFocused)
                .font(.system(size: Theme.FontSize.title, weight: .regular, design: .monospaced))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .frame(minHeight: PromptLayout.editorMinHeight)
                .disabled(isGenerating)
                .onChange(of: prompt) { _, newValue in
                    if newValue.count > AIEngineGeneration.maxPromptLength {
                        prompt = String(newValue.prefix(AIEngineGeneration.maxPromptLength))
                    }
                }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: BuilderTheme.cardCorner).fill(Color.surfaceFaint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BuilderTheme.cardCorner)
                .stroke(editorFocused ? BuilderTheme.accent : BuilderTheme.line, lineWidth: Theme.Stroke.thin)
        )
        .overlay(alignment: .bottomTrailing) {
            Text("\(prompt.count)/\(AIEngineGeneration.maxPromptLength)")
                .font(.system(size: Theme.FontSize.footnote, weight: .regular, design: .monospaced))
                .foregroundColor(prompt.count >= AIEngineGeneration.maxPromptLength ? .accentDanger : BuilderTheme.dim)
                .padding(10)
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRY")
                .font(.system(size: Theme.FontSize.footnote, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(BuilderTheme.dim)

            FlowChips(items: promptExamples, disabled: isGenerating) { example in
                prompt = example
            }
        }
    }

    private var generateButton: some View {
        HStack {
            Spacer()
            BuilderNavButton(label: "Generate", style: .primary,
                             enabled: canGenerate, action: generate)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("ENGINE BUILDER")
                .font(.system(size: Theme.FontSize.control, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundColor(.white)
            Rectangle().fill(BuilderTheme.accent).frame(width: 6, height: 6)
            Text("Generate with AI")
                .font(.system(size: Theme.FontSize.control, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.label)

            Spacer()

            BuilderNavButton(label: "Back", style: .ghost, enabled: !isGenerating, action: onBack)
            BuilderNavButton(label: "Cancel", style: .secondary, enabled: !isGenerating, action: onCancel)
        }
        .padding(.horizontal, PromptLayout.headerHorizontalPadding)
        .padding(.vertical, PromptLayout.headerVerticalPadding)
    }

    // MARK: Actions

    private func generate() {
        let text = prompt
        errorText = nil
        isGenerating = true
        editorFocused = false

        Task {
            do {
                let spec = try await AIEngineGeneration.generate(from: text)
                await MainActor.run {
                    isGenerating = false
                    onGenerated(spec)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorText = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Example chips

private struct FlowChips: View {
    let items: [String]
    let disabled: Bool
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button(action: { onTap(item) }) {
                    Text(item)
                        .font(.system(size: Theme.FontSize.callout, weight: .regular, design: .monospaced))
                        .foregroundColor(BuilderTheme.label)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Color.surfaceLow)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.small)
                                .stroke(BuilderTheme.line, lineWidth: Theme.Stroke.hairline)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
        }
    }
}
