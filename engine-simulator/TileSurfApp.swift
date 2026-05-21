import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#endif

/// RevenueCat sandbox key. Swap to the production key on release.
private let revenueCatAPIKey = "test_ZYpdwVJIKcNhwMICqAkYNPRCGur"

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

@main
struct TileSurfApp: App {
    @StateObject private var rootViewModel: RootViewModel
    @StateObject private var engineViewModel: EngineViewModel
    @StateObject private var purchaseManager: PurchaseManager
    @State private var keyboardController: KeyboardController
    // Pinned to .all so iOS doesn't hide the detail column behind the
    // sidebar (the default on compact widths and iPad portrait). With the
    // orientation lock to landscape the tile area always has room.
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    // Drives the iOS sidebar collapse/expand. The macOS sidebar is
    // controlled via the responder chain, so this is iOS-only.
    @ObservedObject private var sidebarManager = SidebarManager.shared

    init() {
        // Boot RevenueCat before any view binds to PurchaseManager — the
        // singleton subscribes to customerInfoStream during bootstrap.
        PurchaseManager.configure(apiKey: revenueCatAPIKey)

        let oscilloscopeManager = OscilloscopeManager()
        let engineViewModelInst = EngineViewModel(oscillioscopeManager: oscilloscopeManager)
        self._engineViewModel = StateObject(wrappedValue: engineViewModelInst)
        self._purchaseManager = StateObject(wrappedValue: PurchaseManager.shared)
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
        // iPad has no notch — ignoring safe area here gives the builder
        // and tile area the full screen, which is what the user expects on
        // a flat slab. iPhone landscape DOES have a notch cutting into one
        // long edge, so we leave the safe area in place there to keep the
        // sidebar's leading column clear of the cutout.
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        GeometryReader { geo in
            rootScene
                .frame(
                    width: geo.size.width / iosGlobalScale,
                    height: geo.size.height / iosGlobalScale
                )
                .scaleEffect(iosGlobalScale, anchor: .topLeading)
        }
        .ignoresSafeArea(.container, edges: isPad ? .all : [])
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
//            if selection == "history" {
//                
//            } else if selection == "cookies" {
//                
//            } else {
                RootView(vm: rootViewModel)
//            }
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
}

/*
 Purchases.configure(withAPIKey: "test_EUzsEZEBTCqmFZJGCPNcKZoLWCg")
 
 SentrySDK.start { options in
     options.dsn = "https://dcd05699e199354cd229fe74e8eaa55c@o4510452902526976.ingest.us.sentry.io/4510452906721280"

     // Adds IP for users.
     // For more information, visit: https://docs.sentry.io/platforms/apple/data-management/data-collected/
     options.sendDefaultPii = true

     // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
     // We recommend adjusting this value in production.
     options.tracesSampleRate = 1.0

     // Configure profiling. Visit https://docs.sentry.io/platforms/apple/profiling/ to learn more.
     options.configureProfiling = {
         $0.sessionSampleRate = 1.0 // We recommend adjusting this value in production.
         $0.lifecycle = .trace
     }

     // Uncomment the following lines to add more data to your events
     // options.attachScreenshot = true // This adds a screenshot to the error events
     // options.attachViewHierarchy = true // This adds the view hierarchy to the error events

     // Enable experimental logging features
     options.experimental.enableLogs = true

     // Saad:
     options.enableCrashHandler = true
 }
 // Remove the next line after confirming that your Sentry integration is working.
 */
