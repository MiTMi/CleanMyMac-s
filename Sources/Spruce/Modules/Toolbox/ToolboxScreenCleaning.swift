import AppKit
import Observation
import SpruceCore
import SwiftUI

// MARK: - Intro

/// Explains Screen Cleaning and starts a session.
struct ToolboxScreenCleaningScreen: View {
    var onBack: () -> Void

    var body: some View {
        ToolboxToolFrame(onBack: onBack) {
            ModuleIdleView(module: .toolbox,
                           title: "Screen Cleaning",
                           subtitle: "Black out every display and ignore keys, clicks and scrolling while you wipe.",
                           features: [
                               IdleFeature(symbol: "keyboard", title: "Input is ignored",
                                           detail: "Typing, clicking and scrolling do nothing, so wiping the keyboard or trackpad can't trigger anything."),
                               IdleFeature(symbol: "escape", title: "Hold Esc for 2 seconds to finish",
                                           detail: "Or press and hold \u{201C}Done\u{201D} on screen until its ring fills."),
                               IdleFeature(symbol: "circle.lefthalf.filled", title: "Spot smudges",
                                           detail: "Switch the screen between black, white and grey to see marks in different light."),
                               IdleFeature(symbol: "timer", title: "Ends by itself",
                                           detail: "After \(Int(ToolboxScreenCleaningTiming.limit / 60)) minutes, just in case."),
                           ],
                           actionTitle: "Start",
                           actionSubtitle: "Hold Esc to finish",
                           notice: "The power button, Touch ID and a few system shortcuts (like Spotlight) still work.",
                           action: { ToolboxScreenCleaningController.shared.start() })
        }
    }
}

// MARK: - Session state

/// What the overlay shows; updated by the controller about 20 times a second.
@MainActor
@Observable
final class ToolboxScreenCleaningSession {
    static let backgrounds: [(name: String, color: Color)] = [
        ("Black", Color.black), ("White", Color.white), ("Grey", Color(white: 0.5)),
    ]

    var backgroundIndex = 0
    var keyHoldProgress: Double = 0
    var buttonHoldProgress: Double = 0
    var remaining: TimeInterval = 0
    var instructionOpacity: Double = 1

    var holdProgress: Double { max(keyHoldProgress, buttonHoldProgress) }
}

// MARK: - Controller

/// Fixed timings of a session.
enum ToolboxScreenCleaningTiming {
    /// Esc (or the Done button) must be held this long.
    static let hold: TimeInterval = 2
    /// The session ends by itself after this long.
    static let limit: TimeInterval = 600
}

/// Keyboard state of a session, shared with the event monitor (which runs on the main
/// thread but is not actor-isolated), so it is lock-protected.
final class ToolboxCleaningInput: @unchecked Sendable {
    /// Virtual key code of Esc.
    private static let escapeKeyCode: UInt16 = 53

    private let lock = NSLock()
    private var hold = ToolboxHoldTracker(duration: ToolboxScreenCleaningTiming.hold)
    private var overlayWindows: Set<Int> = []

    func reset(overlayWindows: Set<Int>) {
        lock.lock()
        hold.release()
        self.overlayWindows = overlayWindows
        lock.unlock()
    }

    func keyHoldProgress(at date: Date) -> Double {
        lock.lock()
        defer { lock.unlock() }
        return hold.progress(at: date)
    }

    /// Swallows every keyboard, scroll, gesture and right/other-button event. Left
    /// clicks and mouse moves pass only when aimed at an overlay window (its Done button
    /// and background swatches). Esc is tracked for the hold-to-finish gesture.
    func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            if event.keyCode == Self.escapeKeyCode {
                lock.lock()
                hold.press(at: Date())
                lock.unlock()
            }
            return nil
        case .keyUp:
            if event.keyCode == Self.escapeKeyCode {
                lock.lock()
                hold.release()
                lock.unlock()
            }
            return nil
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved:
            lock.lock()
            let ours = overlayWindows.contains(event.windowNumber)
            lock.unlock()
            return ours ? event : nil
        default:
            return nil
        }
    }
}

