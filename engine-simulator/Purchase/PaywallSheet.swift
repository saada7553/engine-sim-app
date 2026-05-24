//
//  PaywallSheet.swift
//  engine-simulator
//
//  Restrained paywall sheet. The hero is a live SceneKit carousel that
//  spawns every built-in engine in turn, idles the crank at heroCrankRPM,
//  and rotates the whole assembly on a turntable so you see all sides.
//  An annotation strip beneath the scene names the engine + key specs.
//
//  Orange chrome is intentionally minimal — reserved for the price and the
//  CTA so neither competes with the 3D scene.
//

import SwiftUI
import SceneKit
import Combine

// MARK: - Layout constants

private let paywallScrim = Color.black.opacity(0.72)
private let paywallCardFill = Color.appBackground
private let paywallCardBorder = Color.strokeSubtle
private let paywallCardCorner: CGFloat = Theme.Radius.window
private let paywallMaxWidth: CGFloat = 520
private let paywallContentSpacing: CGFloat = 18
private let paywallPadding: CGFloat = 24

private let heroHeight: CGFloat = 260
/// Width of the text column on iOS. The left column (hero) takes the rest.
/// On an iPad 11" landscape virtual canvas (~1680pt) this leaves the bulk
/// of the width to the hero. Lower than 520 so the carousel reads as the
/// centerpiece; copy still has room to breathe at this width without
/// excessive wrapping.
private let iosTextColumnWidth: CGFloat = 400
private let heroCorner: CGFloat = Theme.Radius.panel
private let heroBackground = Color.black.opacity(0.55)
private let heroBorder = Color.strokeFaint
private let heroAnnotationBg = Color.black.opacity(0.50)
private let heroAnnotationBorder = Color.white.opacity(0.06)
/// Fixed height reserved for the name+subtitle block: enough for a name that
/// wraps to two full-size lines PLUS the subtitle line. The name is never
/// shrunk or truncated — it wraps within this space — and because the height
/// is fixed, the strip and the whole paywall window stay a constant size as
/// engines with longer names scroll past. Short names just center in it.
private let annotationTextHeight: CGFloat = 52

private let ctaIdleFill = Color.accentLive
private let ctaIdleText = Color.black
private let ctaHoverFill = Color.accentLive.opacity(0.88)
private let bodyText = Color.white.opacity(0.85)
private let mutedText = Color.textMuted
private let dividerColor = Color.strokeFaint
private let successColor = Color.accentOk
private let errorColor = Color.accentDanger.opacity(0.9)

// MARK: - Carousel constants

/// Seconds each engine stays on screen before crossfading to the next.
private let carouselDwellSeconds: TimeInterval = 5.6
/// Crank speed for the hero. Slow enough that the eye reads each stroke.
private let heroCrankRPM: Double = 15.0
/// Full turntable revolution duration (seconds). Independent of crank.
private let heroTurntablePeriod: Double = 12.0
/// Locked store price. The PurchaseManager's localized string will be used
/// if a product is loaded; this is the fallback + the price we ship at.
private let lockedPrice = "$14.99"

// MARK: - View

struct PaywallSheet: View {
    @ObservedObject var manager: PurchaseManager
    @StateObject private var carousel = EngineCarousel()
    @State private var hoverCTA = false

    var body: some View {
        Group {
            #if os(macOS)
            macOSBody
            #else
            iosBody
            #endif
        }
        .transition(.opacity)
        .onAppear { carousel.start() }
        .onDisappear { carousel.stop() }
    }

    /// macOS: centered card floating over a dimmed scrim — works because the
    /// app window can be huge and `.sheet` already inset-fits the card.
    private var macOSBody: some View {
        ZStack {
            paywallScrim
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(alignment: .leading, spacing: paywallContentSpacing) {
                header
                hero
                copyBlock
                priceRow
                primaryCTA
                statusLine
                footerLinks
            }
            .padding(paywallPadding)
            .frame(maxWidth: paywallMaxWidth)
            .background(
                RoundedRectangle(cornerRadius: paywallCardCorner)
                    .fill(paywallCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: paywallCardCorner)
                    .stroke(paywallCardBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.6), radius: 26, y: 12)
        }
    }

    /// iOS: 2-column layout sized for iPad landscape. Left half is the live
    /// 3D engine carousel; right half holds every text element + the buy
    /// button in a single column. No vertical scrolling needed — everything
    /// fits on a single landscape screen, and the carousel reads as the
    /// "showroom" left of the spec sheet.
    #if !os(macOS)
    private var iosBody: some View {
        ZStack {
            paywallCardFill.ignoresSafeArea()

            HStack(spacing: 0) {
                iosHeroColumn
                iosTextColumn
            }
        }
        // Run edge-to-edge top + bottom (under the status bar / home
        // indicator), but RESPECT the leading and trailing safe areas so
        // the iPhone landscape notch doesn't crop into the carousel hero.
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .statusBarHidden(true)
    }

