//
//  FocusTimer.swift
//  boringNotch — Pulau fork
//
//  Pomodoro engine. Wall-clock based (end date), so sleep/wake and UI
//  throttling never drift the countdown.
//

import AppKit
import Combine
import Defaults
import Foundation

@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    enum Phase: String {
        case work, shortBreak, longBreak

        var title: String {
            switch self {
            case .work: return "Focus"
            case .shortBreak: return "Short break"
            case .longBreak: return "Long break"
            }
        }

        var systemImage: String {
            switch self {
            case .work: return "brain.head.profile"
            case .shortBreak: return "cup.and.saucer.fill"
            case .longBreak: return "figure.walk"
            }
        }
    }

    @Published private(set) var phase: Phase = .work
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var sessionsInCycle = 0
    @Published private(set) var completedToday: Int

    private var endDate: Date?
    private var ticker: AnyCancellable?

    private init() {
        remaining = TimeInterval(Defaults[.pomodoroWorkMinutes] * 60)
        completedToday = 0
        rollDayIfNeeded()
        completedToday = Defaults[.pomodoroCompletedToday]
    }

    // MARK: Derived

    var phaseDuration: TimeInterval {
        let minutes: Int
        switch phase {
        case .work: minutes = Defaults[.pomodoroWorkMinutes]
        case .shortBreak: minutes = Defaults[.pomodoroShortBreakMinutes]
        case .longBreak: minutes = Defaults[.pomodoroLongBreakMinutes]
        }
        return TimeInterval(max(1, minutes) * 60)
    }

    var progress: Double {
        guard phaseDuration > 0 else { return 0 }
        return 1 - (remaining / phaseDuration)
    }

    var formattedRemaining: String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: Controls

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        if remaining <= 0 { remaining = phaseDuration }
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        startTicker()
        if phase != .work, Defaults[.pomodoroPauseMusicOnBreak], MusicManager.shared.isPlaying {
            MusicManager.shared.pause()
        }
    }

    func pause() {
        guard isRunning else { return }
        tick()
        isRunning = false
        endDate = nil
        ticker = nil
    }

    func reset() {
        isRunning = false
        endDate = nil
        ticker = nil
        remaining = phaseDuration
    }

    func skip() {
        advancePhase(completedWork: false)
    }

    /// Called when durations change in Settings.
    func durationsChanged() {
        if !isRunning { remaining = phaseDuration }
    }

    // MARK: Engine

    private func startTicker() {
        ticker = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            finishPhase()
        }
    }

    private func finishPhase() {
        isRunning = false
        endDate = nil
        ticker = nil
        NSSound(named: NSSound.Name(phase == .work ? "Glass" : "Hero"))?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        advancePhase(completedWork: phase == .work)
        if Defaults[.pomodoroAutoStartNext] { start() }
    }

    private func advancePhase(completedWork: Bool) {
        isRunning = false
        endDate = nil
        ticker = nil

        switch phase {
        case .work:
            if completedWork {
                rollDayIfNeeded()
                completedToday += 1
                Defaults[.pomodoroCompletedToday] = completedToday
            }
            sessionsInCycle += 1
            phase = sessionsInCycle >= max(1, Defaults[.pomodoroSessionsBeforeLongBreak]) ? .longBreak : .shortBreak
        case .shortBreak:
            phase = .work
        case .longBreak:
            sessionsInCycle = 0
            phase = .work
        }
        remaining = phaseDuration
    }

    private func rollDayIfNeeded() {
        let today = Self.dayStamp(Date())
        if Defaults[.pomodoroCompletedDay] != today {
            Defaults[.pomodoroCompletedDay] = today
            Defaults[.pomodoroCompletedToday] = 0
            completedToday = 0
        }
    }

    private static func dayStamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
