# Pulau — a Boring Notch fork

Pulau ("island") is a fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch) (GPL-3.0).
It keeps everything upstream does (media, shelf, HUDs, calendar, battery, mirror) and adds:

| Tab / feature | What it does |
|---|---|
| **Lyrics** | Karaoke view: time-synced lines auto-scroll and highlight, click a line to seek, ±offset control. LRCLIB exact match by duration → scored search fallback (synced first) → Apple Music embedded lyrics. Cached in memory. |
| **Focus** | Pomodoro (wall-clock based, no drift), to-do list (persisted), clipboard history (text only, memory only, skips password-manager items). |
| **Assistant** | Streaming chat with any OpenAI-compatible endpoint. Default: **Ollama on localhost (free, offline)**. Presets for LM Studio, Groq, Gemini, OpenRouter, OpenAI. Clipboard quick actions: Summarize / Explain / Translate / Fix grammar. API key lives in the Keychain. |
| **Presence** *(experimental, off by default)* | On-device Vision face *detection* pauses music when you walk away, resumes when you're back. Not identity, not security, never unlocks anything. |
| **Shortcuts** | `⌃⌥J` open Assistant and focus input · `⌃⌥P` start/pause timer (rebind in Settings → Pulau). |

## Build

Requirements (from upstream): macOS 15.6+, Xcode 26+.

1. Open `boringNotch.xcodeproj`.
2. Target **boringNotch** → *Signing & Capabilities* → Team: pick your **Personal Team** (free Apple ID). Do the same for **BoringNotchXPCHelper**.
3. Scheme **boringNotch** → `⌘R`.
4. Settings → **Pulau** to configure tabs, timer, assistant.

### Free local AI (recommended)

```bash
brew install ollama
ollama serve          # leave running
ollama pull llama3.2  # ~2 GB; or qwen2.5:3b, gemma3:4b
```

Then Settings → Pulau → Assistant → **Test connection**.

## Changes vs upstream

New code lives in `boringNotch/Pulau/` (synchronized Xcode folder: new files are picked up automatically).
Edited upstream files:

- `enums/generic.swift` — new `NotchViews` cases
- `ContentView.swift` — routes the new tabs
- `components/Tabs/TabSelectionView.swift`, `TabButton.swift` — dynamic tab list
- `components/Notch/BoringHeader.swift` — show tabs when Pulau tabs are on
- `components/Notch/BoringNotchWindow.swift`, `BoringNotchSkyLightWindow.swift` — key-window only while a Pulau text field is active
- `managers/MusicManager.swift` — lyrics pipeline replaced by `LyricsService`
- `Shortcuts/ShortcutConstants.swift`, `boringNotchApp.swift` — new shortcuts + service bootstrap
- `components/Settings/SettingsView.swift` — Pulau pane
- `Info.plist` — Sparkle automatic checks **off** (the feed still points at upstream: "Check for Updates" would install upstream Boring Notch over this fork)
- `project.pbxproj` — `Pulau` folder group, display name

## Known limitations

- No lock-screen player and no Face ID unlock (Canopy has these; webcam face unlock is not secure).
- Timer is only visible in the open notch (no closed-notch live activity yet).
- Assistant is text-only (no voice yet).

## License

GPL-3.0, same as upstream. If you distribute builds you must publish the source.
