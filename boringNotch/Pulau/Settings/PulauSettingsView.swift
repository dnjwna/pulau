//
//  PulauSettingsView.swift
//  boringNotch — Pulau fork
//
//  Settings → Pulau: tabs, lyrics, focus timer, clipboard, assistant, presence.
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct PulauSettingsView: View {
    @Default(.assistantBaseURL) private var baseURL
    @Default(.assistantModel) private var model
    @Default(.assistantSystemPrompt) private var systemPrompt
    @Default(.assistantReasoningEffort) private var reasoningEffort
    @Default(.pomodoroWorkMinutes) private var workMinutes
    @Default(.pomodoroShortBreakMinutes) private var shortBreak
    @Default(.pomodoroLongBreakMinutes) private var longBreak
    @Default(.pomodoroSessionsBeforeLongBreak) private var sessionsBeforeLong
    @Default(.presenceAwaySeconds) private var awaySeconds
    @Default(.pulauLyricsOffset) private var lyricsOffset
    @Default(.clipboardHistoryLimit) private var clipboardLimit
    @Default(.pulauLockScreenPlayerOffset) private var lockPlayerOffset
    @Default(.pulauLockScreenShowLyrics) private var lockShowLyrics

    @ObservedObject private var presence = PresenceMonitor.shared

    @State private var apiKey: String = KeychainStore.read(AssistantService.apiKeyAccount) ?? ""
    @State private var models: [String] = []
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle, testing, ok(Int), failed(String)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .pulauLyricsTab) { Text("Lyrics tab") }
                Defaults.Toggle(key: .pulauFocusTab) { Text("Focus tab (timer, to-do, clipboard)") }
                Defaults.Toggle(key: .pulauAssistantTab) { Text("Assistant tab") }
            } header: {
                Text("Tabs")
            } footer: {
                footnote("Tabs appear in the open notch next to Home. Shelf is controlled in the Shelf pane.")
            }

            Section {
                HStack {
                    Text("Sync offset")
                    Slider(value: $lyricsOffset, in: -2...2, step: 0.05)
                    Text(String(format: "%+.2fs", lyricsOffset))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
                Defaults.Toggle(key: .enableLyrics) { Text("Show current line on the Home tab") }
            } header: {
                Text("Lyrics")
            } footer: {
                footnote("Time-synced lyrics come from LRCLIB (free, no account). Positive offset shows lines earlier.")
            }

            Section {
                Stepper("Focus: \(workMinutes) min", value: $workMinutes, in: 5...120, step: 5)
                Stepper("Short break: \(shortBreak) min", value: $shortBreak, in: 1...30)
                Stepper("Long break: \(longBreak) min", value: $longBreak, in: 5...60, step: 5)
                Stepper("Long break every \(sessionsBeforeLong) sessions", value: $sessionsBeforeLong, in: 2...8)
                Defaults.Toggle(key: .pomodoroAutoStartNext) { Text("Auto-start the next phase") }
                Defaults.Toggle(key: .pomodoroPauseMusicOnBreak) { Text("Pause music when a break starts") }
                KeyboardShortcuts.Recorder("Start / pause timer:", name: .toggleFocusTimer)
            } header: {
                Text("Focus timer")
            }

            Section {
                Defaults.Toggle(key: .clipboardHistoryEnabled) { Text("Keep clipboard history") }
                Stepper("Keep last \(clipboardLimit) items", value: $clipboardLimit, in: 5...100, step: 5)
            } header: {
                Text("Clipboard")
            } footer: {
                footnote("Text only, memory only — cleared when the app quits. Items marked as passwords by password managers are skipped.")
            }

            assistantSection

            Section {
                Defaults.Toggle(key: .pulauLockScreenPlayer) {
                    HStack {
                        Text("Show player on the lock screen")
                        customBadge(text: "Beta")
                    }
                }
                Defaults.Toggle(key: .pulauLockScreenShowLyrics) { Text("Show the current lyric line") }
                Defaults.Toggle(key: .pulauLockScreenWordHighlight) { Text("Highlight lyrics word by word") }
                    .disabled(!lockShowLyrics)
                HStack {
                    Text("Vertical position")
                    Slider(value: $lockPlayerOffset, in: -400...400, step: 10)
                    Text(String(format: "%+.0f pt", lockPlayerOffset))
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
                HStack {
                    Button("Preview for 6 seconds") { PulauLockScreen.shared.preview() }
                    Button("Reset position") { lockPlayerOffset = 0 }
                }
            } header: {
                Text("Lock screen")
            } footer: {
                footnote("Shows a Now Playing widget in the middle of the lock screen while music is playing. Uses a private macOS API, so it may stop working after a macOS update. Word timing is estimated from each line's length unless the lyrics include word timestamps. To-dos, clipboard and Assistant are never shown while locked.")
            }

            Section {
                Defaults.Toggle(key: .presenceEnabled) {
                    HStack {
                        Text("Pause music when I walk away")
                        customBadge(text: "Experimental")
                    }
                }
                Stepper("Away after \(awaySeconds) s without a face", value: $awaySeconds, in: 5...300, step: 5)
                Defaults.Toggle(key: .presenceAutoResume) { Text("Resume when I'm back") }
                LabeledContent("Status", value: presence.status.label)
            } header: {
                Text("Presence")
            } footer: {
                footnote("Uses on-device face *detection* (any face, not you specifically). Not a security feature and does not unlock your Mac. The camera light stays on while this is enabled.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Pulau")
    }

    // MARK: Assistant

    private var assistantSection: some View {
        Section {
            Picker("Preset", selection: presetBinding) {
                Text("Custom").tag("")
                ForEach(AssistantPreset.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }

            TextField("Base URL", text: $baseURL)

            HStack {
                if models.isEmpty {
                    TextField("Model", text: $model)
                } else {
                    Picker("Model", selection: $model) {
                        if !models.contains(model) { Text(model).tag(model) }
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                }
            }

            Picker("Thinking", selection: $reasoningEffort) {
                Text("Auto (fastest on Gemini)").tag("auto")
                Text("Don't send").tag("off")
                Text("Minimal").tag("minimal")
                Text("Low").tag("low")
                Text("Medium").tag("medium")
                Text("High").tag("high")
            }
            .onChange(of: reasoningEffort) { _, _ in AssistantService.resetThinkingNegotiation() }

            SecureField("API key (optional for local)", text: $apiKey)
                .onChange(of: apiKey) { _, newValue in
                    KeychainStore.write(newValue, account: AssistantService.apiKeyAccount)
                }

            HStack {
                Button("Test connection") { Task { await testConnection() } }
                    .disabled(testState == .testing)
                switch testState {
                case .idle: EmptyView()
                case .testing: ProgressView().controlSize(.small)
                case .ok(let count):
                    Label("Connected · \(count) models", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(2)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("System prompt")
                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .frame(minHeight: 60)
            }

            KeyboardShortcuts.Recorder("Open assistant:", name: .openAssistant)
        } header: {
            Text("Assistant")
        } footer: {
            footnote("Any OpenAI-compatible endpoint. Free options: Ollama or LM Studio running locally (nothing leaves your Mac), or a free-tier key from Groq / Google AI Studio. Keys are stored in the macOS Keychain. Use Test connection to load the provider's current model list. Thinking sets `reasoning_effort`: lower = faster first word; pick \"Don't send\" if a provider rejects it.")
        }
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { AssistantPreset.all.first { $0.baseURL == baseURL }?.id ?? "" },
            set: { id in
                guard let preset = AssistantPreset.all.first(where: { $0.id == id }) else { return }
                baseURL = preset.baseURL
                model = preset.defaultModel
                models = []
                testState = .idle
            }
        )
    }

    private func testConnection() async {
        testState = .testing
        do {
            let list = try await AssistantService.fetchModels(baseURL: baseURL, apiKey: apiKey)
            models = list
            testState = .ok(list.count)
        } catch {
            testState = .failed(error.localizedDescription)
        }
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
    }
}

struct AssistantPreset: Identifiable {
    let id: String
    let name: String
    let baseURL: String
    let defaultModel: String

    static let all: [AssistantPreset] = [
        AssistantPreset(id: "ollama", name: "Ollama (local, free)", baseURL: "http://localhost:11434/v1", defaultModel: "llama3.2"),
        AssistantPreset(id: "lmstudio", name: "LM Studio (local, free)", baseURL: "http://localhost:1234/v1", defaultModel: "local-model"),
        AssistantPreset(id: "groq", name: "Groq (free tier, key)", baseURL: "https://api.groq.com/openai/v1", defaultModel: "llama-3.1-8b-instant"),
        AssistantPreset(id: "gemini", name: "Google Gemini (free tier, key)", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", defaultModel: "gemini-3.8-flash"),
        AssistantPreset(id: "openrouter", name: "OpenRouter (key)", baseURL: "https://openrouter.ai/api/v1", defaultModel: "openrouter/auto"),
        AssistantPreset(id: "openai", name: "OpenAI (key)", baseURL: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini")
    ]
}
