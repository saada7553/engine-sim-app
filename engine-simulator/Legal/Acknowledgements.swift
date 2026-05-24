//
//  Acknowledgements.swift
//  engine-simulator
//
//  The app's "unofficial port" disclaimer and the open-source attributions for
//  every third-party component it links. The physics core is AngeTheGreat's
//  open-source Engine Simulator and its MIT-licensed sibling libraries; the
//  app also bundles the Sentry SDK. MIT requires the copyright + permission
//  notice ship with the product, so the text lives here and is surfaced inline
//  in Settings → Legal.
//

import Foundation

// MARK: - Disclaimer copy

/// The single source of truth for the "unofficial / unaffiliated" wording the
/// original author asked us to carry. Reused on the splash subtitle and the
/// settings legal section so they never drift.
enum PortDisclaimer {
    /// Copyright for the proprietary native app (separate from the third-party
    /// MIT notices, which belong to their own authors).
    static let appCopyright = "© 2026 Saad. The native Mac & iOS app is proprietary."

    /// Full statement shown in Settings → Legal: unofficial + not affiliated,
    /// the minimum the original author asked us to carry.
    static let full = """
    Engine Simulator for Mac & iOS is an unofficial port. It is not affiliated \
    with, endorsed by, or supported by AngeTheGreat (Ange Yaghi), the creator of \
    the original Engine Simulator.
    """
}

// MARK: - License data

/// One linked third-party component and the notice that must travel with it.
struct OpenSourceComponent: Identifiable {
    let id = UUID()
    let name: String
    let copyright: String

    /// Every bundled component is MIT-licensed, so the permission text is shared
    /// and shown once; this list carries each component's own copyright line.
    static let all: [OpenSourceComponent] = [
        OpenSourceComponent(name: "Engine Simulator",
                            copyright: "Copyright 2022 AngeTheGreat (Ange Yaghi)"),
        OpenSourceComponent(name: "Piranha",
                            copyright: "Copyright (c) Ange Yaghi"),
        OpenSourceComponent(name: "simple-2d-constraint-solver",
                            copyright: "Copyright (c) 2022 Ange Yaghi"),
        OpenSourceComponent(name: "csv-io",
                            copyright: "Copyright (c) 2022 Ange Yaghi"),
        OpenSourceComponent(name: "Sentry for Cocoa",
                            copyright: "Copyright (c) 2015 Sentry and individual contributors"),
    ]

    /// The standard MIT permission text, shown once beneath the component list.
    static let mitBody = """
    The above software is provided under the MIT License. Permission is hereby \
    granted, free of charge, to any person obtaining a copy of the software and \
    associated documentation files (the "Software"), to deal in the Software \
    without restriction, including without limitation the rights to use, copy, \
    modify, merge, publish, distribute, sublicense, and/or sell copies of the \
    Software, and to permit persons to whom the Software is furnished to do so, \
    subject to the following conditions: The above copyright notices and this \
    permission notice shall be included in all copies or substantial portions \
    of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING \
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS \
    IN THE SOFTWARE.
    """
}
