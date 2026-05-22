//
//  BuilderModeChooser.swift
//  engine-simulator
//
//  First screen of the engine builder: pick a path. Build every parameter by
//  hand in the wizard, or describe the engine in words and let the on-device
//  model draft a spec to fine-tune. Only shown when Foundation Models is
//  available — otherwise the builder opens straight into the manual wizard.
//

import SwiftUI

private enum ChooserLayout {
    static let cardWidth: CGFloat = 260
    static let cardHeight: CGFloat = 220
    static let cardSpacing: CGFloat = 24
    static let iconSize: CGFloat = 34
    static let headerHorizontalPadding: CGFloat = 24
    static let headerVerticalPadding: CGFloat = 14
}

struct BuilderModeChooser: View {
    let onManual: () -> Void
    let onAI: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(BuilderTheme.line)

            Spacer()

            VStack(spacing: 28) {
                Text("How do you want to build it?")
                    .font(.system(size: Theme.FontSize.title, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                HStack(spacing: ChooserLayout.cardSpacing) {
                    ModeCard(
                        icon: "slider.horizontal.3",
                        title: "Build Manually",
                        subtitle: "Dial in every parameter\nyourself, step by step.",
                        action: onManual
                    )
                    ModeCard(
                        icon: "sparkles",
                        title: "Generate with AI",
                        subtitle: "Describe it in words,\nthen tweak the result.",
                        action: onAI
                    )
                }
            }

            Spacer()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("ENGINE BUILDER")
                .font(.system(size: Theme.FontSize.control, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundColor(.white)
            Rectangle()
                .fill(BuilderTheme.accent)
                .frame(width: 6, height: 6)
            Text("New Engine")
                .font(.system(size: Theme.FontSize.control, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.label)

            Spacer()

            BuilderNavButton(label: "Cancel", style: .secondary, action: onCancel)
        }
        .padding(.horizontal, ChooserLayout.headerHorizontalPadding)
        .padding(.vertical, ChooserLayout.headerVerticalPadding)
    }
}

// MARK: - Card

private struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: ChooserLayout.iconSize, weight: .regular))
                    .foregroundColor(BuilderTheme.accent)

                Text(title.uppercased())
                    .font(.system(size: Theme.FontSize.headline, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: Theme.FontSize.callout, weight: .regular, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .foregroundColor(BuilderTheme.label)
                    .padding(.horizontal, 12)
            }
            .frame(width: ChooserLayout.cardWidth, height: ChooserLayout.cardHeight)
            .background(
                RoundedRectangle(cornerRadius: BuilderTheme.cardCorner)
                    .fill(Color.surfaceFaint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BuilderTheme.cardCorner)
                    .stroke(BuilderTheme.line, lineWidth: Theme.Stroke.thin)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
