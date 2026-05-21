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
private let paywallCardBorder = Color.white.opacity(0.10)
private let paywallCardCorner: CGFloat = 14
private let paywallMaxWidth: CGFloat = 520
private let paywallContentSpacing: CGFloat = 18
private let paywallPadding: CGFloat = 24

private let heroHeight: CGFloat = 260
private let heroCorner: CGFloat = 10
private let heroBackground = Color.black.opacity(0.55)
private let heroBorder = Color.white.opacity(0.08)
private let heroAnnotationBg = Color.black.opacity(0.50)
private let heroAnnotationBorder = Color.white.opacity(0.06)

private let ctaIdleFill = Color.orange
private let ctaIdleText = Color.black
private let ctaHoverFill = Color.orange.opacity(0.88)
private let bodyText = Color.white.opacity(0.85)
private let mutedText = Color.white.opacity(0.45)
private let dividerColor = Color.white.opacity(0.08)
private let successColor = Color.green
private let errorColor = Color.red.opacity(0.9)

// MARK: - Carousel constants

/// Seconds each engine stays on screen before crossfading to the next.
private let carouselDwellSeconds: TimeInterval = 7.0
/// Crank speed for the hero. Slow enough that the eye reads each stroke.
private let heroCrankRPM: Double = 15.0
/// Full turntable revolution duration (seconds). Independent of crank.
private let heroTurntablePeriod: Double = 12.0
/// Locked store price. The PurchaseManager's localized string will be used
/// if a product is loaded; this is the fallback + the price we ship at.
private let lockedPrice = "$9.99"

// MARK: - View

struct PaywallSheet: View {
    @ObservedObject var manager: PurchaseManager
    @StateObject private var carousel = EngineCarousel()
    @State private var hoverCTA = false

    var body: some View {
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
        .transition(.opacity)
        .onAppear { carousel.start() }
        .onDisappear { carousel.stop() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("ENGINE SIMULATOR")
                .modifier(RetroFont(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(bodyText)
            Text("PRO")
                .modifier(RetroFont(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.orange.opacity(0.6), lineWidth: 1)
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
        ZStack(alignment: .bottom) {
            heroBackdrop
            PaywallEngineHero(carousel: carousel)
                .frame(height: heroHeight)

            heroAnnotation
        }
        .frame(height: heroHeight)
        .overlay(
            RoundedRectangle(cornerRadius: heroCorner)
                .stroke(heroBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: heroCorner))
    }

    /// Radial spotlight behind the SCN view. SceneKit's vignette dims the
    /// frame; this brightens the center so the engine sits in a warm pool.
    private var heroBackdrop: some View {
        RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Color(red: 0.18, green: 0.13, blue: 0.10), location: 0),
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
            HStack(alignment: .firstTextBaseline) {
                Text(carousel.currentName.uppercased())
                    .modifier(RetroFont(size: 12, weight: .bold))
                    .tracking(2.5)
                    .foregroundColor(.white)
                    .id(carousel.currentName)
                    .transition(.opacity)
                Spacer()
                Text(carousel.currentSubtitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(bodyText)
                    .id(carousel.currentSubtitle)
                    .transition(.opacity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(heroAnnotationBg)

            CarouselProgressBar(count: carousel.count,
                                currentIndex: carousel.currentIndex)
                .frame(height: 2)
        }
    }

    // MARK: Copy

    private var copyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lifetime access to the full simulator.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text("Every preset engine, full ECU tuning, every future update.")
                    .font(.system(size: 12))
                    .foregroundColor(mutedText)
            }
            buildYourOwnCallout
        }
    }

    /// Quiet reminder that the presets above aren't the limit — Pro unlocks
    /// the full builder. Wrench glyph + a single short line.
    private var buildYourOwnCallout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.orange.opacity(0.85))
            Text("Or design your own from scratch in the engine builder — any layout, bore, stroke, cam, and tune.")
                .font(.system(size: 12))
                .foregroundColor(bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
        // The manager falls back to "$9.99" already, but if RevenueCat
        // returns a localized variant (e.g. "US$9.99") we still show it.
        return label.isEmpty ? lockedPrice : label
    }

    // MARK: CTA

    private var primaryCTA: some View {
        Button(action: triggerPurchase) {
            HStack(spacing: 8) {
                if manager.purchaseState == .loading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: ctaIdleText))
                        .scaleEffect(0.7)
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
                    .fill(Color.orange.opacity(0.75))
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
        timer = Timer.scheduledTimer(withTimeInterval: carouselDwellSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
private struct PaywallEngineHero: NSViewRepresentable {
    @ObservedObject var carousel: EngineCarousel

    func makeNSView(context: Context) -> SCNView {
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

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.swapTo(spec: carousel.currentSpec)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Lights

    private func configureLights(in scene: SCNScene) {
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 700
        key.light?.color = NSColor(white: 0.98, alpha: 1.0)
        key.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(key)

        // Warm rim light from behind / off-axis — gives the gold edge
        // highlight that reads as "showroom" rather than "viewport".
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 450
        rim.light?.color = NSColor(red: 1.0, green: 0.78, blue: 0.45, alpha: 1.0)
        rim.eulerAngles = SCNVector3(-Float.pi / 8, -Float.pi * 0.7, 0)
        scene.rootNode.addChildNode(rim)

        // Subtle warm under-light. Real engines never see uplight, which is
        // exactly why a faint one reads as "lifted onto a stage."
        let underLight = SCNNode()
        underLight.light = SCNLight()
        underLight.light?.type = .omni
        underLight.light?.intensity = 220
        underLight.light?.color = NSColor(red: 1.0, green: 0.65, blue: 0.30, alpha: 1.0)
        underLight.light?.attenuationStartDistance = 0.1
        underLight.light?.attenuationEndDistance = 1.2
        underLight.position = SCNVector3(0, -0.35, 0.1)
        scene.rootNode.addChildNode(underLight)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 95
        ambient.light?.color = NSColor(white: 0.40, alpha: 1.0)
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
            // HDR + bloom gives metallic highlights a soft glow on the rim
            // light; the vignette darkens the frame edges so the engine
            // sits in a pool of light. Subtle on purpose.
            camera.wantsHDR = true
            camera.bloomIntensity = 0.65
            camera.bloomThreshold = 0.85
            camera.bloomBlurRadius = 12.0
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
        /// fits the hero rect, looking slightly down on the engine.
        private func frameCamera(for p: EngineGeometryParams, in scene: SCNScene) {
            guard let cam = scene.rootNode.childNode(withName: "paywallCamera", recursively: false) else { return }
            let diag = sqrt(p.blockLength * p.blockLength
                          + p.blockWidth * p.blockWidth
                          + p.blockHeight * p.blockHeight)
            let distance = Float(diag * 1.4)
            cam.position = SCNVector3(0, Float(p.blockHeight) * 0.25, distance)
            cam.look(at: SCNVector3(0, 0, 0))
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
