import SwiftUI
import Sentry

#if os(macOS)
import AppKit
#endif

/// Fixed sidebar width on iOS — mirrors the macOS NavigationSplitView
/// ideal width so the layout looks identical across platforms.
private let iosSidebarWidth: CGFloat = 260

/// Global UI scale on iOS. Every macOS dimension is sized for a 1920+px
/// desktop window; an 11" iPad is ~1180px wide in landscape, so without a
/// scale the top bar, sidebar, builder cards, and tile chrome eat the
/// screen. Rendering the content at its native (macOS) size and then
/// scaleEffect-ing it down to fit gives every view proportionally less
/// real estate, which is exactly what dense dashboards want. Touch areas
/// scale with the view so interaction targets stay aligned.
///
/// 0.7 hits the sweet spot where text is still readable and dash tiles
/// look like a Le Mans dash rather than an iPhone widget. Adjust here to
/// tune the whole iOS app at once.
private let iosGlobalScale: CGFloat = 0.7

/// Small inset on the iPhone leading edge (notch-free side after the
/// landscape-left orientation lock). The safe area there is ignored so the
/// sidebar / app chrome can run almost to the corner, but a sliver of
/// padding keeps content out of the rounded-corner cut-off.
private let iosLeadingInset: CGFloat = 14

/// Launch splash timing. The hold covers the tach key-on sweep (stir → sweep →
/// hold → settle to idle, reaching idle ~2.45s) plus a brief idle linger, then
/// the splash crossfades out over `launchSplashFade`. It's a deliberate brand
/// beat, not a wait on real work — the first engine is already built in
/// TileSurfApp.init before any frame renders.
private let launchSplashHold: Double = 2.9
private let launchSplashFade: Double = 0.5

@main
struct TileSurfApp: App {
    @StateObject private var rootViewModel: RootViewModel
    @StateObject private var engineViewModel: EngineViewModel
    @StateObject private var purchaseManager: PurchaseManager
    @StateObject private var playerIdentity: PlayerIdentity
    @State private var keyboardController: KeyboardController
    // Pinned to .all so iOS doesn't hide the detail column behind the
    // sidebar (the default on compact widths and iPad portrait). With the
    // orientation lock to landscape the tile area always has room.
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    // Drives the iOS sidebar collapse/expand. The macOS sidebar is
    // controlled via the responder chain, so this is iOS-only.
    @ObservedObject private var sidebarManager = SidebarManager.shared
    // Branded launch splash, shown over everything from frame one and crossfaded
    // away after a short hold (see launchSplashHold).
    @State private var showLaunchSplash = true

    init() {
        // Start crash/error reporting first, before any other startup work,
        // so failures during bootstrap are captured.
        configureSentry()

        // Boot the StoreKit purchase layer before any view binds to
        // PurchaseManager — it loads the product + entitlement state and
        // starts listening for transaction updates during bootstrap.
        PurchaseManager.configure()

        let oscilloscopeManager = OscilloscopeManager()
        let engineViewModelInst = EngineViewModel(oscillioscopeManager: oscilloscopeManager)
        self._engineViewModel = StateObject(wrappedValue: engineViewModelInst)
        self._purchaseManager = StateObject(wrappedValue: PurchaseManager.shared)
        self._playerIdentity = StateObject(wrappedValue: PlayerIdentity.shared)
        // Resolve the layout to boot into. Order: last-used (per UserDefaults)
        // → Default. The lookup goes through TileStore.shared.layouts, which
        // already merges built-ins with user-saved layouts, so a custom one
        // the user picked last time also re-opens here.
        let storedId = UserDefaults.standard
            .string(forKey: RootViewModel.lastActiveLayoutKey)
            .flatMap(UUID.init(uuidString:))
        let resolved = storedId
            .flatMap { id in TileStore.shared.layouts.first(where: { $0.id == id }) }
            ?? BuiltInLayouts.defaultLayout
        self._rootViewModel = StateObject(wrappedValue: RootViewModel(
            engineVm: engineViewModelInst,
            data: resolved.rootData,
            activeLayoutId: resolved.id)
        )
        self._keyboardController = State(
            initialValue: KeyboardController(engineVm: engineViewModelInst)
        )
    }
    
    var body: some Scene {
        WindowGroup {
            scaledRoot
                .environmentObject(purchaseManager)
                .background(Color.appBackground)
                #if os(macOS)
                .toolbarBackground(Color.appBackground, for: .windowToolbar)
                .toolbarColorScheme(.dark, for: .windowToolbar)
                .toolbarRole(.editor)
                .onAppear { resizeMacWindowToScreen() }
                #endif
                .onKeyPress { press in
                    handleKeyPress(press: press)
                }
            
                // First-launch onboarding sits above everything at true window
                // size (outside the iOS content scaleEffect) so its prose and
                // the real dash controls it renders stay comfortably readable.
                .overlay {
                    if !playerIdentity.hasCompletedOnboarding {
                        OnboardingView(identity: playerIdentity)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3),
                           value: playerIdentity.hasCompletedOnboarding)

                // Launch splash sits above everything (including onboarding) at
                // true window size, outside the iOS content scaleEffect, so the
                // lockup stays crisp. Mounted from frame one; crossfades out
                // after a brief brand hold.
                .overlay {
                    if showLaunchSplash {
                        LaunchSplashView()
                            .transition(.opacity)
                            .task {
                                try? await Task.sleep(
                                    nanoseconds: UInt64(launchSplashHold * 1_000_000_000)
                                )
                                withAnimation(.easeInOut(duration: launchSplashFade)) {
                                    showLaunchSplash = false
                                }
                            }
                    }
                }
        }
        #if os(macOS)
        .commands {
            tileSurfCommands(rootViewModel: rootViewModel)
        }
        #endif
    }

