import AppKit
import Observation
import OSLog

/// A keyboard input that webOS can receive through its remote APIs.
enum TVKeyboardInput: Equatable, Sendable {
    case text(String)
    case delete
    case enter
    case navigation(TVNavigationButton)

    static func from(characters: String, keyCode: UInt16) -> Self? {
        switch keyCode {
        case 36, 76: return .enter
        case 51: return .delete
        case 123: return .navigation(.left)
        case 124: return .navigation(.right)
        case 125: return .navigation(.down)
        case 126: return .navigation(.up)
        default:
            guard !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else {
                return nil
            }
            return .text(characters)
        }
    }
}

/// Mirrors macOS mouse movement, primary clicks, scrolling, and typing to the TV while enabled.
@MainActor
@Observable
final class MouseControlManager {
    private let controller: TVController
    private let logger = Logger(subsystem: "com.lgtvmenubar", category: "MouseControlManager")
    private var inputEventTap: CFMachPort?
    private var inputEventTapSource: CFRunLoopSource?
    private let scrollSensitivity: CGFloat = 0.05
    private var pendingDeltaX: CGFloat = 0
    private var pendingDeltaY: CGFloat = 0
    private var pendingScrollX: CGFloat = 0
    private var pendingScrollY: CGFloat = 0
    private var movementFlushTask: Task<Void, Never>?
    private var scrollFlushTask: Task<Void, Never>?
    private var keyboardTask: Task<Void, Never>?

    private(set) var isEnabled = false
    private(set) var unavailableReason: String?

    init(controller: TVController) {
        self.controller = controller
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled else {
            stop()
            return
        }

        guard !isEnabled, controller.connectionState.isConnected else { return }
        guard controller.hasAccessibilityPermission() else {
            unavailableReason = "Accessibility permission is required for keyboard control."
            return
        }
        guard startInputCapture() else {
            unavailableReason = "Mouse and keyboard capture could not be started."
            return
        }

        unavailableReason = nil
        isEnabled = true
        logger.info("TV mouse and keyboard control enabled")
        controller.diagnosticLogger.log(level: "info", category: "MouseControl", message: "TV pointer control enabled", metadata: nil)
    }

    func stop() {
        guard isEnabled || inputEventTap != nil else { return }

        stopInputCapture()
        movementFlushTask?.cancel()
        movementFlushTask = nil
        scrollFlushTask?.cancel()
        scrollFlushTask = nil
        keyboardTask?.cancel()
        keyboardTask = nil
        pendingDeltaX = 0
        pendingDeltaY = 0
        pendingScrollX = 0
        pendingScrollY = 0
        isEnabled = false
        logger.info("TV mouse and keyboard control disabled")
        controller.diagnosticLogger.log(level: "info", category: "MouseControl", message: "TV pointer control disabled", metadata: nil)
    }

    private func startInputCapture() -> Bool {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passRetained(event)
                }