    /// Left column on iOS: carousel chevrons + engine name strip sits as
    /// its own row at the top, pushing the 3D view down. Avoids the
    /// transparent-overlay problem where the SceneKit engine bled through
    /// the annotation's gradient.
    private var iosHeroColumn: some View {
        VStack(spacing: 0) {
            heroAnnotation
            ZStack {
                heroBackdrop
                PaywallEngineHero(carousel: carousel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Right column on iOS: header (brand + close), main copy, build-your-
    /// own callout, price row, CTA, status, footer. ScrollView wraps the
    /// middle so very small scenes (iPhone landscape) still let users reach
    /// everything; on iPad the natural heights fit without scrolling.
    private var iosTextColumn: some View {
        VStack(spacing: 0) {
            iosTextHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    copyBlock
                    priceRow
                    statusLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            iosBottomBar
        }
        .frame(width: iosTextColumnWidth)
        .background(paywallCardFill)
    }

    /// Brand strip + close button at the top of the right column.
    private var iosTextHeader: some View {
        HStack(spacing: 10) {
            Text("ENGINE SIMULATOR")
                .modifier(RetroFont(size: Theme.FontSize.footnote, weight: .bold))
                .tracking(2)
                .foregroundColor(bodyText)
            Text("PRO")
                .modifier(RetroFont(size: Theme.FontSize.footnote, weight: .bold))
                .tracking(2)
                .foregroundColor(.accentLive)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.accentLive.opacity(0.6), lineWidth: 1)
                )
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    /// Sticky bottom slab: CTA + footer links. Sits above the home indicator
    /// inset so nothing important hides behind it.
    private var iosBottomBar: some View {
        VStack(spacing: 12) {
            primaryCTA
            footerLinks
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            Rectangle()
                .fill(paywallCardFill)
                .shadow(color: Color.black.opacity(0.4), radius: 10, y: -4)
        )
    }

    #endif

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("ENGINE SIMULATOR")
                .modifier(RetroFont(size: Theme.FontSize.body, weight: .bold))
                .tracking(2)
                .foregroundColor(bodyText)
            Text("PRO")
                .modifier(RetroFont(size: Theme.FontSize.body, weight: .bold))
                .tracking(2)
                .foregroundColor(.accentLive)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.accentLive.opacity(0.6), lineWidth: 1)
                )
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(mutedText)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    // MARK: Hero

    private var hero: some View {
        // Carousel strip (arrows + name + progress) sits as its own row ABOVE
        // the 3D view rather than overlaid on it. Overlaying made the centered
        // engine read as off-center because the controls covered its lower
        // half — the iOS layout already does it this way.
        VStack(spacing: 0) {
            heroAnnotation
            ZStack {
                heroBackdrop
                PaywallEngineHero(carousel: carousel)
            }
            .frame(height: heroHeight)
        }
        .overlay(
            RoundedRectangle(cornerRadius: heroCorner)
                .stroke(heroBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: heroCorner))
    }

    /// Radial spotlight behind the SCN view. SceneKit's vignette dims the
    /// frame; this lifts the center so the engine sits in a soft, cool pool.
    private var heroBackdrop: some View {
        RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Color(red: 0.07, green: 0.08, blue: 0.11), location: 0),
                .init(color: Color.black.opacity(0.75), location: 0.65),
                .init(color: Color.black.opacity(0.95), location: 1.0),
            ]),
            center: .center,
            startRadius: 20,
            endRadius: 260
        )
    }

    private var heroAnnotation: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(heroAnnotationBorder)
                .frame(height: 1)
            HStack(alignment: .center, spacing: 10) {
                carouselArrow(systemName: "chevron.left", help: "Previous engine",
                              action: { carousel.previous() })
                // Name over subtitle, each on its own full-width line. Stacked
                // (rather than side-by-side) so even the longest name gets the
                // whole width and stays on one readable line at full size. The
                // block has a fixed two-line height, so the strip — and the
                // window — never changes size as engines scroll by.
                VStack(spacing: 3) {
                    Text(carousel.currentName.uppercased())
                        .modifier(RetroFont(size: Theme.FontSize.control, weight: .bold))
                        .tracking(2.5)
                        .foregroundColor(.white)
                        // Wrap (up to two lines) at full size — never shrink,
                        // never truncate. The fixed block height below reserves
                        // room for both lines so nothing gets clipped.
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(carousel.currentName)
                        .transition(.opacity)
                    Text(carousel.currentSubtitle)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(bodyText)
                        .lineLimit(1)
                        .id(carousel.currentSubtitle)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity)
                .frame(height: annotationTextHeight)
                carouselArrow(systemName: "chevron.right", help: "Next engine",
                              action: { carousel.next() })
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            // macOS gets the dark strip behind the carousel name; on iOS
            // the hero is edge-to-edge so that strip reads as a random
            // black bar across the screen. Fade it to clear at the edges
            // instead so the text just sits on the scene with a soft
            // gradient.
            #if os(macOS)
            .background(heroAnnotationBg)
            #else
            // Strip is a standalone row above the hero now — solid card
            // fill instead of a gradient so it reads as its own bar, not
            // as a fade overlaid on the SceneKit view.
            .background(paywallCardFill)
            #endif

            CarouselProgressBar(count: carousel.count,
                                currentIndex: carousel.currentIndex)
                .frame(height: 2)
        }
    }

    private func carouselArrow(systemName: String,
                               help: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(bodyText)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Copy

    private var copyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lifetime access to the full simulator.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text("Every preset engine, full ECU tuning, and every future update. Design your own from scratch in the engine builder. Any layout, bore, stroke, cam, and tune.")
                .font(.system(size: 12))
                .foregroundColor(mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Price row

    private var priceRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(displayPrice)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("one-time")
                .font(.system(size: 12))
                .foregroundColor(mutedText)
            Spacer()
        }
    }

    private var displayPrice: String {
        let label = manager.lifetimePriceLabel
        return label.isEmpty ? lockedPrice : label
    }

    // MARK: CTA

    private var primaryCTA: some View {
        Button(action: triggerPurchase) {
            HStack(spacing: 8) {
                if manager.purchaseState == .loading {
                    DashLoader(diameter: 15, tint: ctaIdleText)
                    Text("Contacting App Store…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ctaIdleText)
                } else {
                    Text("Get lifetime access")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(ctaIdleText)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ctaIdleText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoverCTA ? ctaHoverFill : ctaIdleFill)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(manager.purchaseState == .loading)
        .onHover { hoverCTA = $0 }
    }

    // MARK: Status

    @ViewBuilder
    private var statusLine: some View {
        switch manager.purchaseState {
        case .idle, .loading:
            EmptyView()
        case .succeeded:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(successColor)
                Text("Pro unlocked. Thanks for your support.")
                    .font(.system(size: 12))
                    .foregroundColor(successColor)
                Spacer()
            }
        case .error(let message):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(errorColor)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(errorColor)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
    }

    // MARK: Footer

    private var footerLinks: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button(action: triggerRestore) {
                    Text("Restore purchases")
                        .font(.system(size: 11))
                        .foregroundColor(mutedText)
                        .underline()
                }
                .buttonStyle(.plain)
                .disabled(manager.purchaseState == .loading)

                Spacer()

                Text("Billed through Apple. Cancel anytime in your App Store account.")
                    .font(.system(size: 10))
                    .foregroundColor(mutedText.opacity(0.85))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                LegalLinkLabel(title: "Terms of Use", url: LegalLinks.termsOfUse, color: mutedText)
                Text("·").font(.system(size: 11)).foregroundColor(mutedText.opacity(0.5))
                LegalLinkLabel(title: "Privacy Policy", url: LegalLinks.privacyPolicy, color: mutedText)
                Spacer()
            }
        }
    }

    // MARK: Actions

    private func dismiss() {
        manager.isPresentingPaywall = false
        manager.purchaseState = .idle
    }

    private func triggerPurchase() {
        Task { await manager.purchaseLifetime() }
    }

    private func triggerRestore() {
        Task { await manager.restorePurchases() }
    }
}

