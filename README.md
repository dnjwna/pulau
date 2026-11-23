<h1 align="center">Pulau</h1>

<p align="center">
  <b>Your notch, finally useful.</b><br>
  A free, open-source macOS notch app: synced lyrics, focus tools, an AI assistant and a lock-screen player.<br>
  Built on <a href="https://github.com/TheBoredTeam/boring.notch">Boring Notch</a> (GPL-3.0).
</p>

<!-- DEMO VIDEO: edit this file on GitHub and drag the MP4 here; GitHub will host it. -->

---

**Pulau** (Indonesian for *island*) is a fork of Boring Notch. It keeps everything upstream does (music controls, file shelf, HUD replacement, calendar, battery, mirror) and adds the features below.

## What's new in Pulau

| Feature | What it does |
|---|---|
| **Lyrics** | Karaoke view in the notch: time-synced lines auto-scroll and highlight, click a line to seek, adjustable sync offset. Lyrics come from [LRCLIB](https://lrclib.net) (free, no account): exact match by duration, then a scored search fallback that prefers synced lyrics. |
| **Focus** | Pomodoro timer (wall-clock based, no drift), a persistent to-do list, and clipboard history (text only, kept in memory, skips items marked concealed by password managers). |
| **Assistant** | Streaming chat with any OpenAI-compatible endpoint. Default is **Ollama on localhost** (free and offline). Presets for LM Studio, Groq, Gemini, OpenRouter and OpenAI. Clipboard quick actions: Summarize, Explain, To English, Fix grammar. API keys are stored in the macOS Keychain. |
| **Lock-screen player** *(beta)* | A Now Playing widget in the middle of the lock screen: artwork, title, the current lyric line, progress and playback controls. While the Mac is locked, the Focus and Assistant tabs are hidden and text input is disabled. |
| **Presence** *(experimental, off by default)* | On-device face *detection* pauses music when you walk away and resumes when you're back. It detects any face, not you specifically. Not a security feature and never unlocks anything. |
| **Shortcuts** | `⌃⌥J` open the Assistant · `⌃⌥P` start/pause the focus timer (rebind in Settings → Pulau). |

## Build from source

Requirements: macOS 15.6+, Xcode 26+.

1. Clone the repo and open `boringNotch.xcodeproj`.
2. Signing uses **Sign to Run Locally**, so no Apple Developer account is needed.
3. Select the **boringNotch** scheme and press `⌘R`.
4. Open Settings → **Pulau** to configure tabs, the timer, the assistant and the lock-screen player.

### Free local AI (recommended)

```bash
brew install ollama
ollama serve          # leave running
ollama pull llama3.2  # ~2 GB; smaller options: qwen2.5:3b, gemma3:4b
```

Then Settings → Pulau → Assistant → **Test connection**.

Cloud providers (Gemini, Groq, …) work too: pick a preset, paste your API key, and choose a model. Response speed depends on the provider and model.

## Known limitations

- **The lock-screen player uses a private macOS API (SkyLight)**, the same one Boring Notch uses for "Show notch on lock screen". It may stop working after a macOS update.
- **No Face ID–style unlock.** This is intentional: webcam face detection is not secure.
- The focus timer is only visible in the open notch; there is no closed-notch countdown yet.
- The assistant is text-only (no voice input yet).
- **Don't use "Check for Updates".** The Sparkle feed still points at upstream Boring Notch and would replace Pulau. Automatic update checks are turned off.
- Builds are not notarized. On first launch macOS will warn about an unidentified developer: right-click the app → **Open**.

## Changes vs upstream

New code lives in `boringNotch/Pulau/` (a synchronized Xcode folder, so new files are picked up automatically). Edited upstream files:

- `enums/generic.swift`: new `NotchViews` cases
- `ContentView.swift`: routes the new tabs
- `components/Tabs/TabSelectionView.swift`, `TabButton.swift`: dynamic tab list (Focus/Assistant hidden while locked)
- `components/Notch/BoringHeader.swift`: shows tabs when Pulau tabs are on
- `components/Notch/BoringNotchWindow.swift`, `BoringNotchSkyLightWindow.swift`: key window only while a Pulau text field is active
- `managers/MusicManager.swift`: lyrics pipeline replaced by `LyricsService`
- `Shortcuts/ShortcutConstants.swift`, `boringNotchApp.swift`: new shortcuts, service bootstrap, lock/unlock hooks
- `components/Settings/SettingsView.swift`: Pulau settings pane
- `Info.plist`: Sparkle automatic checks off
- `project.pbxproj`: `Pulau` folder group, display name

## Credits & license

Pulau is a fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam and contributors; all upstream features and most of the app are their work. Lyrics are provided by [LRCLIB](https://lrclib.net). See `THIRD_PARTY_LICENSES` for bundled dependencies.

Licensed under **GPL-3.0**, the same as upstream (see `LICENSE`). If you distribute builds, you must also publish the source.