/// Runs a Screen Cleaning session: one borderless black window per display at the
/// screen-saver level, a local event monitor that swallows keyboard, scroll and
/// right/other-button input (left clicks only reach the overlay's own controls),
/// presentation options that hide the Dock and menu bar and block app switching,
/// and a display-sleep assertion. Ends after holding Esc (or the Done button) for
/// 2 seconds, or after the safety time limit. Input is never locked beyond the
/// process: quitting or a crash releases everything.
@MainActor
final class ToolboxScreenCleaningController {
    static let shared = ToolboxScreenCleaningController()

    let session = ToolboxScreenCleaningSession()
    private(set) var isActive = false

    private let input = ToolboxCleaningInput()
    private var windows: [NSWindow] = []
    private var eventMonitor: Any?
    private var activity: NSObjectProtocol?
    private var ticker: Task<Void, Never>?
    private var previousOptions: NSApplication.PresentationOptions = []
    private var changedOptions = false
    private var buttonHold = ToolboxHoldTracker(duration: 2)
    private var clock = ToolboxCleaningClock(startedAt: Date(), limit: 600)

    func start() {
        guard !isActive else { return }
        isActive = true
        buttonHold = ToolboxHoldTracker(duration: ToolboxScreenCleaningTiming.hold)
        clock = ToolboxCleaningClock(startedAt: Date(), limit: ToolboxScreenCleaningTiming.limit)
        session.backgroundIndex = 0
        session.keyHoldProgress = 0
        session.buttonHoldProgress = 0
        session.remaining = ToolboxScreenCleaningTiming.limit
        session.instructionOpacity = 1

        NSApp.activate(ignoringOtherApps: true)
        makeWindows()
        input.reset(overlayWindows: Set(windows.map(\.windowNumber)))

        // Hide the Dock and menu bar and block ⌘-Tab / Force Quit while cleaning.
        // Skipped in full-screen mode, where the system manages these options itself.
        previousOptions = NSApp.presentationOptions
        if !previousOptions.contains(.fullScreen) {
            NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching,
                                         .disableForceQuit, .disableSessionTermination, .disableHideApplication]
            changedOptions = true
        }

