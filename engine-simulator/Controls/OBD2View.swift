//
//  OBD2View.swift
//  engine-simulator
//
//  Tile mimicking a vintage OBD-II diagnostic scanner: amber-on-black
//  monospaced readout with faint horizontal scanlines and a soft glow
//  on every code row.
//
//  Stored-DTC semantics — engine state is sampled on a timer and faults
//  accumulate into a scrolling log. A fault must persist past a short
//  debounce before it's committed, so a value hovering on a threshold
//  doesn't flash rows on and off. A committed code self-clears once its
//  fault has resolved and it's been shown for at least codeExpireSeconds;
//  a fault that's still active is kept indefinitely.
//
//  The CLEAR CODES button wipes the log for ~0.4s; any fault still
//  active afterwards re-accumulates once it clears the debounce. That
//  matches a real scanner: Mode 04 clears stored DTCs, and active
//  monitors re-set them.
//

import SwiftUI
import Combine

// MARK: - Palette / dimensions

private let crtBackground = Color(red: 0.02, green: 0.02, blue: 0.03)
private let crtInner = Color(red: 0.05, green: 0.04, blue: 0.02)
private let amberWarn = Color(red: 1.0, green: 0.72, blue: 0.20)
private let amberCritical = Color(red: 1.0, green: 0.35, blue: 0.15)
private let amberDim = Color(red: 0.55, green: 0.40, blue: 0.10)
private let nominalGreen = Color(red: 0.30, green: 1.0, blue: 0.45)
private let panelBorder = Color.white.opacity(0.10)

private let tilePadding: CGFloat = 10
private let cardCorner: CGFloat = 3
private let scanlineSpacing: CGFloat = 2.0
private let scanlineOpacity: Double = 0.05
private let scanlineMinHeight: CGFloat = 80

private let clearWipeSeconds: Double = 0.4

// How often we re-sample engine state for codes, and how long a fault
// must persist continuously before it's committed to the list. The
// debounce stops a value hovering on a threshold from flashing rows on
// and off — a code has to "stick" before it shows up.
private let sampleInterval: Double = 0.2
private let appearDebounceSeconds: Double = 0.5

// A committed code self-clears once it's been shown for at least this long
// AND its underlying fault is no longer active. Codes whose fault is still
// present never expire; recently-committed codes linger until they age out,
// so a fault that flickers off briefly doesn't blank the row.
private let codeExpireSeconds: Double = 10.0

// Code-row text scales with the panel width so it stays readable on a
// large tile without being hardcoded to a single point size. Clamped so
// it never gets tiny on a narrow tile or oversized on a wide one.
private let minCodeFontSize: CGFloat = 13
private let maxCodeFontSize: CGFloat = 17
private let codeFontWidthRatio: CGFloat = 0.032
private let descFontRatio: CGFloat = 0.85
private let glyphFontRatio: CGFloat = 0.92
private let actionFontRatio: CGFloat = 0.72

// MARK: - View

struct OBD2View: View {
    @ObservedObject var vm: EngineViewModel

    /// When non-nil, the list is hidden until the timer elapses. Set by
    /// tapping CLEAR CODES.
    @State private var clearedAt: Date?

    /// Drives the live-blinking dot in the header.
    @State private var blinkOn: Bool = true

    /// Accumulated stored codes — like a real scanner's DTC memory, codes
    /// pile up and stay until CLEAR CODES is pressed; the list scrolls.
    @State private var accumulated: [OBD2Code] = []

    /// Candidate faults seen but not yet committed, with the time they
    /// were first observed. Used to enforce `appearDebounceSeconds`.
    @State private var firstSeen: [String: Date] = [:]

    /// When each committed code was first added to `accumulated`. Drives the
    /// `codeExpireSeconds` auto-clear so a resolved fault eventually drops off
    /// instead of lingering until CLEAR CODES is pressed.
    @State private var committedAt: [String: Date] = [:]

    /// Fault ids that were active when CLEAR CODES was last pressed. They stay
    /// suppressed (won't re-accumulate) for as long as they remain continuously
    /// active; once a fault clears, it drops out of this set so a genuine
    /// recurrence shows up again.
    @State private var suppressed: Set<String> = []

    // Held in @State so the publisher is created exactly once. As a plain
    // `let` it would be rebuilt on every re-render — and the engine pushes
    // updates many times a second — so onReceive would resubscribe to a
    // fresh timer before it ever fired, and no codes would accumulate.
    @State private var sampleTimer = Timer.publish(every: sampleInterval,
                                                   on: .main, in: .common).autoconnect()

