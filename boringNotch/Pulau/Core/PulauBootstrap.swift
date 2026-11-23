//
//  PulauBootstrap.swift
//  boringNotch — Pulau fork
//
//  Wakes up the long-lived Pulau services once at launch. Each service
//  observes its own Defaults key and starts/stops itself.
//

import Combine
import Defaults
import Foundation

@MainActor
enum PulauBootstrap {
    private static var started = false
    private static var observers = Set<AnyCancellable>()

    static func start() {
        guard !started else { return }
        started = true

        _ = ClipboardMonitor.shared      // starts if clipboardHistoryEnabled
        _ = PresenceMonitor.shared       // starts if presenceEnabled
        _ = FocusTimer.shared
        _ = PulauLockScreen.shared

        // Keep the idle timer in sync with duration edits in Settings.
        Defaults.publisher(keys: .pomodoroWorkMinutes, .pomodoroShortBreakMinutes, .pomodoroLongBreakMinutes, options: [])
            .receive(on: DispatchQueue.main)
            .sink { _ in
                Task { @MainActor in FocusTimer.shared.durationsChanged() }
            }
            .store(in: &observers)
    }
}