// MARK: - Progress bar

private struct CarouselProgressBar: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        GeometryReader { geo in
            let segmentWidth = geo.size.width / CGFloat(max(count, 1))
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(dividerColor)
                Rectangle()
                    .fill(Color.accentLive.opacity(0.75))
                    .frame(width: segmentWidth)
                    .offset(x: segmentWidth * CGFloat(currentIndex))
                    .animation(.easeInOut(duration: 0.45), value: currentIndex)
            }
        }
    }
}

// MARK: - Carousel state

@MainActor
final class EngineCarousel: ObservableObject {
    @Published private(set) var currentIndex: Int = 0

    /// Only Pro-gated engines — the free ones (Geo Metro) are excluded
    /// because the paywall is selling the engines the user can't already
    /// run. Auto-syncs with EngineLibrary.freeEngineIds.
    private let specs: [EngineSpec] = BuiltInEngineSpecs.orderedSpecs
        .filter { !EngineLibrary.freeEngineIds.contains($0.id) }
    private var timer: Timer?

    var count: Int { specs.count }
    var currentSpec: EngineSpec { specs[currentIndex] }
    var currentName: String { currentSpec.name }
    var currentSubtitle: String { Self.subtitle(for: currentSpec) }

    func start() {
        guard timer == nil, count > 1 else { return }
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// User-driven next/previous. Restart the dwell timer so the engine the
    /// user just landed on gets a full cycle of screen time before the
    /// auto-advance kicks back in.
    func next() {
        step(by: 1)
    }

    func previous() {
        step(by: -1)
    }

    private func step(by delta: Int) {
        withAnimation(.easeInOut(duration: 0.35)) {
            currentIndex = ((currentIndex + delta) % count + count) % count
        }
        if timer != nil {
            timer?.invalidate()
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: carouselDwellSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.35)) {
            currentIndex = (currentIndex + 1) % count
        }
    }

