//
//  KeyboardController.swift
//  engine-simulator
//
//  Maps physical keyboard input to engine controls. See ControlsMenuView for
//  the user-facing reference of these bindings.
//

#if os(macOS)
import AppKit
#endif

/// Installs an app-wide key monitor that drives the engine simulation.
/// Engine keys are ignored while a text field is being edited or while a menu
/// shortcut modifier (Command/Control/Option) is held.
///
/// iOS doesn't get the global NSEvent monitor — the dashboard there is driven
/// by on-screen controls and SwiftUI's `.onKeyPress` for any attached hardware
/// keyboard. The Swift call sites only need a stable type with the same init,
/// so on iOS this collapses to an empty stub.
#if os(macOS)
final class KeyboardController {
    private let engineVm: EngineViewModel
    private var monitor: Any?
    private var clutchKeyHeld = false

    private enum KeyCode {
        static let a: UInt16 = 0
        static let s: UInt16 = 1
        static let d: UInt16 = 2
        static let h: UInt16 = 4
        static let space: UInt16 = 49
        static let arrowUp: UInt16 = 126
        static let arrowDown: UInt16 = 125
    }

    private static let menuModifiers: NSEvent.ModifierFlags = [.command, .control, .option]

    init(engineVm: EngineViewModel) {
        self.engineVm = engineVm
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            // Returning nil consumes the event; only fall back to passing it
            // through if the controller itself has gone away.
            guard let self else { return event }
            return self.handle(event)
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Returns nil to consume the event, or the event itself to pass it through.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !isEditingText else { return event }

        switch event.type {
        case .flagsChanged:
            handleClutchModifier(event)
            return event
        case .keyDown:
            guard event.modifierFlags.isDisjoint(with: Self.menuModifiers) else { return event }
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        default:
            return event
        }
    }

    /// Shift toggles the clutch on each fresh press (modifier-only keys arrive
    /// as flagsChanged events rather than keyDown/keyUp).
    private func handleClutchModifier(_ event: NSEvent) {
        let shiftDown = event.modifierFlags.contains(.shift)
        if shiftDown && !clutchKeyHeld {
            engineVm.toggleClutch()
        }
        clutchKeyHeld = shiftDown
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case KeyCode.space:
            if !event.isARepeat {
                engineVm.beginRev()
            }
            return nil
        case KeyCode.a, KeyCode.s, KeyCode.d, KeyCode.h,
             KeyCode.arrowUp, KeyCode.arrowDown:
            // Toggles/shifts fire once per press, not on auto-repeat.
            if !event.isARepeat {
                performAction(for: event.keyCode)
            }
            return nil
        default:
            return event
        }
    }

    private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == KeyCode.space else { return event }
        engineVm.endRev()
        return nil
    }

    private func performAction(for keyCode: UInt16) {
        switch keyCode {
        case KeyCode.a: engineVm.toggleIgnition()
        case KeyCode.s: engineVm.toggleStarter()
        case KeyCode.d: engineVm.toggleDyno()
        case KeyCode.h: engineVm.toggleHold()
        case KeyCode.arrowUp: engineVm.shiftUp()
        case KeyCode.arrowDown: engineVm.shiftDown()
        default: break
        }
    }

    private var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSText
    }
}
#else
final class KeyboardController {
    init(engineVm: EngineViewModel) {
        _ = engineVm
    }
}
#endif
