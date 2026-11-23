//
//  LockScreenPlayerController.swift
//  boringNotch — Pulau fork
//
//  A large Now Playing widget shown in the middle of the macOS lock screen.
//
//  How it works: a borderless panel is created when the screen locks and is
//  "delegated" to the lock-screen space through the private SkyLight framework
//  (the same mechanism Boring Notch uses for "Show notch on lock screen").
//  Because SkyLight is private API it can break in a future macOS update; the
//  feature is behind a toggle and does nothing when it's off.
//
//  Privacy: while locked, `PulauLockScreen.isLocked` is true. The notch hides
//  the Focus and Assistant tabs and refuses keyboard focus (see
//  TabSelectionView / NotchInputFocus), so to-dos, clipboard history and chat
//  are never visible or editable on the lock screen.
//

import AppKit
import Combine
import Defaults
import SkyLightWindow
import SwiftUI

@MainActor
final class PulauLockScreen: ObservableObject {
    static let shared = PulauLockScreen()

    /// Mirrors the lock state for non-SwiftUI readers (tab list, input focus).
    nonisolated(unsafe) static var isLocked = false

    @Published private(set) var locked = false
    /// True while the Settings "Preview" is on screen (desktop, no SkyLight).
    @Published private(set) var previewing = false

    private var panel: LockScreenPlayerPanel?
    /// EXPERIMENTAL full-screen, click-through album-art backdrop. Only
    /// created while its toggle is on: when off there is no extra window at
    /// all over the lock screen. A previous version at a high window level
    /// covered the macOS clock/password field and blocked typing the password.
    private var backdrop: LockScreenPlayerPanel?
    /// Windows currently moved to the lock-screen space via SkyLight.
    private var delegated: [NSWindow] = []
    private var onLockScreen = false
    private var hideTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var observers = Set<AnyCancellable>()

    static let panelSize = NSSize(width: 560, height: 212)

    private init() {
        Defaults.publisher(.pulauLockScreenPlayerOffset, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.reposition() } }
            .store(in: &observers)

        Defaults.publisher(.pulauLockScreenPlayer, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self, self.locked else { return }
                    change.newValue ? self.show(onLockScreen: true) : self.hide()
                }
            }
            .store(in: &observers)

        Defaults.publisher(.pulauLockScreenArtBackdrop, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self, self.panel?.isVisible == true else { return }
                    change.newValue ? self.attachBackdrop() : self.detachBackdrop()
                }
            }
            .store(in: &observers)

        Defaults.publisher(.pulauLockScreenBackdropLayer, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.backdrop?.level = Self.backdropLevel }
            }
            .store(in: &observers)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.reposition() } }
            .store(in: &observers)
    }

    // MARK: Lock events (called from AppDelegate)

    func screenLocked() {
        locked = true
        PulauLockScreen.isLocked = true
        NotchInputFocus.shared.end()
        if [NotchViews.focus, .assistant].contains(BoringViewCoordinator.shared.currentView) {
            BoringViewCoordinator.shared.currentView = .home
        }
        cancelPreview()
        guard Defaults[.pulauLockScreenPlayer] else { return }
        show(onLockScreen: true)
    }

    func screenUnlocked() {
        locked = false
        PulauLockScreen.isLocked = false
        hide()
    }

    // MARK: Preview (Settings)

    /// Shows the widget on the normal desktop for a few seconds so the user can
    /// check the look and vertical position without locking the Mac.
    func preview(seconds: Double = 6) {
        guard !locked else { return }
        previewTask?.cancel()
        previewing = true
        show(onLockScreen: false)
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.cancelPreview()
        }
    }

    private func cancelPreview() {
        previewTask?.cancel()
        previewTask = nil
        guard previewing else { return }
        previewing = false
        if !locked { hide() }
    }

    // MARK: Window

    private func show(onLockScreen: Bool) {
        hideTask?.cancel()
        hideTask = nil

        self.onLockScreen = onLockScreen
        let panel = self.panel ?? makePanel()
        self.panel = panel
        reposition()

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        delegateIfNeeded(panel)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        if Defaults[.pulauLockScreenArtBackdrop] { attachBackdrop() }
    }

    private func delegateIfNeeded(_ window: NSWindow) {
        guard onLockScreen, !delegated.contains(where: { $0 === window }) else { return }
        SkyLightOperator.shared.delegateWindow(window)
        delegated.append(window)
    }

    private func undelegate(_ window: NSWindow) {
        guard let index = delegated.firstIndex(where: { $0 === window }) else { return }
        SkyLightOperator.shared.undelegateWindow(window)
        delegated.remove(at: index)
    }

    // MARK: Backdrop (experimental)

    /// Lowest = just above the desktop picture; Normal = regular app level.
    /// Both are far below the level that broke password entry before.
    static var backdropLevel: NSWindow.Level {
        switch Defaults[.pulauLockScreenBackdropLayer] {
        case "normal": return .normal
        default: return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        }
    }

    private func attachBackdrop() {
        guard backdrop == nil, let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        let window = LockScreenPlayerPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = Self.backdropLevel
        window.ignoresMouseEvents = true
        let host = NSHostingView(rootView: LockScreenBackdropView())
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        window.setFrame(frame, display: true)
        window.alphaValue = 0
        window.orderFrontRegardless()
        backdrop = window
        delegateIfNeeded(window)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            window.animator().alphaValue = 1
        }
    }

    private func detachBackdrop() {
        guard let window = backdrop else { return }
        backdrop = nil
        undelegate(window)
        window.orderOut(nil)
    }

    private func hide() {
        // The backdrop goes first and immediately: it is the window that can
        // get in the way of the system lock UI.
        detachBackdrop()
        guard let panel else { return }
        hideTask?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }
        // Wait for the unlock transition before leaving the lock-screen space,
        // otherwise the widget flashes on the desktop.
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, let panel = self.panel else { return }
            self.undelegate(panel)
            panel.orderOut(nil)
            self.onLockScreen = false
        }
    }

    private func makePanel() -> LockScreenPlayerPanel {
        let panel = LockScreenPlayerPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let host = NSHostingView(rootView: LockScreenPlayerView())
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    /// Centers the widget horizontally on the primary display (where macOS
    /// draws the lock screen UI), with a user-adjustable vertical offset.
    private func reposition() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        backdrop?.setFrame(frame, display: true)
        guard let panel else { return }
        let size = Self.panelSize
        let offset = CGFloat(Defaults[.pulauLockScreenPlayerOffset])
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2 + offset
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// Borderless, never-key panel. It accepts clicks for the playback buttons but
/// can never receive keyboard input.
final class LockScreenPlayerPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        level = .mainMenu + 4
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        sharingType = Defaults[.hideFromScreenRecording] ? .none : .readWrite
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
