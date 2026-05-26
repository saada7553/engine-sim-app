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
        static let b: UInt16 = 11
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

    /// Engine keys that should never reach the system while the tutorial is up,
    /// so pressing them drives the demo (or does nothing) instead of beeping.
    private static let engineKeyCodes: Set<UInt16> = [
        KeyCode.a, KeyCode.s, KeyCode.d, KeyCode.h, KeyCode.b,
        KeyCode.space, KeyCode.arrowUp, KeyCode.arrowDown
    ]

    /// Returns nil to consume the event, or the event itself to pass it through.
    private func handle(_ event: NSEvent) -> NSEvent? {
        // While the first-launch tutorial is up the live engine must stay dead.
        // Engine keys instead drive the tutorial's on-screen demo controls and
        // are swallowed so they don't beep — except while the username field is
        // being edited, where every key must reach the text field.
        if !PlayerIdentity.shared.hasCompletedOnboarding {
            guard !isEditingText else { return event }
            return handleOnboardingKey(event)
        }

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

    /// Tutorial routing: A toggles the demo ignition, S cranks it, Shift toggles
    /// the demo clutch — all on `OnboardingEngineDemo`, never the real engine.
    /// Every other engine key is swallowed so the tutorial stays quiet; keys we
    /// don't own pass through untouched.
    private func handleOnboardingKey(_ event: NSEvent) -> NSEvent? {
        let demo = OnboardingEngineDemo.shared
        switch event.type {
        case .flagsChanged:
            let shiftDown = event.modifierFlags.contains(.shift)
            if shiftDown && !clutchKeyHeld { demo.toggleClutch() }
            clutchKeyHeld = shiftDown
            return event
        case .keyDown:
            guard event.modifierFlags.isDisjoint(with: Self.menuModifiers) else { return event }
            if !event.isARepeat {
                switch event.keyCode {
                case KeyCode.a: demo.toggleIgnition()
                case KeyCode.s: demo.toggleStarter()
                default: break
                }
            }
            return Self.engineKeyCodes.contains(event.keyCode) ? nil : event
        case .keyUp:
            return Self.engineKeyCodes.contains(event.keyCode) ? nil : event
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
        case KeyCode.b:
            // Press-and-hold brake — full pressure while held.
            if !event.isARepeat {
                engineVm.beginBrake()
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
        switch event.keyCode {
        case KeyCode.space:
            engineVm.endRev()
            return nil
        case KeyCode.b:
            engineVm.endBrake()
            return nil
        default:
            return event
        }
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