        let mask: NSEvent.EventTypeMask = [
            .keyDown, .keyUp, .flagsChanged, .systemDefined, .scrollWheel,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved, .magnify, .swipe, .rotate, .smartMagnify, .gesture,
        ]
        let input = self.input
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            input.handle(event)
        }

        activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated],
                                                         reason: "Screen Cleaning")
        NSCursor.setHiddenUntilMouseMoves(true)

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, self.isActive else { return }
                self.tick()
            }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        ticker?.cancel()
        ticker = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        if changedOptions {
            NSApp.presentationOptions = previousOptions
            changedOptions = false
        }
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        NSCursor.setHiddenUntilMouseMoves(false)
        input.reset(overlayWindows: [])
        buttonHold.release()
        session.keyHoldProgress = 0
        session.buttonHoldProgress = 0
    }

    // MARK: Windows

    private func makeWindows() {
        let screens = NSScreen.screens
        for (index, screen) in screens.enumerated() {
            let window = ToolboxCleaningWindow(contentRect: screen.frame, styleMask: [.borderless],
                                               backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let overlay = ToolboxScreenCleaningOverlay(
                session: session,
                showsControls: index == 0,
                onHoldChanged: { [weak self] pressing in self?.setButtonPressed(pressing) },
                onFinish: { [weak self] in self?.stop() },
                onBackground: { [weak self] choice in self?.session.backgroundIndex = choice })
            window.contentView = NSHostingView(rootView: overlay)
            windows.append(window)
        }
        // The first screen holds the menu bar; it gets the controls and keyboard focus.
        windows.first?.makeKeyAndOrderFront(nil)
        for window in windows.dropFirst() {
            window.orderFrontRegardless()
        }
    }

    // MARK: Ticking

    private func setButtonPressed(_ pressing: Bool) {
        if pressing {
            buttonHold.press(at: Date())
        } else {
            buttonHold.release()
        }
    }

    private func tick() {
        let now = Date()
        let keyProgress = input.keyHoldProgress(at: now)
        session.keyHoldProgress = keyProgress
        session.buttonHoldProgress = buttonHold.progress(at: now)
        session.remaining = clock.remaining(at: now)
        session.instructionOpacity = clock.instructionOpacity(at: now)
        if keyProgress >= 1 || buttonHold.isComplete(at: now) || clock.isExpired(at: now) {
            stop()
            return
        }
        // Stay in front: input only reaches the monitor while Spruce is the active app.
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
            windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

/// Borderless overlay window that can take keyboard focus.
final class ToolboxCleaningWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Overlay

struct ToolboxScreenCleaningOverlay: View {
    var session: ToolboxScreenCleaningSession
    var showsControls: Bool
    var onHoldChanged: (Bool) -> Void
    var onFinish: () -> Void
    var onBackground: (Int) -> Void

    var body: some View {
        let backgrounds = ToolboxScreenCleaningSession.backgrounds
        let index = min(max(0, session.backgroundIndex), backgrounds.count - 1)
        let ink: Color = index == 1 ? .black : .white
        ZStack {
            backgrounds[index].color
                .ignoresSafeArea()
            if showsControls {
                instructions(ink: ink)
                VStack {
                    Spacer()
                    controls(ink: ink, selected: index)
                        .padding(.bottom, 48)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: index)
    }

    private func instructions(ink: Color) -> some View {
        VStack(spacing: 16) {
            Text("Screen Cleaning")
                .font(.system(size: 30, weight: .light))
            Text("Keys, clicks and scrolling are ignored.\nHold Esc for 2 seconds to finish.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
            ZStack {
                Circle()
                    .stroke(ink.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(session.holdProgress))
                    .stroke(ink.opacity(0.8), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 44, height: 44)
            .opacity(session.holdProgress > 0 ? 1 : 0)
            Text("Ends by itself in \(ToolboxCleaningClock.clockText(session.remaining))")
                .font(.system(size: 12).monospacedDigit())
        }
        .foregroundStyle(ink.opacity(0.45))
        .opacity(session.holdProgress > 0 ? 1 : session.instructionOpacity)
        .allowsHitTesting(false)
    }

    private func controls(ink: Color, selected: Int) -> some View {
        HStack(spacing: 28) {
            HStack(spacing: 10) {
                ForEach(Array(ToolboxScreenCleaningSession.backgrounds.enumerated()), id: \.offset) { offset, background in
                    Button {
                        onBackground(offset)
                    } label: {
                        Circle()
                            .fill(background.color)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(ink.opacity(offset == selected ? 0.8 : 0.25),
                                                           lineWidth: offset == selected ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .help(background.name)
                    .accessibilityLabel("\(background.name) background")
                }
            }
            ToolboxHoldToFinishButton(ink: ink, progress: session.buttonHoldProgress,
                                      onPressingChanged: onHoldChanged, onFinish: onFinish)
        }
        .opacity(max(0.35, session.instructionOpacity))
    }
}

/// "Done" button that must be held for 2 seconds; a ring fills while it's held.
struct ToolboxHoldToFinishButton: View {
    var ink: Color
    var progress: Double
    var onPressingChanged: (Bool) -> Void
    var onFinish: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(ink.opacity(0.2), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(ink.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            Text("Done")
                .font(.system(size: 13, weight: .semibold))
            Text("hold 2 s")
                .font(.system(size: 11))
                .opacity(0.7)
        }
        .foregroundStyle(ink.opacity(0.85))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(ink.opacity(0.08)))
        .overlay(Capsule().strokeBorder(ink.opacity(0.25), lineWidth: 1))
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: ToolboxScreenCleaningTiming.hold, maximumDistance: 40,
                            perform: onFinish, onPressingChanged: onPressingChanged)
        .accessibilityLabel("Finish screen cleaning")
        .accessibilityHint("Press and hold for two seconds")
        .accessibilityAction { onFinish() }
    }
}
