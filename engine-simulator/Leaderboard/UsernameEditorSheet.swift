//
//  UsernameEditorSheet.swift
//  engine-simulator
//
//  Post-onboarding rename for the leaderboard username. Runs the same
//  three-layer ``UsernameValidator`` the onboarding flow does, so a name can
//  never be changed into something the board wouldn't have accepted up front.
//

import SwiftUI

private let sheetWidth: CGFloat = 380
private let sheetPadding: CGFloat = 24

struct UsernameEditorSheet: View {
    @ObservedObject var identity: PlayerIdentity
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String = ""
    @State private var isChecking = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.section) {
            Text("Leaderboard name")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                TextField("Username", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, Theme.Space.xxl)
                    .padding(.vertical, Theme.Space.xl)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.panel)
                            .fill(Color.surfaceLow)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel)
                                .stroke(errorText == nil ? Color.strokeStrong : Color.accentDanger,
                                        lineWidth: Theme.Stroke.thin)))
                    .onSubmit(save)
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif

                if let errorText {
                    Text(errorText)
                        .font(.system(size: Theme.FontSize.callout))
                        .foregroundColor(.accentDanger)
                }
            }

            HStack(spacing: Theme.Space.xl) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.textMuted)

                Button(action: save) {
                    HStack(spacing: 6) {
                        if isChecking { ProgressView().controlSize(.small) }
                        Text("Save")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.panel)
                        .fill(canSave ? Color.accentLive : Color.accentLive.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }

            #if DEBUG
            // Dev-only: replay the first-launch flow without clearing defaults.
            Divider().background(Color.strokeFaint)
            Button(action: { identity.resetOnboarding(); dismiss() }) {
                Label("Replay tutorial", systemImage: "arrow.counterclockwise")
                    .font(.system(size: Theme.FontSize.callout, weight: .medium))
                    .foregroundColor(.textMuted)
            }
            .buttonStyle(.plain)
            #endif
        }
        .padding(sheetPadding)
        .frame(width: sheetWidth)
        .background(Color.appBackground)
        .onAppear { draft = identity.username }
    }

    private var canSave: Bool {
        !isChecking && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let name = draft
        isChecking = true
        errorText = nil
        Task {
            let result = await UsernameValidator.validate(name)
            await MainActor.run {
                isChecking = false
                switch result {
                case .valid:
                    identity.setUsername(name)
                    dismiss()
                case .invalid(let reason):
                    errorText = reason
                }
            }
        }
    }
}