                let manager = Unmanaged<MouseControlManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleInputEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        inputEventTap = eventTap
        inputEventTapSource = source
        return true
    }

    private func stopInputCapture() {
        if let source = inputEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            inputEventTapSource = nil
        }
        if let eventTap = inputEventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            inputEventTap = nil
        }
    }

    private nonisolated func handleInputEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Task { @MainActor [weak self] in
                self?.resumeInputCapture()
            }
            return Unmanaged.passRetained(event)
        case .keyDown:
            return handleKeyboardEvent(event)
        case .mouseMoved, .leftMouseDragged:
            let dx = event.getDoubleValueField(.mouseEventDeltaX)
            let dy = event.getDoubleValueField(.mouseEventDeltaY)
            Task { @MainActor [weak self] in
                self?.enqueuePointerMove(dx: dx, dy: dy)
            }
            return Unmanaged.passRetained(event)
        case .leftMouseDown:
            Task { @MainActor [weak self] in
                self?.sendPointerClick()
            }
            return nil
        case .scrollWheel:
            guard let scrollEvent = NSEvent(cgEvent: event) else {
                return Unmanaged.passRetained(event)
            }
            let dx = scrollEvent.scrollingDeltaX
            let dy = scrollEvent.scrollingDeltaY
            Task { @MainActor [weak self] in
                self?.enqueuePointerScroll(dx: dx, dy: dy)
            }
            return nil
        default:
            return Unmanaged.passRetained(event)
        }
    }

    private func resumeInputCapture() {
        guard let inputEventTap else { return }
        CGEvent.tapEnable(tap: inputEventTap, enable: true)
        logger.warning("TV pointer input capture was disabled and has been re-enabled")
        controller.diagnosticLogger.log(level: "warning", category: "MouseControl", message: "TV pointer input capture was re-enabled", metadata: nil)
    }

    private nonisolated func handleKeyboardEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let keyEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passRetained(event)
        }

        if keyEvent.keyCode == 53 {
            Task { @MainActor [weak self] in
                self?.stop()
            }
            return nil
        }

        let ignoredModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard keyEvent.modifierFlags.intersection(ignoredModifiers).isEmpty,
              let input = TVKeyboardInput.from(characters: keyEvent.characters ?? "", keyCode: keyEvent.keyCode) else {
            return Unmanaged.passRetained(event)
        }

        Task { @MainActor [weak self] in
            self?.sendKeyboardInput(input)
        }
        return nil
    }

    private func enqueuePointerMove(dx: CGFloat, dy: CGFloat) {
        guard isEnabled else { return }

        pendingDeltaX += dx
        pendingDeltaY += dy
        scheduleMovementFlush()
    }

    private func enqueuePointerScroll(dx: CGFloat, dy: CGFloat) {
        guard isEnabled else { return }

        pendingScrollX += dx * scrollSensitivity
        pendingScrollY += dy * scrollSensitivity
        scheduleScrollFlush()
    }

    private func scheduleMovementFlush() {
        guard isEnabled, movementFlushTask == nil else { return }

        movementFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled, let self else { return }
            self.movementFlushTask = nil
            await self.flushPendingMovement()
        }
    }

    private func scheduleScrollFlush() {
        guard isEnabled, scrollFlushTask == nil else { return }

        scrollFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled, let self else { return }
            self.scrollFlushTask = nil
            await self.flushPendingScroll()
        }
    }

    private func flushPendingMovement() async {
        guard isEnabled else { return }

        // ponytail: 40-pixel packets avoid webOS's non-linear large-delta handling; raise only after device testing.
        let dx = max(-40, min(40, Int(pendingDeltaX.rounded(.towardZero))))
        let dy = max(-40, min(40, Int(pendingDeltaY.rounded(.towardZero))))
        guard dx != 0 || dy != 0 else { return }

        pendingDeltaX -= CGFloat(dx)
        pendingDeltaY -= CGFloat(dy)

        do {
            try await controller.sendPointerMove(dx: dx, dy: dy)
            scheduleMovementFlush()
        } catch {
            logger.error("Failed to move TV pointer: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    private func flushPendingScroll() async {
        guard isEnabled else { return }

        let dx = max(-40, min(40, Int(pendingScrollX.rounded(.towardZero))))
        let dy = max(-40, min(40, Int(pendingScrollY.rounded(.towardZero))))
        guard dx != 0 || dy != 0 else { return }

        pendingScrollX -= CGFloat(dx)
        pendingScrollY -= CGFloat(dy)

        do {
            try await controller.sendPointerScroll(dx: dx, dy: dy)
            scheduleScrollFlush()
        } catch {
            logger.error("Failed to scroll TV pointer: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    private func sendPointerClick() {
        guard isEnabled else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.controller.sendPointerClick()
            } catch {
                self.logger.error("Failed to click TV pointer: \(error.localizedDescription, privacy: .public)")
                self.stop()
            }
        }
    }

    private func sendKeyboardInput(_ input: TVKeyboardInput) {
        let previousTask = keyboardTask
        keyboardTask = Task { @MainActor [weak self] in
            _ = await previousTask?.result
            guard let self, self.isEnabled else { return }

            do {
                switch input {
                case .text(let text):
                    try await self.controller.sendText(text)
                case .delete:
                    try await self.controller.deleteCharacters(1)
                case .enter:
                    try await self.controller.sendEnterKey()
                case .navigation(let button):
                    try await self.controller.sendNavigationButton(button)
                }
            } catch {
                self.logger.error("Failed to send TV keyboard input: \(error.localizedDescription, privacy: .public)")
                self.stop()
            }
        }
    }
}