    /// Layout + displacement + redline. Computed from the spec so the strip
    /// stays correct if a built-in's bore/stroke ever moves.
    private static func subtitle(for spec: EngineSpec) -> String {
        let cyls = spec.layout.cylinderCount
        let cylVolMm3 = .pi / 4.0 * spec.boreMm * spec.boreMm * spec.strokeMm
        let totalCc = cylVolMm3 * Double(cyls) / 1000.0
        let liters = totalCc / 1000.0
        let displacement = String(format: "%.1fL", liters)
        let redline = "\(Int(spec.redlineRpm)) rpm"
        return "\(spec.layout.displayName) · \(displacement) · \(redline)"
    }
}

// MARK: - 3D hero

/// SceneKit carousel: spawns the carousel's current EngineSpec, slowly spins
/// both the crankshaft (heroCrankRPM) and the whole assembly (turntable),
/// and rebuilds when the carousel advances.
private struct PaywallEngineHero: _SCNViewRepresentable {
    @ObservedObject var carousel: EngineCarousel

    private func makeSCNView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.allowsCameraControl = false
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.loops = true

        configureLights(in: view.scene!)
        context.coordinator.attach(to: view, spec: carousel.currentSpec)
        view.delegate = context.coordinator
        return view
    }

#if os(macOS)
    func makeNSView(context: Context) -> SCNView { makeSCNView(context: context) }
    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.swapTo(spec: carousel.currentSpec)
    }
#else
    func makeUIView(context: Context) -> SCNView { makeSCNView(context: context) }
    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.swapTo(spec: carousel.currentSpec)
    }
