//
//  NotchInputFocus.swift
//  boringNotch — Pulau fork
//
//  The notch panel normally refuses key status so it never steals focus.
//  Text input (Assistant, To-do) needs key status, so we grant it only while
//  a Pulau text field is being edited, and keep the notch open during that time.
//

import AppKit
import SwiftUI

@MainActor
final class NotchInputFocus: ObservableObject {
    static let shared = NotchInputFocus()

    /// Read by the notch windows' `canBecomeKey`. Only ever mutated on the main thread.
    nonisolated(unsafe) static var allowsKeyWindow = false

    @Published private(set) var wantsKey = false

    private weak var keyedWindow: NSWindow?
    private var resignObserver: NSObjectProtocol?
    private var holdsNotchOpen = false

    private init() {}

    /// Call when the user starts interacting with a text field inside the notch.
    func begin(in window: NSWindow?) {
        guard let window, !PulauLockScreen.isLocked else { return }
        if !holdsNotchOpen {
            holdsNotchOpen = true
            SharingStateManager.shared.beginInteraction()
        }
        wantsKey = true
        NotchInputFocus.allowsKeyWindow = true
        keyedWindow = window
        window.makeKey()

        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.end() }
            }
        }
    }

    /// Call on submit / escape / focus loss. Safe to call multiple times.
    func end() {
        wantsKey = false
        NotchInputFocus.allowsKeyWindow = false
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        keyedWindow = nil
        if holdsNotchOpen {
            holdsNotchOpen = false
            SharingStateManager.shared.endInteraction()
            SharingStateManager.shared.requestCloseIfReady()
        }
    }

    var isActive: Bool { holdsNotchOpen }
}

/// Exposes the hosting NSWindow to SwiftUI (reports only when it changes).
struct HostingWindowReader: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    final class ReaderView: NSView {
        var onResolve: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = self.window
            DispatchQueue.main.async { [weak self] in
                self?.onResolve?(window)
            }
        }
    }

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onResolve = onResolve
    }
}

extension Notification.Name {
    /// Posted to programmatically focus the assistant input (global shortcut).
    static let pulauFocusAssistantInput = Notification.Name("pulauFocusAssistantInput")
}

struct NotchTextField: View {
    let placeholder: String
    @Binding var text: String
    var focusNotification: Notification.Name? = nil
    var onSubmit: () -> Void
    var onEscape: () -> Void = {}

    @FocusState private var focused: Bool
    @State private var window: NSWindow?

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(PulauTheme.body)
            .foregroundStyle(PulauTheme.primaryText)
            .focused($focused)
            .onSubmit {
                onSubmit()
            }
            .onExitCommand {
                focused = false
                NotchInputFocus.shared.end()
                onEscape()
            }
            .background(HostingWindowReader { resolved in if window !== resolved { window = resolved } })
            .simultaneousGesture(TapGesture().onEnded { activate() })
            .onChange(of: focused) { _, isFocused in
                if !isFocused { NotchInputFocus.shared.end() }
            }
            .onDisappear {
                NotchInputFocus.shared.end()
            }
            .onReceive(NotificationCenter.default.publisher(for: focusNotification ?? Notification.Name("pulau.none"))) { _ in
                guard focusNotification != nil else { return }
                activate()
            }
    }

    private func activate() {
        NotchInputFocus.shared.begin(in: window)
        // Focus after the window has become key, otherwise the field ignores it.
        DispatchQueue.main.async { focused = true }
    }
}