    /// Display order: critical first, then alphanumeric — matches the
    /// ordering OBD2CodeService used to apply.
    private var displayedCodes: [OBD2Code] {
        if clearedAt != nil { return [] }
        return accumulated.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return severityRank(lhs.severity) > severityRank(rhs.severity)
            }
            return lhs.code < rhs.code
        }
    }

    private func severityRank(_ s: OBD2Severity) -> Int {
        s == .critical ? 2 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            crtPanel
        }
        .padding(tilePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.appBackground)
        .onReceive(sampleTimer) { _ in sample() }
        .onChange(of: vm.repairToken) { _, _ in clearCodes() }
    }

    /// Re-derive raw codes, refresh any already-shown code's fields, and
    /// promote candidates that have persisted past the debounce window.
    private func sample() {
        guard clearedAt == nil else { return }
        let now = Date()
        let raw = OBD2CodeService.codes(for: vm)
        let rawIds = Set(raw.map { $0.id })
        let rawById = Dictionary(raw.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Lift suppression for any cleared fault that has since gone away — if
        // it comes back later it counts as a fresh occurrence and will show.
        suppressed.formIntersection(rawIds)

        // Keep escalating severity / description changes in sync.
        accumulated = accumulated.map { rawById[$0.id] ?? $0 }

        let shown = Set(accumulated.map { $0.id })
        var pending = firstSeen
        for code in raw where !shown.contains(code.id) && !suppressed.contains(code.id) {
            let seenAt = pending[code.id] ?? now
            if now.timeIntervalSince(seenAt) >= appearDebounceSeconds {
                accumulated.append(code)
                committedAt[code.id] = now
                pending[code.id] = nil
            } else {
                pending[code.id] = seenAt
            }
        }

        // Drop candidates that vanished before committing — their debounce
        // restarts if they reappear.
        firstSeen = pending.filter { rawIds.contains($0.key) }

        // Auto-clear committed codes whose fault has resolved and that have
        // been shown longer than codeExpireSeconds. Active faults (still in
        // rawIds) are always kept regardless of age.
        accumulated.removeAll { code in
            guard !rawIds.contains(code.id) else { return false }
            let addedAt = committedAt[code.id] ?? now
            return now.timeIntervalSince(addedAt) >= codeExpireSeconds
        }
        committedAt = committedAt.filter { key, _ in
            accumulated.contains { $0.id == key }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(amberWarn)
                    .frame(width: 7, height: 7)
                    .opacity(blinkOn ? 1.0 : 0.25)
                    .shadow(color: amberWarn.opacity(0.7), radius: 2)
                Text("OBD-II SCAN")
                    .modifier(RetroFont(size: 12))
                    .tracking(1.0)
                    .foregroundColor(.white)
            }
            Spacer()
            Text(codeBadgeText)
                .modifier(RetroFont(size: 11))
                .tracking(0.6)
                .foregroundColor(displayedCodes.isEmpty ? nominalGreen : amberWarn)
            clearButton
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                blinkOn.toggle()
            }
        }
    }

    private var codeBadgeText: String {
        let count = displayedCodes.count
        if count == 0 { return "NO CODES" }
        return "\(count) CODE\(count == 1 ? "" : "S")"
    }

    private var clearButton: some View {
        let isEmpty = displayedCodes.isEmpty
        return SmallActionButton(label: "CLEAR CODES",
                                 accent: amberWarn,
                                 action: clearCodes)
            .disabled(isEmpty)
            .opacity(isEmpty ? 0.4 : 1.0)
            .help("Clear stored codes. A fault only re-appears if it clears and then recurs.")
    }

    /// Wipe the accumulated log and suppress every currently-active fault so it
    /// stays cleared until it actually goes away and re-occurs. Sampling pauses
    /// for the brief wipe; when it resumes, suppressed faults are skipped.
    private func clearCodes() {
        suppressed = Set(OBD2CodeService.codes(for: vm).map { $0.id })
        accumulated = []
        firstSeen = [:]
        committedAt = [:]
        clearedAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + clearWipeSeconds) {
            clearedAt = nil
        }
    }

    // MARK: CRT panel

    private var crtPanel: some View {
        GeometryReader { geo in
            let codeFont = min(maxCodeFontSize,
                               max(minCodeFontSize, geo.size.width * codeFontWidthRatio))
            ZStack {
                // Background with subtle radial glow center
                RadialGradient(colors: [crtInner, crtBackground],
                               center: .center,
                               startRadius: 8,
                               endRadius: 240)

                // Scanlines overlay
                if geo.size.height >= scanlineMinHeight {
                    Canvas { context, size in
                        var y: CGFloat = 0
                        while y < size.height {
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            context.stroke(path,
                                           with: .color(.white.opacity(scanlineOpacity)),
                                           lineWidth: 0.5)
                            y += scanlineSpacing
                        }
                    }
                }

                // Content
                if displayedCodes.isEmpty {
                    emptyState
                } else {
                    codeList(fontSize: codeFont)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner)
                .stroke(panelBorder, lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCorner))
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("NO ACTIVE CODES")
                .modifier(RetroFont(size: 14))
                .tracking(2.4)
                .foregroundColor(nominalGreen)
                .shadow(color: nominalGreen.opacity(0.6), radius: 4)
            Text("SYSTEM NOMINAL")
                .modifier(RetroFont(size: 11))
                .tracking(1.6)
                .foregroundColor(nominalGreen.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Code list

    private func codeList(fontSize: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(displayedCodes) { code in
                    CodeRow(code: code, fontSize: fontSize)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Code row

private struct CodeRow: View {
    let code: OBD2Code
    let fontSize: CGFloat

    private var color: Color {
        switch code.severity {
        case .critical: return amberCritical
        case .warning:  return amberWarn
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(code.code)
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.6), radius: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(code.description.uppercased())
                    .font(.system(size: fontSize * descFontRatio, weight: .regular, design: .monospaced))
                    .foregroundColor(color.opacity(0.80))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: color.opacity(0.4), radius: 2)
                // Remediation hint: what the user should actually do. Dimmer
                // and smaller so it reads as secondary guidance, not a fault.
                if let action = code.action {
                    Text("▸ " + action.uppercased())
                        .font(.system(size: fontSize * actionFontRatio, weight: .regular, design: .monospaced))
                        .foregroundColor(amberDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
            severityGlyph
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var severityGlyph: some View {
        Text(code.severity == .critical ? "!!" : "!")
            .font(.system(size: fontSize * glyphFontRatio, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .shadow(color: color.opacity(0.6), radius: 2)
    }
}
