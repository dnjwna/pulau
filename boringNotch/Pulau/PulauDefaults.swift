//
//  PulauDefaults.swift
//  boringNotch — Pulau fork
//
//  Settings keys for the Pulau additions (Lyrics, Focus, Assistant, Presence).
//  Secrets (API keys) are NOT stored here; see KeychainStore.
//

import Defaults
import Foundation

struct TodoItem: Codable, Hashable, Identifiable, Defaults.Serializable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
    var createdAt: Date = Date()
}

extension Defaults.Keys {
    // MARK: Tabs
    static let pulauLyricsTab = Key<Bool>("pulauLyricsTab", default: true)
    static let pulauFocusTab = Key<Bool>("pulauFocusTab", default: true)
    static let pulauAssistantTab = Key<Bool>("pulauAssistantTab", default: true)

    // MARK: Lyrics
    /// Global offset applied to synced lyrics, in seconds. Positive = lyrics appear earlier.
    static let pulauLyricsOffset = Key<Double>("pulauLyricsOffset", default: 0.3)

    // MARK: Focus (Pomodoro)
    static let pomodoroWorkMinutes = Key<Int>("pomodoroWorkMinutes", default: 25)
    static let pomodoroShortBreakMinutes = Key<Int>("pomodoroShortBreakMinutes", default: 5)
    static let pomodoroLongBreakMinutes = Key<Int>("pomodoroLongBreakMinutes", default: 15)
    static let pomodoroSessionsBeforeLongBreak = Key<Int>("pomodoroSessionsBeforeLongBreak", default: 4)
    static let pomodoroAutoStartNext = Key<Bool>("pomodoroAutoStartNext", default: false)
    static let pomodoroPauseMusicOnBreak = Key<Bool>("pomodoroPauseMusicOnBreak", default: false)
    static let pomodoroCompletedToday = Key<Int>("pomodoroCompletedToday", default: 0)
    static let pomodoroCompletedDay = Key<String>("pomodoroCompletedDay", default: "")

    // MARK: To-do
    static let pulauTodos = Key<[TodoItem]>("pulauTodos", default: [])

    // MARK: Clipboard history
    static let clipboardHistoryEnabled = Key<Bool>("clipboardHistoryEnabled", default: true)
    static let clipboardHistoryLimit = Key<Int>("clipboardHistoryLimit", default: 25)

    // MARK: Assistant (OpenAI-compatible endpoint; Ollama by default = free & local)
    static let assistantBaseURL = Key<String>("assistantBaseURL", default: "http://localhost:11434/v1")
    static let assistantModel = Key<String>("assistantModel", default: "llama3.2")
    static let assistantSystemPrompt = Key<String>(
        "assistantSystemPrompt",
        default: "You are a concise assistant living in the user's MacBook notch. Answer in at most 4 short sentences unless asked for more. Reply in the user's language."
    )
    static let assistantMaxHistoryTurns = Key<Int>("assistantMaxHistoryTurns", default: 6)
    /// "auto" = send "minimal" to Gemini, nothing elsewhere. "off" = never send.
    /// Otherwise sent verbatim as `reasoning_effort` (minimal / low / medium / high).
    static let assistantReasoningEffort = Key<String>("assistantReasoningEffort", default: "auto")

    // MARK: Lock-screen player
    static let pulauLockScreenPlayer = Key<Bool>("pulauLockScreenPlayer", default: true)
    static let pulauLockScreenShowLyrics = Key<Bool>("pulauLockScreenShowLyrics", default: true)
    /// Light up the active lyric line word by word (timing estimated unless the lyrics have word tags).
    static let pulauLockScreenWordHighlight = Key<Bool>("pulauLockScreenWordHighlight", default: true)
    /// Vertical offset from the screen centre, in points. Positive = higher.
    static let pulauLockScreenPlayerOffset = Key<Double>("pulauLockScreenPlayerOffset", default: 0)
    /// Hide the lock-screen card after this many minutes paused. 0 = never.
    static let pulauLockScreenHideAfterPauseMinutes = Key<Int>("pulauLockScreenHideAfterPauseMinutes", default: 5)

    // MARK: Presence (experimental, non-security)
    static let presenceEnabled = Key<Bool>("presenceEnabled", default: false)
    static let presenceAwaySeconds = Key<Int>("presenceAwaySeconds", default: 20)
    static let presenceAutoResume = Key<Bool>("presenceAutoResume", default: true)
}

enum PulauFeatures {
    static var anyTabEnabled: Bool {
        Defaults[.pulauLyricsTab] || Defaults[.pulauFocusTab] || Defaults[.pulauAssistantTab]
    }
}
