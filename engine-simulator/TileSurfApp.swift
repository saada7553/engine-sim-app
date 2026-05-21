import SwiftUI
import WebKit

@main
struct TileSurfApp: App {
    @StateObject private var rootViewModel: RootViewModel
    @StateObject private var engineViewModel: EngineViewModel
    @State private var keyboardController: KeyboardController

    init() {
        let oscilloscopeManager = OscilloscopeManager()
        let engineViewModelInst = EngineViewModel(oscillioscopeManager: oscilloscopeManager)
        self._engineViewModel = StateObject(wrappedValue: engineViewModelInst)
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
            NavigationSplitView {
                SideBarView(
                    rootViewModel: rootViewModel
                )
                .navigationSplitViewColumnWidth(ideal: 260)
            } detail: {
                detailView
            }
            .background(Color.appBackground)
            .toolbarBackground(Color.appBackground, for: .windowToolbar)
            .toolbarColorScheme(.dark, for: .windowToolbar)
            .toolbarRole(.editor)
            .onAppear {
                DispatchQueue.main.async {
                    if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? NSApplication.shared.windows.first {
                        if let screen = window.screen {
                            window.setFrame(screen.visibleFrame, display: true)
                        }
                    }
                }
            }
            .onKeyPress { press in
                handleKeyPress(press: press)
            }
        }
        .commands {
            tileSurfCommands(rootViewModel: rootViewModel)
        }
    }
    
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