#endif

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Lights

    private func configureLights(in scene: SCNScene) {
        // White key light does the actual lifting — bright enough now that
        // HDR auto-exposure isn't masking dim intensities. The warm lights
        // are deliberately a small fraction of the key so the aura reads
        // as a tint, not as the dominant illumination.
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.light?.color = PlatformColor(white: 0.98, alpha: 1.0)
        key.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(key)

        // Warm rim light from behind / off-axis. Faint relative to key —
        // just a hint of gold on the edge, not a wash.
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 80
        rim.light?.color = PlatformColor(red: 1.0, green: 0.78, blue: 0.45, alpha: 1.0)
        rim.eulerAngles = SCNVector3(-Float.pi / 8, -Float.pi * 0.7, 0)
        scene.rootNode.addChildNode(rim)

        // Subtle warm under-light. Real engines never see uplight, which is
        // exactly why a faint one reads as "lifted onto a stage."
        let underLight = SCNNode()
        underLight.light = SCNLight()
        underLight.light?.type = .omni
        underLight.light?.intensity = 40
        underLight.light?.color = PlatformColor(red: 1.0, green: 0.65, blue: 0.30, alpha: 1.0)
        underLight.light?.attenuationStartDistance = 0.1
        underLight.light?.attenuationEndDistance = 1.2
        underLight.position = SCNVector3(0, -0.35, 0.1)
        scene.rootNode.addChildNode(underLight)

        // Neutral ambient fills the shadow side so unlit detail still reads.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 220
        ambient.light?.color = PlatformColor(white: 0.55, alpha: 1.0)
        scene.rootNode.addChildNode(ambient)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        private weak var scnView: SCNView?
        private var turntable: SCNNode?
        private var parts: ProceduralEngineParts?
        private var currentSpecId: UUID?

        private var accumulatedCrankAngle: Double = 0.0
        private var accumulatedTurntableAngle: Double = 0.0
        private var lastUpdateTime: TimeInterval = 0.0

        func attach(to view: SCNView, spec: EngineSpec) {
            self.scnView = view
            installTurntable(in: view)
            rebuild(with: spec)
        }

        func swapTo(spec: EngineSpec) {
            if spec.id == currentSpecId { return }
            rebuild(with: spec)
        }

        // MARK: Build

        private func installTurntable(in view: SCNView) {
            guard let scene = view.scene else { return }
            let node = SCNNode()
            node.name = "paywallTurntable"
            scene.rootNode.addChildNode(node)
            turntable = node
            installCamera(in: scene)
        }

        private func installCamera(in scene: SCNScene) {
            let cam = SCNNode()
            cam.name = "paywallCamera"
            let camera = SCNCamera()
            camera.zNear = 0.005
            camera.zFar = 50.0
            camera.fieldOfView = 36
            // Bloom was blowing the warm rim light into a yellow haze that
            // hid engine detail — disabled entirely. HDR auto-exposure was
            // also pushing mid-tones too bright; without HDR the lights
            // hit the surface at their literal intensity. The vignette is
            // still safe (cheap post-fx, only darkens the corners).
            camera.wantsHDR = false
            camera.vignettingIntensity = 0.6
            camera.vignettingPower = 0.4
            cam.camera = camera
            scene.rootNode.addChildNode(cam)
        }

        private func rebuild(with spec: EngineSpec) {
            guard let turntable = turntable, let scene = scnView?.scene else { return }

            turntable.childNodes.forEach { $0.removeFromParentNode() }
            parts = nil
            accumulatedCrankAngle = 0
            // Keep the turntable angle so we don't snap back to 0 on swap.

            let built = ProceduralEngineAssembly.build(spec: spec)
            turntable.addChildNode(built.assemblyNode)
            parts = built
            currentSpecId = spec.id

            frameCamera(for: built.params, in: scene)
        }

        /// Sit the camera back far enough that any built-in (Geo through LFA V10)
        /// fits the hero rect, looking *very slightly* down on the engine.
        ///
        /// The engine is rotated so its bore axis points world-up: the crank sits
        /// at the local origin and the block/head extend upward from there, so the
        /// assembly's vertical center is at `blockCenterZ` (world +Y), NOT at the
        /// origin. The camera must aim at that centroid — aiming at the origin
        /// (the crank) leaves the engine reading high in the frame.
        ///
        /// • distance is 2.0× the block diagonal so the tallest engines (LFA V10,
        ///   F1 V12) don't crowd the viewport.
        /// • the camera sits a touch above the centroid for a slight tilt-down,
        ///   and looks straight at the centroid so the engine is vertically
        ///   centered regardless of viewport aspect ratio.
        private func frameCamera(for p: EngineGeometryParams, in scene: SCNScene) {
            guard let cam = scene.rootNode.childNode(withName: "paywallCamera", recursively: false) else { return }
            let diag = sqrt(p.blockLength * p.blockLength
                          + p.blockWidth * p.blockWidth
                          + p.blockHeight * p.blockHeight)
            let distance = Float(diag * 2.0)
            let centerY = Float(p.blockCenterZ)
            let tiltLift = Float(p.blockHeight) * 0.08
            cam.position = SCNVector3(0, centerY + tiltLift, distance)
            cam.look(at: SCNVector3(0, centerY, 0))
        }

        // MARK: Animation loop

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt: Double
            if lastUpdateTime > 0 {
                dt = min(time - lastUpdateTime, 1.0 / 30.0)
            } else {
                dt = 1.0 / 60.0
            }
            lastUpdateTime = time

            let crankOmega = (heroCrankRPM / 60.0) * 2.0 * .pi
            accumulatedCrankAngle += crankOmega * dt
            if accumulatedCrankAngle > 100.0 * .pi {
                accumulatedCrankAngle = accumulatedCrankAngle.truncatingRemainder(dividingBy: 4.0 * .pi)
            }

            let turntableOmega = 2.0 * .pi / heroTurntablePeriod
            accumulatedTurntableAngle += turntableOmega * dt
            if accumulatedTurntableAngle > 2.0 * .pi {
                accumulatedTurntableAngle -= 2.0 * .pi
            }

            if let parts = parts {
                ProceduralEngineAssembly.animate(parts: parts, crankAngle: accumulatedCrankAngle)
            }
            turntable?.eulerAngles = SCNVector3(0, Float(accumulatedTurntableAngle), 0)
        }
    }
}
