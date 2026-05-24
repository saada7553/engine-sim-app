//
//  LegalLinks.swift
//  engine-simulator
//
//  One source of truth for the app's legal document links and the reusable
//  views that surface them — the paywall, onboarding, settings, and every
//  public-posting step. Two of the three are placeholders until the hosted
//  pages exist; swap the URL strings here and every surface updates at once.
//

import SwiftUI

enum LegalLinks {
    static let privacyPolicy = URL(string: "https://saada7553.github.io/privacy-policy.html")!
    static let communityGuidelines = URL(string: "https://saada7553.github.io/community-guidelines.html")!
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Sentence shown at every point a user creates public content (setting a
    /// username, publishing an engine, posting a run). Wording is the App
    /// Store UGC requirement: agreement + zero-tolerance, with a tappable link
    /// to the full guidelines.
    static let agreementMarkdown =
        "By posting, you agree to our [Community Guidelines](\(communityGuidelines.absoluteString)). "
        + "Objectionable content isn't tolerated and may be removed."
}

// MARK: - Markdown helper

/// Builds an `AttributedString` from markdown so inline `[label](url)` links in
/// a `Text` render tappable (routing through the environment's `openURL`),
/// without scattering try/catch at every call site.
enum LegalMarkdown {
    static func attributed(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}

// MARK: - Standalone link

/// A single underlined legal link that opens its document. Used in the paywall
/// footer and the settings legal section.
struct LegalLinkLabel: View {
    let title: String
    let url: URL
    var fontSize: CGFloat = 11
    var color: Color = .textMuted

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(url) } label: {
            Text(title)
                .font(.system(size: fontSize))
                .foregroundColor(color)
                .underline()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Posting agreement note

/// The community-guidelines agreement line for any public-posting surface.
/// Drop it next to the control that publishes content; the embedded link is
/// tinted with the app accent and tappable.
struct CommunityAgreementNote: View {
    var fontSize: CGFloat = 11
    var alignment: TextAlignment = .leading

    var body: some View {
        Text(LegalMarkdown.attributed(LegalLinks.agreementMarkdown))
            .font(.system(size: fontSize))
            .foregroundColor(.textMuted)
            .tint(.accentLive)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}