    /// On iOS, draw the entire rootScene at a `1/scale` virtual canvas and
    /// then `scaleEffect` it down to the real screen size. SwiftUI lays out
    /// at the virtual size (so the macOS-tuned numbers are honored exactly),
    /// while the user sees a proportionally smaller, denser dashboard.
    @ViewBuilder
    private var scaledRoot: some View {
        #if os(macOS)
        rootScene
        #else
        // Orientation is locked to landscape-left so the iPhone notch is
        // always on the RIGHT edge. We ignore the safe area on the left,
        // top, and bottom (status bar is hidden, home indicator is a thin
        // bar that doesn't visually clash) but keep the RIGHT safe area
        // so content never hides behind the notch. A small leading inset
        // keeps the sidebar out of the rounded-corner cut-off.
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        GeometryReader { geo in
            rootScene
                .frame(
                    width: geo.size.width / iosGlobalScale,
                    height: geo.size.height / iosGlobalScale
                )
                .scaleEffect(iosGlobalScale, anchor: .topLeading)
        }
        .padding(.leading, isPad ? 0 : iosLeadingInset)
        // Respect the BOTTOM safe area on iPhone so the home indicator
        // doesn't sit on top of dashboard content (this was clipping the
        // 0-60 timer's Run / Reset buttons when the sidebar collapsed and
        // the timer column reflowed).
        .ignoresSafeArea(.container, edges: isPad ? .all : [.leading, .top])
        // iPadOS does not always honour the Info.plist UIStatusBarHidden flag
        // (e.g. in Stage Manager), so the status bar can sit on top of the
        // full-bleed dashboard. Re-assert it at the view level to reclaim the
        // top edge. iPhone is already hidden; re-asserting is harmless.
        .statusBarHidden(true)
        #endif
    }

    private var rootScene: some View {
        #if os(macOS)
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            SideBarView(rootViewModel: rootViewModel)
                .navigationSplitViewColumnWidth(ideal: 260)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        // Fold the sidebar away while the engine builder is up so it gets the
        // full window, then restore it on exit. iOS handles this in RootView
        // via SidebarManager; macOS drives the split-view column directly.
        .onChange(of: rootViewModel.isBuildingEngine) { _, building in
            splitViewVisibility = building ? .detailOnly : .all
        }
        #else
        // iOS: NavigationSplitView collapses the detail column behind the
        // sidebar in any compact context (iPhone, iPad slide-over, smaller
        // scene sizes). Since the app is landscape-only and the tile area
        // needs to be visible at all times, sidestep the column-collapse
        // logic with a plain HStack. SidebarManager.isSidebarHidden lets
        // the user collapse the sidebar from the top-bar toggle.
        HStack(spacing: 0) {
            if !sidebarManager.isSidebarHidden {
                SideBarView(rootViewModel: rootViewModel)
                    .frame(width: iosSidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.22), value: sidebarManager.isSidebarHidden)
        #endif
    }

    #if os(macOS)
    /// Forces the freshly-opened window to fill the screen, since SwiftUI's
    /// default `WindowGroup` sizing is a small floating panel.
    private func resizeMacWindowToScreen() {
        DispatchQueue.main.async {
            let key = NSApplication.shared.windows.first(where: { $0.isKeyWindow })
            guard let window = key ?? NSApplication.shared.windows.first,
                  let screen = window.screen else { return }
            window.setFrame(screen.visibleFrame, display: true)
        }
    }
    #endif
    
    var detailView: some View {
        ZStack {
            RootView(vm: rootViewModel)
        }
        .navigationTitle("")
    }
    
    func handleKeyPress(press: KeyPress) -> KeyPress.Result {
        if press.key == .escape && rootViewModel.browserMode != .operational {
            rootViewModel.browserMode = .operational
            return .handled
        }
        return .ignored
    }
}

@CommandsBuilder
func tileSurfCommands(rootViewModel: RootViewModel) -> some Commands {
    CommandGroup(after: .newItem) {
        Button("Toggle Split") { rootViewModel.toggleSplitMode() }
            .keyboardShortcut("t", modifiers: [.command])

        Button("Toggle Sidebar") { SidebarManager.shared.toggleSidebar() }
            .keyboardShortcut("b", modifiers: [.command])

        Button("Toggle Delete") { rootViewModel.toggleDeleteMode() }
            .keyboardShortcut("d", modifiers: [.command])

        Button("Save Workspace") { rootViewModel.presentSaveLayout() }
            .keyboardShortcut("s", modifiers: [.command])
    }

#if DEBUG
    CommandMenu("Debug") {
        Button("Reset Purchases (show paywall again)") {
            Task { await PurchaseManager.shared.resetPurchasesForDebug() }
        }
    }
#endif
}
